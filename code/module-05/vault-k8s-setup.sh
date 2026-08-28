#!/usr/bin/env bash
# Module 5 — configuration de Vault dans le cluster kind (via kubectl exec vault-0) :
#   - auth kubernetes (enable + config)
#   - secret secret/meditrack/api
#   - policy meditrack-read
#   - role kubernetes/meditrack (injection) et kubernetes/vso-demo (VSO)
# Prerequis : ./code/lab/lab-k8s-up.sh execute (cluster vault-formation + Helm).
# Usage : ./vault-k8s-setup.sh
set -euo pipefail

ROOT_TOKEN=root-token-formation

kubectl config use-context kind-vault-formation

kubectl -n vault exec -i vault-0 -- sh -e <<EOF
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$ROOT_TOKEN

# 1. Auth kubernetes : Vault tourne DANS le cluster, l'API server est joignable
#    via les variables d'environnement injectees par Kubernetes dans le pod.
vault auth enable kubernetes || true
vault write auth/kubernetes/config \
  kubernetes_host="https://\$KUBERNETES_SERVICE_HOST:\$KUBERNETES_SERVICE_PORT"

# 2. Secret de MediTrack
vault kv put secret/meditrack/api db_user=meditrack db_password='K8sInject!2026'

# 3. Policy en lecture seule sur ce secret
vault policy write meditrack-read - <<'POLICY'
path "secret/data/meditrack/api" {
  capabilities = ["read"]
}
POLICY

# 4. Role pour l'injection : lie (ServiceAccount meditrack-sa, namespace demo)
#    a la policy meditrack-read.
#    NB : Vault emet un WARNING "does not have an audience configured" —
#    attendu en lab ; en production, ajouter audience="vault" et un token projete.
vault write auth/kubernetes/role/meditrack \
  bound_service_account_names=meditrack-sa \
  bound_service_account_namespaces=demo \
  policies=meditrack-read \
  ttl=1h

# 5. Role pour le Vault Secrets Operator (login avec le SA default du ns demo)
vault write auth/kubernetes/role/vso-demo \
  bound_service_account_names=default \
  bound_service_account_namespaces=demo \
  policies=meditrack-read \
  ttl=1h
EOF

cat <<'DONE'

Configuration Vault terminee :
  auth/kubernetes             active et configuree (kubernetes_host)
  secret/meditrack/api        db_user + db_password
  policy meditrack-read       lecture de secret/data/meditrack/api
  role kubernetes/meditrack   SA meditrack-sa, ns demo  (injection)
  role kubernetes/vso-demo    SA default,      ns demo  (VSO)
DONE
