#!/usr/bin/env bash
# pipeline-deploy.sh — joue le job "deploy" du pipeline PayLink, en local,
# SANS AUCUN SECRET STOCKE cote CI :
#   1. obtient un id_token (simule par gen-jwt.sh, signe RS256)
#   2. se logue sur Vault via auth/jwt (role paylink-deploy)
#   3. lit secret/paylink/api avec le token de job (policy paylink-read)
#   4. genere l'artefact de configuration du deploiement
#   5. revoque son token en fin de job
#
# Usage : ./pipeline-deploy.sh [ref]     (defaut : main)
#   ./pipeline-deploy.sh main            -> doit reussir
#   ./pipeline-deploy.sh feature/hack    -> doit etre refuse par Vault
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINE="${ENGINE:-podman}"
VAULT_ADDR_LAB=http://127.0.0.1:8200

# --- Variables "predefinies GitLab CI" simulees -----------------------------
CI_COMMIT_REF_NAME="${1:-main}"
CI_PROJECT_ID="${CI_PROJECT_ID:-42}"
CI_PROJECT_PATH="${CI_PROJECT_PATH:-utopios/paylink-api}"
CI_PIPELINE_ID="${CI_PIPELINE_ID:-1337}"

step() { printf '\n== %s ==\n' "$*"; }

step "Job deploy — projet $CI_PROJECT_PATH — ref $CI_COMMIT_REF_NAME"
echo "Aucune variable VAULT_TOKEN dans la CI : le job va prouver son identite."

# --- 1. id_token ------------------------------------------------------------
step "1/5 Obtention de l'id_token (id_tokens: de GitLab, simule ici)"
JWT="$("$DIR/gen-jwt.sh" \
  --ref "$CI_COMMIT_REF_NAME" \
  --project-id "$CI_PROJECT_ID" \
  --project-path "$CI_PROJECT_PATH" \
  --pipeline-id "$CI_PIPELINE_ID")"
echo "id_token obtenu (${#JWT} caracteres) — jamais affiche dans les logs"

# --- 2. login Vault ----------------------------------------------------------
step "2/5 Login Vault : auth/jwt/login, role paylink-deploy"
CI_VAULT_TOKEN="$($ENGINE exec -e VAULT_ADDR=$VAULT_ADDR_LAB vault \
  vault write -field=token auth/jwt/login role=paylink-deploy jwt="$JWT")"
echo "Token de job obtenu (TTL court) — jamais affiche dans les logs"

# --- 3. lecture du secret ----------------------------------------------------
step "3/5 Lecture de secret/paylink/api avec le token de job"
API_KEY="$($ENGINE exec -e VAULT_ADDR=$VAULT_ADDR_LAB -e VAULT_TOKEN="$CI_VAULT_TOKEN" vault \
  vault kv get -field=api_key secret/paylink/api)"
API_URL="$($ENGINE exec -e VAULT_ADDR=$VAULT_ADDR_LAB -e VAULT_TOKEN="$CI_VAULT_TOKEN" vault \
  vault kv get -field=api_url secret/paylink/api)"
echo "api_url : $API_URL"
echo "api_key : **** (masquee — jamais dans les logs de CI)"

# --- 4. artefact de deploiement ----------------------------------------------
step "4/5 Generation de l'artefact de configuration"
mkdir -p "$DIR/deploy-artifacts"
ARTIFACT="$DIR/deploy-artifacts/paylink-api.env"
cat > "$ARTIFACT" <<EOF
# Genere par le job deploy (pipeline $CI_PIPELINE_ID, ref $CI_COMMIT_REF_NAME)
# Ne jamais committer ce fichier.
PAYLINK_API_URL=$API_URL
PAYLINK_API_KEY=$API_KEY
PAYLINK_DEPLOY_REF=$CI_COMMIT_REF_NAME
PAYLINK_DEPLOY_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
chmod 600 "$ARTIFACT"
echo "Artefact ecrit : $ARTIFACT"

# --- 5. revocation du token --------------------------------------------------
step "5/5 Fin de job : revocation du token"
$ENGINE exec -e VAULT_ADDR=$VAULT_ADDR_LAB -e VAULT_TOKEN="$CI_VAULT_TOKEN" vault \
  vault token revoke -self
echo "Token de job revoque."

step "Job deploy termine"
echo "Bilan : zero secret stocke cote CI, identite prouvee par JWT signe,"
echo "token a TTL court revoque en fin de job."
