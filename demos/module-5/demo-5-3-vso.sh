#!/usr/bin/env bash
# ============================================================================
# demo-5-3-vso.sh — Vault Secrets Operator : Secret natif et resynchronisation
#
# Le script s'arrête à chaque étape et attend [Entrée] pour continuer.
# Chaque commande est affichée avant d'être exécutée.
#
# Prérequis : cluster kind démarré (code/lab/lab-k8s-up.sh)
#             et vault-k8s-setup.sh exécuté (démo 5.2)
# Usage     : ./demos/module-05/demo-5-3-vso.sh
#             ./demos/module-05/demo-5-3-vso.sh --auto    (sans pauses)
#             ./demos/module-05/demo-5-3-vso.sh --clean   (nettoie et sort)
# ============================================================================

set -euo pipefail

CLUSTER=vault-formation
CODE_DIR="code/module-05"
AUTO=0
[ "${1:-}" = "--auto" ] && AUTO=1

export KIND_EXPERIMENTAL_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-podman}"

BLUE=$'\033[1;34m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m';  DIM=$'\033[2m';     OFF=$'\033[0m'

vlt() {
  kubectl -n vault exec vault-0 -- sh -c \
    "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root-token-formation vault $*"
}

titre() {
  printf '\n%s╔══════════════════════════════════════════════════════════════╗%s\n' "$BLUE" "$OFF"
  printf '%s║%s  %-60s%s║%s\n' "$BLUE" "$OFF" "$*" "$BLUE" "$OFF"
  printf '%s╚══════════════════════════════════════════════════════════════╝%s\n' "$BLUE" "$OFF"
}

etape() { printf '\n%s── %s%s\n' "$CYAN" "$*" "$OFF"; }
note()  { printf '%s   %s%s\n' "$DIM" "$*" "$OFF"; }

pause() {
  [ "$AUTO" -eq 1 ] && { sleep 1; return; }
  printf '\n%s   [Entrée] pour continuer…%s ' "$GREEN" "$OFF"
  read -r _
}

run() {
  printf '\n%s$ %s%s\n' "$GREEN" "$*" "$OFF"
  eval "$@"
}

if [ "${1:-}" = "--clean" ]; then
  kubectl delete -f "$CODE_DIR/vso-resources.yaml" --ignore-not-found >/dev/null 2>&1 || true
  echo "Nettoyé : CRD VSO supprimées."
  exit 0
fi


# ===========================================================================
titre "VÉRIFICATION DU LAB"

etape "Cluster kind"
kind get clusters 2>/dev/null | grep -qx "$CLUSTER" || {
  echo "Le cluster '$CLUSTER' n'existe pas. Lancez ./code/lab/lab-k8s-up.sh"
  exit 1
}
run "kubectl config use-context kind-$CLUSTER"

etape "L'opérateur VSO"
run "kubectl -n vault-secrets-operator-system get pods"

etape "Le rôle vso-demo côté Vault"
if ! vlt read auth/kubernetes/role/vso-demo >/dev/null 2>&1; then
  echo "Le rôle vso-demo n'existe pas. Lancez ./$CODE_DIR/vault-k8s-setup.sh"
  exit 1
fi
note "rôle vso-demo présent"

pause


# ===========================================================================
titre "ÉTAPE 1 — Les trois CRD"

run "cat $CODE_DIR/vso-resources.yaml"

pause


# ===========================================================================
titre "ÉTAPE 2 — Appliquer les CRD"

run "kubectl apply -f $CODE_DIR/vso-resources.yaml"

etape "État de la VaultStaticSecret"
sleep 5
run "kubectl -n demo get vaultstaticsecret"

pause


# ===========================================================================
titre "ÉTAPE 3 — Le Secret Kubernetes natif créé"

etape "Le Secret, décodé"
for _ in $(seq 1 15); do
  kubectl -n demo get secret meditrack-api-creds >/dev/null 2>&1 && break
  sleep 2
done

printf '\n%s$ kubectl -n demo get secret meditrack-api-creds -o go-template=...%s\n' "$GREEN" "$OFF"
kubectl -n demo get secret meditrack-api-creds \
  -o go-template='{{ range $k, $v := .data }}{{ $k }} = {{ $v | base64decode }}{{ "\n" }}{{ end }}'

pause


# ===========================================================================
titre "ÉTAPE 4 — Rotation côté Vault, resynchronisation automatique"

etape "Valeur actuelle du Secret K8s"
run "kubectl -n demo get secret meditrack-api-creds \\
  -o jsonpath='{.data.db_password}' | base64 -d ; echo"

etape "Rotation dans Vault"
START=$(date +%s)
run "kubectl -n vault exec vault-0 -- sh -c \\
  'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root-token-formation \\
   vault kv patch secret/meditrack/api db_password=RotatedByVSO!99'"

etape "Attente de la resynchronisation (refreshAfter = 15s)"
for _ in $(seq 1 20); do
  VAL=$(kubectl -n demo get secret meditrack-api-creds \
        -o jsonpath='{.data.db_password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
  [ "$VAL" = 'RotatedByVSO!99' ] && break
  sleep 2
done
ELAPSED=$(( $(date +%s) - START ))

etape "Nouvelle valeur du Secret K8s"
run "kubectl -n demo get secret meditrack-api-creds \\
  -o jsonpath='{.data.db_password}' | base64 -d ; echo"

printf '\n%s   Propagation en %s secondes.%s\n' "$YELLOW" "$ELAPSED" "$OFF"

pause


# ===========================================================================
titre "ÉTAPE 5 — Le pod ne voit pas la nouvelle valeur"

etape "Variables d'environnement du pod (si consommé en envFrom)"
run "kubectl -n demo get pods"

note "Un pod consommant ce Secret en envFrom garde l'ancienne valeur"
note "jusqu'à son redémarrage — d'où spec.rolloutRestartTargets dans la CRD."

pause


# ===========================================================================
titre "FIN"

note "Les CRD restent en place : le TP 5 repart de cet état."
note "Nettoyage : ./demos/module-05/demo-5-3-vso.sh --clean"
note "Teardown complet du lab K8s : ./code/lab/lab-down.sh"
