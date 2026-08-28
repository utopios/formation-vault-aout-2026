#!/usr/bin/env bash
# gen-jwt.sh — fabrique un id_token JWT "comme GitLab CI" et le signe en RS256
# avec la cle privee du lab (keys/gitlab-ci.key).
#
# PIEGE nbf/iat : l'horloge de la VM podman peut deriver par rapport a l'hote.
# On prend donc l'heure DU CONTENEUR VAULT (celle qui compte pour la
# validation), jamais celle du poste :
#   NOW=$(podman exec vault date -u +%s)
#
# Usage :
#   ./gen-jwt.sh [--ref main] [--project-id 42] [--project-path utopios/paylink-api]
#                [--aud https://vault.paylink.local] [--exp 300]
#                [--ref-type branch] [--ref-protected true|false]
#                [--pipeline-id 1337] [--iss https://gitlab.example.com]
#                [--decode]
#
# Par defaut, ref_protected vaut "true" si ref=main, "false" sinon
# (comme une branche protegee GitLab). --decode affiche le payload au lieu
# du JWT (pratique pour inspecter les claims).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
KEY="$DIR/keys/gitlab-ci.key"
ENGINE="${ENGINE:-podman}"

REF="main"
PROJECT_ID="42"
PROJECT_PATH="utopios/paylink-api"
AUD="https://vault.paylink.local"
EXP_SECONDS="300"
REF_TYPE="branch"
REF_PROTECTED=""
PIPELINE_ID="1337"
ISS="https://gitlab.example.com"
DECODE="no"

while [ $# -gt 0 ]; do
  case "$1" in
    --ref)           REF="$2"; shift 2 ;;
    --project-id)    PROJECT_ID="$2"; shift 2 ;;
    --project-path)  PROJECT_PATH="$2"; shift 2 ;;
    --aud)           AUD="$2"; shift 2 ;;
    --exp)           EXP_SECONDS="$2"; shift 2 ;;
    --ref-type)      REF_TYPE="$2"; shift 2 ;;
    --ref-protected) REF_PROTECTED="$2"; shift 2 ;;
    --pipeline-id)   PIPELINE_ID="$2"; shift 2 ;;
    --iss)           ISS="$2"; shift 2 ;;
    --decode)        DECODE="yes"; shift ;;
    *) echo "option inconnue : $1" >&2; exit 1 ;;
  esac
done

if [ ! -f "$KEY" ]; then
  echo "Cle privee absente ($KEY) : lancez d'abord ./gen-keys.sh" >&2
  exit 1
fi

# Branche protegee simulee : main est protegee, le reste non.
if [ -z "$REF_PROTECTED" ]; then
  if [ "$REF" = "main" ]; then REF_PROTECTED="true"; else REF_PROTECTED="false"; fi
fi

# Heure de reference : celle du conteneur vault (evite le piege nbf).
NOW="$($ENGINE exec vault date -u +%s)"
EXP=$((NOW + EXP_SECONDS))

b64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

HEADER='{"alg":"RS256","typ":"JWT"}'

PAYLOAD=$(cat <<EOF
{"iss":"$ISS","sub":"project_path:$PROJECT_PATH:ref_type:$REF_TYPE:ref:$REF","aud":"$AUD","iat":$NOW,"nbf":$NOW,"exp":$EXP,"project_id":"$PROJECT_ID","project_path":"$PROJECT_PATH","ref":"$REF","ref_type":"$REF_TYPE","ref_protected":"$REF_PROTECTED","pipeline_id":"$PIPELINE_ID","job_id":"$((PIPELINE_ID * 10 + 1))"}
EOF
)

if [ "$DECODE" = "yes" ]; then
  echo "$PAYLOAD"
  exit 0
fi

SIGNING_INPUT="$(printf '%s' "$HEADER" | b64url).$(printf '%s' "$PAYLOAD" | b64url)"
SIGNATURE="$(printf '%s' "$SIGNING_INPUT" | openssl dgst -sha256 -sign "$KEY" -binary | b64url)"

echo "$SIGNING_INPUT.$SIGNATURE"
