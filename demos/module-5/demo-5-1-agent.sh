#!/usr/bin/env bash
# ============================================================================
# demo-5-1-agent.sh — Vault Agent standalone : auto-auth, sink, template
#

set -euo pipefail

VAULT_ADDR=http://127.0.0.1:8200
VAULT_TOKEN=root-token-formation
WORK="${WORK:-$HOME/demo-agent}"
CODE_DIR="code/module-05"
AUTO=0
[ "${1:-}" = "--auto" ] && AUTO=1

BLUE=$'\033[1;34m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m';  DIM=$'\033[2m';     OFF=$'\033[0m'

vexec() {
  docker exec -i -e VAULT_ADDR="$VAULT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" \
    vault vault "$@"
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

nettoyer() {
  docker rm -f vault-agent >/dev/null 2>&1 || true
  rm -rf "$WORK"
}

if [ "${1:-}" = "--clean" ]; then
  nettoyer
  echo "Nettoyé : conteneur vault-agent supprimé, $WORK effacé."
  exit 0
fi


# ===========================================================================
titre "PRÉPARATION"

etape "Vérification du lab"
docker ps --format '{{.Names}}' | grep -q '^vault$' || {
  echo "Le conteneur 'vault' n'est pas démarré. Lancez ./code/lab/lab-up.sh"
  exit 1
}
note "conteneur vault actif"

etape "Répertoire de travail"
nettoyer
mkdir -p "$WORK/out"
cp "$CODE_DIR/agent.hcl" "$CODE_DIR/app.env.ctmpl" "$WORK/"
note "$WORK"

etape "Secret consommé par le template"
run "vexec kv put secret/paylink/api \\
    db_user=paylink_app db_password='Rot4ted!2026' api_key=pk_live_99Z"

etape "Policy en lecture seule"
vexec policy write paylink-read - <<'EOF'
path "secret/data/paylink/api" {
  capabilities = ["read"]
}
EOF
note "policy paylink-read chargée"

etape "AppRole dédié à l'agent"
vexec auth enable approle >/dev/null 2>&1 || note "approle déjà activée"
run "vexec write auth/approle/role/paylink-agent \\
    token_policies=paylink-read token_ttl=1h"

etape "Identifiants livrés en fichiers"
vexec read -field=role_id auth/approle/role/paylink-agent/role-id > "$WORK/role_id"
vexec write -f -field=secret_id auth/approle/role/paylink-agent/secret-id > "$WORK/secret_id"
note "role_id   : $(cat "$WORK/role_id")"
note "secret_id : $(cut -c1-12 < "$WORK/secret_id")…"

etape "Neutralisation de template_config (intervalle par défaut = 5 min)"
python3 - "$WORK/agent.hcl" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().split('\n')
out, in_tc = [], False
for l in lines:
    if l.startswith('template_config {'):
        in_tc = True; out.append('# ' + l); continue
    if in_tc:
        out.append('# ' + l)
        if l.strip() == '}':
            in_tc = False
        continue
    out.append(l)
open(p, 'w').write('\n'.join(out))
PY
note "bloc template_config commenté"

pause


# ===========================================================================
titre "ÉTAPE 1 — La configuration de l'agent"

etape "agent.hcl"
run "cat $WORK/agent.hcl"

pause

etape "Le template consul-template"
run "cat $WORK/app.env.ctmpl"

pause


# ===========================================================================
titre "ÉTAPE 2 — Lancement de l'agent"

run "docker run -d --name vault-agent --network vault-lab \\
  -v \"$WORK:/agent\" \\
  docker.io/hashicorp/vault:1.20 \\
  vault agent -config=/agent/agent.hcl"

sleep 3
pause


# ===========================================================================
titre "ÉTAPE 3 — Les logs : auth, sink, rendu"

run "docker logs vault-agent 2>&1 | grep -E 'auth.handler|sink.file|rendered' | head -10"

pause


# ===========================================================================
titre "ÉTAPE 4 — Le token déposé et le fichier rendu"

etape "Le token dans le sink"
run "head -c 30 $WORK/out/vault-token ; echo '…'"

etape "Le fichier rendu pour l'application"
run "cat $WORK/out/app.env"

pause


# ===========================================================================
titre "ÉTAPE 5 — Rotation avec l'intervalle par défaut"

etape "Rotation du mot de passe dans Vault"
run "vexec kv patch secret/paylink/api db_password='NewRotation!42'"

etape "Attente de 60 secondes"
if [ "$AUTO" -eq 1 ]; then
  sleep 15
else
  for i in $(seq 60 -5 5); do
    printf '\r   %s%2d s restantes%s ' "$DIM" "$i" "$OFF"
    sleep 5
  done
  printf '\r                          \r'
fi

etape "Relecture du fichier rendu"
run "cat $WORK/out/app.env"

printf '\n%s   Le fichier n'\''a pas changé.%s\n' "$YELLOW" "$OFF"

pause


# ===========================================================================
titre "ÉTAPE 6 — Correction : static_secret_render_interval"

etape "Décommenter le bloc template_config"
python3 - "$WORK/agent.hcl" <<'PY'
import sys, re
p = sys.argv[1]
s = open(p).read()
s = re.sub(r'^# (template_config \{)', r'\1', s, flags=re.M)
s = re.sub(r'^#   (static_secret_render_interval.*)$', r'  \1', s, flags=re.M)
s = re.sub(r'^# (\})$', r'\1', s, flags=re.M)
s = re.sub(r'^#   (# .*)$', r'  \1', s, flags=re.M)
open(p, 'w').write(s)
PY
run "grep -A5 '^template_config' $WORK/agent.hcl"

etape "Redémarrage de l'agent"
run "docker restart vault-agent"

etape "Attente du re-rendu"
for _ in $(seq 1 20); do
  grep -q 'NewRotation!42' "$WORK/out/app.env" 2>/dev/null && break
  sleep 2
done

etape "Relecture du fichier"
run "cat $WORK/out/app.env"

etape "Les événements de rendu"
run "docker logs vault-agent 2>&1 | grep rendered | tail -3"

pause


# ===========================================================================
titre "NETTOYAGE"

run "docker rm -f vault-agent"
note "Répertoire $WORK conservé — ./demo-5-1-agent.sh --clean pour l'effacer"
