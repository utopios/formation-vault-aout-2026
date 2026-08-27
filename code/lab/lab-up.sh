#!/usr/bin/env bash
# Lab Vault — jour 1 et module 4.
# Demarre un Vault en mode dev et un PostgreSQL sur un reseau podman dedie.
# Usage : ./lab-up.sh
set -euo pipefail



ENGINE="${ENGINE:-podman}"
NETWORK=vault-lab
VAULT_IMAGE=docker.io/hashicorp/vault:1.20
PG_IMAGE=docker.io/library/postgres:16-alpine
ROOT_TOKEN=root-token-formation

$ENGINE network create $NETWORK 2>/dev/null || true

$ENGINE rm -f vault postgres 2>/dev/null || true

$ENGINE run -d --name vault --network $NETWORK -p 8200:8200 \
  -e VAULT_DEV_ROOT_TOKEN_ID=$ROOT_TOKEN \
  -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
  $VAULT_IMAGE

$ENGINE run -d --name postgres --network $NETWORK \
  -e POSTGRES_PASSWORD=rootpg \
  -e POSTGRES_DB=paylink \
  $PG_IMAGE

echo "Attente du demarrage de Vault..."
for i in $(seq 1 30); do
  if curl -sf http://127.0.0.1:8200/v1/sys/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

curl -s http://127.0.0.1:8200/v1/sys/health | grep -o '"sealed":[a-z]*'

cat <<EOF

Lab pret.
  UI Vault      : http://127.0.0.1:8200 (token : $ROOT_TOKEN)
  CLI dans le conteneur :
    $ENGINE exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$ROOT_TOKEN vault vault status
  API depuis le poste :
    curl -H "X-Vault-Token: $ROOT_TOKEN" http://127.0.0.1:8200/v1/sys/health

Astuce : dans votre shell, definissez
  alias v='$ENGINE exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$ROOT_TOKEN vault vault'
EOF
