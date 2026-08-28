#!/usr/bin/env bash
# PayLink — insertion d'un paiement : credentials dynamiques + chiffrement transit.
#
# L'application ne connait AUCUN secret statique :
#   1. elle obtient un compte PostgreSQL ephemere via database/creds/paylink-dml,
#   2. elle chiffre le numero de carte via transit/encrypt/paylink-cards,
#   3. elle insere le paiement (ciphertext vault:vN:... en base, jamais le clair).
#
# Usage :
#   APP_TOKEN=<token applicatif (policy paylink-app)> \
#     ./insert-payment.sh <reference> <montant_cents> <numero_carte>
# Exemple :
#   APP_TOKEN=hvs.XXXX ./insert-payment.sh PAY-1042 4990 4242-4242-4242-4242
#
# Prerequis : lab podman demarre (conteneurs vault + postgres, reseau vault-lab),
# table payments chargee (init-payments.sql), role paylink-dml et cle
# paylink-cards configures (voir TP 4).
set -euo pipefail

ENGINE="${ENGINE:-podman}"
VAULT_ADDR_IN_CONTAINER="${VAULT_ADDR_IN_CONTAINER:-http://127.0.0.1:8200}"

if [ -z "${APP_TOKEN:-}" ]; then
  echo "Erreur : exportez APP_TOKEN (token applicatif porteur de la policy paylink-app)." >&2
  exit 1
fi

if [ "$#" -ne 3 ]; then
  echo "Usage : APP_TOKEN=<token> $0 <reference> <montant_cents> <numero_carte>" >&2
  exit 1
fi

REF="$1"
AMOUNT_CENTS="$2"
CARD_NUMBER="$3"

# CLI Vault executee dans le conteneur, avec le token APPLICATIF (pas root).
vlt() {
  "$ENGINE" exec \
    -e VAULT_ADDR="$VAULT_ADDR_IN_CONTAINER" \
    -e VAULT_TOKEN="$APP_TOKEN" \
    vault vault "$@"
}

echo "[1/3] Obtention de credentials PostgreSQL dynamiques (database/creds/paylink-dml)"
CREDS_JSON="$(vlt read -format=json database/creds/paylink-dml)"
DB_USER="$(printf '%s\n' "$CREDS_JSON"  | sed -n 's/.*"username": *"\([^"]*\)".*/\1/p')"
DB_PASS="$(printf '%s\n' "$CREDS_JSON"  | sed -n 's/.*"password": *"\([^"]*\)".*/\1/p')"
LEASE_ID="$(printf '%s\n' "$CREDS_JSON" | sed -n 's/.*"lease_id": *"\([^"]*\)".*/\1/p')"

if [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; then
  echo "Erreur : impossible d'extraire username/password de la reponse Vault." >&2
  exit 1
fi
echo "      compte ephemere : $DB_USER"
echo "      lease           : $LEASE_ID"

echo "[2/3] Chiffrement du numero de carte (transit/encrypt/paylink-cards)"
CARD_B64="$(printf '%s' "$CARD_NUMBER" | base64)"
CIPHERTEXT="$(vlt write -field=ciphertext transit/encrypt/paylink-cards plaintext="$CARD_B64")"
echo "      ciphertext      : $CIPHERTEXT"

echo "[3/3] Insertion du paiement avec le compte dynamique"
"$ENGINE" exec -e PGPASSWORD="$DB_PASS" postgres \
  psql -h 127.0.0.1 -U "$DB_USER" -d paylink -v ON_ERROR_STOP=1 -c \
  "INSERT INTO payments (reference, amount_cents, card_number_encrypted)
   VALUES ('$REF', $AMOUNT_CENTS, '$CIPHERTEXT');"

echo "OK : paiement '$REF' insere ($AMOUNT_CENTS cents), carte chiffree."
echo "Le compte $DB_USER expirera avec son lease (aucun nettoyage a faire)."
