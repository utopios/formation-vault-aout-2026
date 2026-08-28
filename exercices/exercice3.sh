alias v='podman exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root-token-formation vault vault'

v policy write paylink-cicd - <<'EOF'
# Policy CI/CD PayLink : lecture large, ecriture ciblee, jamais de suppression
path "secret/data/paylink/*" {
  capabilities = ["read"]
}

path "secret/data/paylink/webhooks" {
  capabilities = ["create", "read", "update"]
}

path "secret/metadata/paylink/*" {
  capabilities = ["read", "list"]
}

path "secret/delete/paylink/*" {
  capabilities = ["deny"]
}

path "secret/destroy/paylink/*" {
  capabilities = ["deny"]
}
EOF
```

### Création du token pour la policy paylink-cicd
T_CICD =$(v token create -policy=paylink-cicd -field token -ttl=1h)

curl -s -H "X-Vault-Token: $T_CICD" \
  "http://127.0.0.1:8200/v1/secret/data/paylink/api" 
