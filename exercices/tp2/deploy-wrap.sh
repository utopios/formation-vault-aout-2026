#!/bin/bash
# ============================================================================
# deploy-wrap.sh — Côté OPÉRATEUR / outil de déploiement
#
# Génère un secret_id AppRole pour le rôle paylink-api, mais ne le lit
# JAMAIS en clair : il demande à Vault de l'envelopper (response wrapping)
# et ne transmet à l'application que le wrapping token, à usage unique
# et à durée de vie courte.
#
# Prérequis : le conteneur podman "vault" du lab est démarré (code/lab/lab-up.sh)
#             et le rôle auth/approle/role/paylink-api existe (démo 2.1).
#
# Usage :
#   ./deploy-wrap.sh [répertoire_de_livraison]   (défaut : ./handoff)
#
# Équivalent de l'alias du lab :
#   alias v='podman exec -e VAULT_ADDR=http://127.0.0.1:8200 \
#            -e VAULT_TOKEN=root-token-formation vault vault'
# ============================================================================
set -euo pipefail

VAULT_CONTAINER="${VAULT_CONTAINER:-vault}"
VAULT_ADDR_IN="http://127.0.0.1:8200"
OPERATOR_TOKEN="${OPERATOR_TOKEN:-root-token-formation}"
ROLE_NAME="${ROLE_NAME:-paylink-api}"
WRAP_TTL="${WRAP_TTL:-120s}"
HANDOFF_DIR="${1:-./handoff}"

# La CLI vault exécutée dans le conteneur, avec le token de l'opérateur.
vop() {
  podman exec -e VAULT_ADDR="$VAULT_ADDR_IN" -e VAULT_TOKEN="$OPERATOR_TOKEN" \
    "$VAULT_CONTAINER" vault "$@"
}

echo "[deploy] Rôle cible          : $ROLE_NAME"
echo "[deploy] Wrap TTL            : $WRAP_TTL"
mkdir -p "$HANDOFF_DIR"

# 1. Le role_id n'est PAS un secret : c'est l'identifiant public du rôle.
ROLE_ID=$(vop read -field=role_id "auth/approle/role/$ROLE_NAME/role-id")
printf '%s\n' "$ROLE_ID" > "$HANDOFF_DIR/role-id.txt"
echo "[deploy] role_id             : $ROLE_ID"

# 2. Génération du secret_id SANS jamais le voir : Vault le range dans son
#    cubbyhole et ne nous rend qu'un wrapping token à usage unique.
WRAPPING_TOKEN=$(vop write -wrap-ttl="$WRAP_TTL" -f -field=wrapping_token \
  "auth/approle/role/$ROLE_NAME/secret-id")
printf '%s\n' "$WRAPPING_TOKEN" > "$HANDOFF_DIR/wrapping-token.txt"
chmod 600 "$HANDOFF_DIR/wrapping-token.txt"
echo "[deploy] wrapping_token      : ${WRAPPING_TOKEN:0:24}... (usage unique, TTL $WRAP_TTL)"

# 3. Trace d'audit locale : l'accessor permet de retrouver / révoquer le
#    secret_id plus tard, sans connaître sa valeur.
vop write "sys/wrapping/lookup" "token=$WRAPPING_TOKEN" \
  > "$HANDOFF_DIR/wrapping-lookup.txt" || true

echo "[deploy] Livraison déposée dans $HANDOFF_DIR/ :"
ls -l "$HANDOFF_DIR"
echo "[deploy] Le secret_id n'est jamais apparu à l'écran ni dans ce script."
echo "[deploy] Lancez maintenant ./app-unwrap-login.sh $HANDOFF_DIR (dans les $WRAP_TTL)."
