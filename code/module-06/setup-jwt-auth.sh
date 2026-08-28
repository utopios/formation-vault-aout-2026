#!/usr/bin/env bash
# setup-jwt-auth.sh — configure l'auth JWT dans Vault pour le pipeline PayLink.
# - active auth/jwt
# - declare la cle publique du "GitLab simule" + bound_issuer
# - cree le role paylink-deploy (bound_claims passes en JSON via heredoc :
#   en key=value la CLI echoue avec « expected a map, got 'string' »)
# Prerequis : lab demarre (conteneur vault), ./gen-keys.sh execute,
#             policy paylink-read existante.
# Usage : ./setup-jwt-auth.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINE="${ENGINE:-podman}"
ROOT_TOKEN="${ROOT_TOKEN:-root-token-formation}"
ISS="https://gitlab.example.com"

v() {
  $ENGINE exec -i \
    -e VAULT_ADDR=http://127.0.0.1:8200 \
    -e VAULT_TOKEN="$ROOT_TOKEN" \
    vault vault "$@"
}

if [ ! -f "$DIR/keys/gitlab-ci.pub" ]; then
  echo "Cle publique absente : lancez d'abord ./gen-keys.sh" >&2
  exit 1
fi

echo "### 1/3 Activation de la methode auth jwt"
v auth enable jwt 2>/dev/null || echo "(auth jwt deja activee, on continue)"

echo "### 2/3 Configuration : cle publique de verification + issuer attendu"
PUB="$(cat "$DIR/keys/gitlab-ci.pub")"
v write auth/jwt/config \
  jwt_validation_pubkeys="$PUB" \
  bound_issuer="$ISS"

echo "### 3/3 Role paylink-deploy (bound_claims EN JSON, pas en key=value)"
v write auth/jwt/role/paylink-deploy - <<EOF
{
  "role_type": "jwt",
  "bound_audiences": "https://vault.paylink.local",
  "bound_claims": {
    "project_id": "42",
    "ref": "main",
    "ref_type": "branch"
  },
  "user_claim": "project_path",
  "token_policies": "paylink-read",
  "token_ttl": "10m",
  "token_max_ttl": "15m"
}
EOF

echo
echo "### Verification du role"
v read auth/jwt/role/paylink-deploy

echo
echo "Auth JWT prete. Testez :"
echo "  JWT=\$(./gen-jwt.sh --ref main)"
echo "  $ENGINE exec -e VAULT_ADDR=http://127.0.0.1:8200 vault vault write auth/jwt/login role=paylink-deploy jwt=\"\$JWT\""
