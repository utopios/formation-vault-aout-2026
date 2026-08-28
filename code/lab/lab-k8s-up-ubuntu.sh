#!/usr/bin/env bash

set -euo pipefail

CLUSTER=vault-formation
ROOT_TOKEN=root-token-formation
KIND_VERSION="${KIND_VERSION:-v0.30.0}"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

BLUE=$'\033[1;34m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
RED=$'\033[0;31m';  DIM=$'\033[2m';      OFF=$'\033[0m'

step() { printf '\n%s=== %s ===%s\n' "$BLUE" "$*" "$OFF"; }
ok()   { printf '%s  [OK]%s %s\n'   "$GREEN"  "$OFF" "$*"; }
warn() { printf '%s  [!] %s%s\n'    "$YELLOW" "$*"   "$OFF"; }
fail() { printf '%s  [KO]%s %s\n'   "$RED"    "$OFF" "$*"; }
note() { printf '%s      %s%s\n'    "$DIM"    "$*"   "$OFF"; }

need_sudo() {
  if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
}
need_sudo

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64)   GOARCH=amd64 ;;
  aarch64|arm64)  GOARCH=arm64 ;;
  *) fail "Architecture non gérée : $ARCH" ; exit 1 ;;
esac


# ===========================================================================
step "1. Détection du moteur de conteneurs"

if [ -n "${ENGINE:-}" ]; then
  note "moteur forcé par la variable ENGINE"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  ENGINE=docker
elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
  ENGINE=podman
elif command -v docker >/dev/null 2>&1; then
  fail "docker est installé mais ne répond pas."
  note "Démarrez-le : $SUDO systemctl start docker"
  note "Et ajoutez-vous au groupe : $SUDO usermod -aG docker \$USER  (puis reconnexion)"
  exit 1
elif command -v podman >/dev/null 2>&1; then
  fail "podman est installé mais ne répond pas."
  note "Vérifiez : podman info"
  exit 1
else
  fail "Ni docker ni podman n'est installé."
  note "Docker  : $SUDO apt-get install -y docker.io"
  note "Podman  : $SUDO apt-get install -y podman"
  exit 1
fi

ok "moteur : $ENGINE ($($ENGINE --version | head -1))"

if [ "$ENGINE" = "podman" ]; then
  export KIND_EXPERIMENTAL_PROVIDER=podman
  note "KIND_EXPERIMENTAL_PROVIDER=podman exporté"
fi


# ===========================================================================
step "2. Outils Kubernetes"

install_kubectl() {
  note "installation de kubectl…"
  local ver
  ver=$(curl -sL https://dl.k8s.io/release/stable.txt)
  curl -sLo /tmp/kubectl "https://dl.k8s.io/release/${ver}/bin/linux/${GOARCH}/kubectl"
  $SUDO install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm -f /tmp/kubectl
}

install_kind() {
  note "installation de kind ${KIND_VERSION}…"
  curl -sLo /tmp/kind \
    "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${GOARCH}"
  $SUDO install -m 0755 /tmp/kind /usr/local/bin/kind
  rm -f /tmp/kind
}

install_helm() {
  note "installation de helm…"
  curl -sL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    | $SUDO bash >/dev/null
}

for tool in kubectl kind helm; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool présent — $("$tool" version --client 2>/dev/null | head -1 || "$tool" version 2>/dev/null | head -1)"
  elif [ "$CHECK_ONLY" -eq 1 ]; then
    fail "$tool ABSENT"
  else
    command -v curl >/dev/null 2>&1 || {
      fail "curl est requis pour l'installation."
      note "$SUDO apt-get update && $SUDO apt-get install -y curl"
      exit 1
    }
    "install_$tool"
    ok "$tool installé — $(command -v "$tool")"
  fi
done

if [ "$CHECK_ONLY" -eq 1 ]; then
  step "Vérification terminée (aucune modification)"
  exit 0
fi


# ===========================================================================
step "3. Cluster kind"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  ok "cluster '$CLUSTER' déjà présent"
else
  note "création du cluster (~2 min)…"
  kind create cluster --name "$CLUSTER" --wait 120s
  ok "cluster '$CLUSTER' créé"
fi

kubectl config use-context "kind-$CLUSTER" >/dev/null
ok "contexte kubectl : kind-$CLUSTER"


# ===========================================================================
step "4. Vault et Agent Injector (Helm)"

helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install vault hashicorp/vault \
  --namespace vault --create-namespace \
  --set "server.dev.enabled=true" \
  --set "server.dev.devRootToken=$ROOT_TOKEN" \
  --set "injector.enabled=true" >/dev/null

kubectl -n vault wait --for=condition=Ready pod/vault-0 --timeout=180s >/dev/null
ok "vault-0 prêt"


# ===========================================================================
step "5. Vault Secrets Operator (Helm)"

helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator \
  --namespace vault-secrets-operator-system --create-namespace >/dev/null

kubectl -n vault-secrets-operator-system \
  wait --for=condition=Available deploy --all --timeout=180s >/dev/null
ok "opérateur VSO prêt"


# ===========================================================================
step "Cluster prêt"

kubectl -n vault get pods

cat <<EOF

  Moteur          : $ENGINE
  Cluster         : kind-$CLUSTER
  Token racine    : $ROOT_TOKEN

  CLI Vault dans le cluster :
    kubectl -n vault exec vault-0 -- sh -c "VAULT_TOKEN=$ROOT_TOKEN vault status"

  Suite du module 5 :
    ./code/module-05/vault-k8s-setup.sh
EOF

if [ "$ENGINE" = "podman" ]; then
  cat <<'EOF'
  Podman : pensez à exporter la variable dans votre shell avant kind
    export KIND_EXPERIMENTAL_PROVIDER=podman
EOF
fi
