#!/bin/bash
# ============================================================================
# app-unwrap-login.sh — Côté APPLICATION (simulée : l'API PayLink)
#
# 1. Récupère role_id + wrapping token déposés par deploy-wrap.sh
# 2. Déballe (unwrap) le secret_id — première et unique utilisation possible
# 3. Se logue en AppRole et obtient son token applicatif (TTL 15m)
# 4. Lit ses secrets applicatifs
# 5. Entretient son token avec une boucle de renew (sinon re-login)
#
# Ce script ne connaît AUCUN token d'administration : il ne reçoit que le
# wrapping token (jetable) et le role_id (non secret).
#
# Usage :
#   ./app-unwrap-login.sh [répertoire_de_livraison]   (défaut : ./handoff)
#
# Variables d'environnement utiles :
#   RENEW_INTERVAL  secondes entre deux renew (défaut 300 ; mettre 5 en lab)
#   RENEW_MAX       nombre de renews avant de s'arrêter (défaut 3 ; 0 = infini)
# ============================================================================
set -euo pipefail

VAULT_CONTAINER="${VAULT_CONTAINER:-vault}"
VAULT_ADDR_IN="http://127.0.0.1:8200"
HANDOFF_DIR="${1:-./handoff}"
RENEW_INTERVAL="${RENEW_INTERVAL:-300}"
RENEW_MAX="${RENEW_MAX:-3}"

# La CLI vault exécutée dans le conteneur avec un token arbitraire (1er arg).
vapp() {
  local token="$1"; shift
  podman exec -e VAULT_ADDR="$VAULT_ADDR_IN" -e VAULT_TOKEN="$token" \
    "$VAULT_CONTAINER" vault "$@"
}

# --- 1. Récupération de la livraison ---------------------------------------
ROLE_ID=$(cat "$HANDOFF_DIR/role-id.txt")
WRAPPING_TOKEN=$(cat "$HANDOFF_DIR/wrapping-token.txt")
echo "[app] role_id reçu          : $ROLE_ID"
echo "[app] wrapping token reçu   : ${WRAPPING_TOKEN:0:24}..."

# --- 2. Unwrap : seule opération possible avec ce token ---------------------
# Si cette étape échoue en 400, le wrapping token a déjà été consommé :
# quelqu'un a intercepté le secret_id => alerte sécurité, on régénère tout.
if ! SECRET_ID=$(vapp "$WRAPPING_TOKEN" unwrap -field=secret_id); then
  echo "[app] ALERTE : unwrap impossible — wrapping token déjà consommé ou expiré." >&2
  echo "[app] Compromission possible du canal de livraison. Abandon." >&2
  exit 1
fi
rm -f "$HANDOFF_DIR/wrapping-token.txt"   # plus aucune valeur, on nettoie
echo "[app] secret_id déballé (unwrap OK, token de wrapping consommé)"

# --- 3. Login AppRole --------------------------------------------------------
APP_TOKEN=$(vapp "" write -field=token auth/approle/login \
  role_id="$ROLE_ID" secret_id="$SECRET_ID")
unset SECRET_ID                            # plus besoin, on limite l'exposition
echo "[app] login AppRole OK      : token ${APP_TOKEN:0:12}... (TTL 15m)"
vapp "$APP_TOKEN" token lookup | grep -E '^(display_name|policies|ttl|renewable) '

# --- 4. Lecture des secrets applicatifs -------------------------------------
echo "[app] lecture de secret/paylink/api :"
DB_USER=$(vapp "$APP_TOKEN" kv get -field=db_user secret/paylink/api)
DB_PASSWORD=$(vapp "$APP_TOKEN" kv get -field=db_password secret/paylink/api)
API_KEY=$(vapp "$APP_TOKEN" kv get -field=api_key secret/paylink/api)
echo "[app]   db_user     = $DB_USER"
echo "[app]   db_password = ${DB_PASSWORD:0:3}*** (masqué)"
echo "[app]   api_key     = ${API_KEY:0:8}***"
echo "[app] L'application démarre avec ses secrets. (connexion DB simulée)"

# --- 5. Boucle d'entretien du token ------------------------------------------
# token_ttl=15m : on renouvelle bien avant l'échéance. token_max_ttl=1h :
# au-delà, renew refusé => il faudra re-faire un login complet.
i=0
while [ "$RENEW_MAX" -eq 0 ] || [ "$i" -lt "$RENEW_MAX" ]; do
  sleep "$RENEW_INTERVAL"
  i=$((i + 1))
  if OUT=$(vapp "$APP_TOKEN" token renew -format=json 2>&1); then
    # deux champs lease_duration dans la réponse : celui du bloc auth est le bon
    TTL=$(printf '%s' "$OUT" | sed -n 's/.*"lease_duration": *\([0-9][0-9]*\).*/\1/p' | tail -1)
    echo "[app] renew #$i OK — TTL rechargé à ${TTL}s"
  else
    echo "[app] renew #$i refusé (max_ttl atteint ou token expiré) => re-login requis"
    echo "$OUT"
    exit 2
  fi
done
echo "[app] fin de démonstration après $i renew(s). En production : boucle infinie (RENEW_MAX=0)."
