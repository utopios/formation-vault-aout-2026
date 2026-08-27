alias v='podman exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root-token-formation vault vault'
v kv put secret/ledger/db \
    user=ledger_batch password='Ldg#Init2024'

v kv put secret/ledger/s3 \
    access_key=AKIA7TQX9LEDGER01 \
    secret_key=wJalr0XUtnFEMI1K7MDENG2bPxRfiCY

v kv list secret/ledger

v kv put secret/ledger/db \
    user=ledger_batch password='Ldg#Rot2026'

v kv patch secret/ledger/s3 \
    secret_key=wJalr9NEWKEY4RotatedX2026abcDEF

v kv get secret/ledger/db

v kv get secret/ledger/s3

v kv get -version=1 secret/ledger/db
v kv get -version=1 -field=password secret/ledger/db

curl -s -H "X-Vault-Token: root-token-formation" \
  http://127.0.0.1:8200/v1/secret/data/ledger/s3 | jq


curl -s -H "X-Vault-Token: root-token-formation" \
  -X POST \
  -d '{"data":{"url":"amqp://mq.paylink.internal:5672","vhost":"ledger"}}' \
  http://127.0.0.1:8200/v1/secret/data/ledger/queue | jq

v kv metadata get secret/ledger/db

v kv delete secret/ledger/queue

v kv undelete -versions=1 secret/ledger/queue

v kv get -field=vhost secret/ledger/queue