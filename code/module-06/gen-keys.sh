#!/usr/bin/env bash
# gen-keys.sh — genere la paire RSA qui simule la cle de signature de GitLab CI.
# La cle privee signe les JWT du lab ; la cle publique est declaree dans Vault
# (auth/jwt/config, jwt_validation_pubkeys) a la place du JWKS de GitLab.
# Usage : ./gen-keys.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
KEYS="$DIR/keys"

mkdir -p "$KEYS"

if [ -f "$KEYS/gitlab-ci.key" ]; then
  echo "Cle privee deja presente : $KEYS/gitlab-ci.key (rien a faire)"
else
  openssl genrsa -out "$KEYS/gitlab-ci.key" 2048
  echo "Cle privee generee : $KEYS/gitlab-ci.key"
fi

openssl rsa -in "$KEYS/gitlab-ci.key" -pubout -out "$KEYS/gitlab-ci.pub"
echo "Cle publique exportee : $KEYS/gitlab-ci.pub"

chmod 600 "$KEYS/gitlab-ci.key"

echo
echo "Dans un vrai GitLab, cette cle est detenue par la plateforme et la cle"
echo "publique est exposee via https://gitlab.example.com/-/jwks. Ici, nous la"
echo "declarons directement dans Vault avec jwt_validation_pubkeys."
