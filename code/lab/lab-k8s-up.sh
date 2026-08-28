#!/usr/bin/env bash
# Lab Kubernetes — module 5.
# Cree un cluster kind (provider podman) puis installe Vault (mode dev +
# Agent Injector) et le Vault Secrets Operator via Helm.
# Usage : ./lab-k8s-up.sh
set -euo pipefail

export KIND_EXPERIMENTAL_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-podman}"
CLUSTER=vault-formation
ROOT_TOKEN=root-token-formation

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  kind create cluster --name "$CLUSTER" --wait 120s
fi
kubectl config use-context "kind-$CLUSTER"

helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null
helm repo update >/dev/null

helm upgrade --install vault hashicorp/vault \
  --namespace vault --create-namespace \
  --set "server.dev.enabled=true" \
  --set "server.dev.devRootToken=$ROOT_TOKEN" \
  --set "injector.enabled=true"

kubectl -n vault wait --for=condition=Ready pod/vault-0 --timeout=180s

helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator \
  --namespace vault-secrets-operator-system --create-namespace

kubectl -n vault-secrets-operator-system wait --for=condition=Available deploy --all --timeout=180s

cat <<EOF

Cluster pret.
  kubectl -n vault get pods
  CLI Vault dans le cluster :
    kubectl -n vault exec vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault status"
EOF
