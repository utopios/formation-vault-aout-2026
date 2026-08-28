#!/usr/bin/env bash
set -euo pipefail

VAULT_ADDR=http://127.0.0.1:8200
VAULT_TOKEN=root-token-formation
CODE_DIR="code/module-04"

v() {
  docker exec -e VAULT_ADDR="$VAULT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" \
    vault vault "$@"
}

vi() {
  docker exec -i -e VAULT_ADDR="$VAULT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" \
    vault vault "$@"
}

vapp() {
  docker exec -e VAULT_ADDR="$VAULT_ADDR" -e VAULT_TOKEN="$APP_TOKEN" \
    vault vault "$@"
}

pg() {
  docker exec postgres psql -U postgres -d paylink "$@"
}

step() { printf '\n\033[1;34m=== %s ===\033[0m\n' "$*"; }


step "Prérequis — moteur database"

v secrets enable database 2>/dev/null || true

v write database/config/paylink-pg \
    plugin_name=postgresql-database-plugin \
    connection_url="postgresql://{{username}}:{{password}}@postgres:5432/paylink?sslmode=disable" \
    allowed_roles="paylink-readonly,paylink-dml" \
    username="postgres" \
    password="rootpg"

v write database/roles/paylink-readonly \
    db_name=paylink-pg \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl=1h max_ttl=24h


step "Prérequis — moteur transit"

v secrets enable transit 2>/dev/null || true
v write -f transit/keys/paylink-cards type=aes256-gcm96


step "Étape 1 — Table payments"

docker exec -i postgres psql -U postgres -d paylink < "$CODE_DIR/init-payments.sql"

pg -c "DELETE FROM payments WHERE reference IN ('PAY-1042','PAY-1043','TEST-DML');"

pg -c "\d payments"
pg -c "SELECT count(*) FROM payments;"


step "Étape 2 — Rôle database paylink-dml"

docker cp "$CODE_DIR/paylink-dml-role.json" vault:/tmp/paylink-dml-role.json

docker exec vault sh -c \
  "VAULT_ADDR=$VAULT_ADDR VAULT_TOKEN=$VAULT_TOKEN \
   vault write database/roles/paylink-dml @/tmp/paylink-dml-role.json"

v read database/roles/paylink-dml


step "Étape 2 — Contrôle : INSERT autorisé, DDL refusé"

DML_JSON=$(v read -format=json database/creds/paylink-dml)
DML_USER=$(echo "$DML_JSON" | jq -r '.data.username')
DML_PASS=$(echo "$DML_JSON" | jq -r '.data.password')

docker exec -e PGPASSWORD="$DML_PASS" postgres \
  psql -h 127.0.0.1 -U "$DML_USER" -d paylink -c \
  "INSERT INTO payments (reference, amount_cents, card_number_encrypted)
   VALUES ('TEST-DML', 100, 'vault:v1:test');"

docker exec -e PGPASSWORD="$DML_PASS" postgres \
  psql -h 127.0.0.1 -U "$DML_USER" -d paylink -c "CREATE TABLE hack(i int);" \
  || echo ">>> permission denied for schema public — attendu"

pg -c "DELETE FROM payments WHERE reference = 'TEST-DML';"


step "Étape 3 — Policy applicative et token"

vi policy write paylink-app - < "$CODE_DIR/paylink-app.hcl"

v policy read paylink-app

APP_TOKEN=$(v token create -policy=paylink-app -ttl=1h -field=token)
export APP_TOKEN

vapp token lookup | grep -E '^(policies|ttl)'


step "Étape 4 — L'application de bout en bout"

chmod +x "$CODE_DIR/insert-payment.sh"

APP_TOKEN="$APP_TOKEN" "$CODE_DIR/insert-payment.sh" PAY-1042 4990 4242-4242-4242-4242
APP_TOKEN="$APP_TOKEN" "$CODE_DIR/insert-payment.sh" PAY-1043 12550 4970-1234-5678-9010

pg -c "SELECT reference, amount_cents, left(card_number_encrypted, 30) AS carte
       FROM payments ORDER BY id;"


step "Étape 5 — Round-trip decrypt"

CIPHER=$(pg -tA -c \
  "SELECT card_number_encrypted FROM payments WHERE reference = 'PAY-1042';")

vapp write -field=plaintext transit/decrypt/paylink-cards \
    ciphertext="$CIPHER" | base64 -d ; echo


step "Étape 5 — Tests négatifs (403 attendus)"

vapp read database/creds/paylink-readonly \
  || echo ">>> 403 attendu : la policy n'autorise que paylink-dml"

vapp read transit/keys/paylink-cards \
  || echo ">>> 403 attendu : l'app ne lit pas les métadonnées de la clé"

vapp write -f transit/keys/paylink-cards/rotate \
  || echo ">>> 403 attendu : l'app ne fait pas tourner la clé"


step "Étape 5 — Comptes dynamiques dans pg_user"

pg -c "SELECT usename, valuntil FROM pg_user WHERE usename LIKE 'v-token-paylink-d%';"


step "Étape 6 — Teardown"

v lease revoke -prefix database/creds/paylink-dml
v token revoke "$APP_TOKEN"

pg -c "SELECT count(*) AS comptes_restants FROM pg_user
       WHERE usename LIKE 'v-token-paylink-d%';"


step "Terminé"
