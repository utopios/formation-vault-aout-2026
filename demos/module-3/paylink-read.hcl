path "secret/data/paylink/*" {
  capabilities = ["read"]
}
path "secret/metadata/paylink/*" {
  capabilities = ["read", "list"]
}