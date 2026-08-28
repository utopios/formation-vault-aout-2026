#!/usr/bin/env bash
# ============================================================================
# demo-5-2-injector.sh — Agent Injector : MediTrack injecté sur kind
#
# Le script s'arrête à chaque étape et attend [Entrée] pour continuer.
# Chaque commande est affichée avant d'être exécutée.
#
# Prérequis : cluster kind démarré (code/lab/lab-k8s-up.sh)
# Usage     : ./demos/module-05/demo-5-2-injector.sh
#             ./demos/module-05/demo-5-2-injector.sh --auto    (sans pauses)
#             ./demos/module-05/demo-5-2-injector.sh --clean   (nettoie et sort)
# ============================================================================

set -euo pipefail

CLUSTER=vault-formation
CODE_DIR="code/module-05"
AUTO=0
[ "${1:-}" = "--auto" ] && AUTO=1

export KIND_EXPERIMENTAL_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-podman}"

BLUE=$'\033[1;34m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m';  DIM=$'\033[2m';     OFF=$'\033[0m'

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
  kubectl delete -f "$CODE_DIR/meditrack-deployment.yaml" --ignore-not-found >/dev/null 2>&1 || true
  echo "Nettoyé : deployment MediTrack supprimé."
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

etape "Vault et son Injector"
run "kubectl -n vault get pods"

pause


# ===========================================================================
titre "ÉTAPE 1 — Le webhook d'admission"

run "kubectl get mutatingwebhookconfigurations"

pause


# ===========================================================================
titre "ÉTAPE 2 — Configurer Vault (auth kubernetes, secret, policy, rôles)"

run "./$CODE_DIR/vault-k8s-setup.sh"

pause

etape "Relire le rôle créé"
run "kubectl -n vault exec vault-0 -- sh -c \\
  'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root-token-formation \\
   vault read auth/kubernetes/role/meditrack'"

pause


# ===========================================================================
titre "ÉTAPE 3 — Le deployment annoté"

run "cat $CODE_DIR/meditrack-deployment.yaml"

pause

etape "Application du manifest"
run "kubectl apply -f $CODE_DIR/meditrack-deployment.yaml"

etape "Attente du pod (Init puis Running 2/2)"
run "kubectl -n demo rollout status deploy/meditrack-api --timeout=120s"

pause


# ===========================================================================
titre "ÉTAPE 4 — La preuve : 2 conteneurs et le fichier injecté"

etape "Les conteneurs du pod"
run "kubectl -n demo get pod -l app=meditrack-api \\
  -o jsonpath='{.items[0].spec.containers[*].name}' ; echo"

etape "L'init container ajouté par le webhook"
run "kubectl -n demo get pod -l app=meditrack-api \\
  -o jsonpath='{.items[0].spec.initContainers[*].name}' ; echo"

etape "Le fichier rendu, lu depuis le conteneur applicatif"
run "kubectl -n demo exec deploy/meditrack-api -c app -- cat /vault/secrets/app.env"

pause


# ===========================================================================
titre "ÉTAPE 5 — Vérifications complémentaires"

etape "Le pod, vu de l'extérieur"
run "kubectl -n demo get pods"

etape "Les logs de l'init container"
run "kubectl -n demo logs deploy/meditrack-api -c vault-agent-init 2>&1 | tail -8"

pause


# ===========================================================================
titre "FIN"

note "Le deployment reste en place : la démo 5.3 (VSO) enchaîne dessus."
note "Nettoyage : ./demos/module-05/demo-5-2-injector.sh --clean"
