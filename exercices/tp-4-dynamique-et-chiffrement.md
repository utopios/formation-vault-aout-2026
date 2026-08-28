# TP 4 — PayLink passe aux credentials dynamiques et chiffre les cartes

> Module : 4 — Secrets dynamiques et chiffrement as a service
> Durée estimée : 50 min
> Difficulté : 3 / 5
> Type : Travaux pratiques guidés

## Mise en situation

L'audit de sécurité de PayLink a rendu son verdict : le compte PostgreSQL
statique partagé doit disparaître, et plus aucun numéro de carte ne doit être
stocké en clair. Vous êtes chargé de faire évoluer l'API de paiement :

- elle obtiendra ses accès PostgreSQL **à la demande** via le moteur
  `database` (rôle `paylink-dml` : `INSERT`, `UPDATE`, `SELECT` sur la table
  `payments`) ;
- elle **chiffrera** chaque numéro de carte via le moteur `transit` (clé
  `paylink-cards`) avant insertion ;
- elle tournera avec un token porteur d'une policy **minimale** : rien
  d'autre que ces deux capacités.

L'« application » est fournie sous forme de script shell
(`code/module-04/insert-payment.sh`) : votre travail est de préparer tout ce
dont elle a besoin côté Vault et PostgreSQL, puis de prouver que le moindre
privilège est respecté.

## Objectifs

- Créer un rôle database DML adapté à un besoin applicatif précis
- Écrire et appliquer une policy applicative strictement minimale
- Faire fonctionner une application de bout en bout sans aucun secret statique
- Vérifier en SQL que les données sensibles ne sont stockées que chiffrées

## Prérequis techniques

### Environnement

- Lab Podman démarré (`code/lab/lab-up.sh`) : conteneurs `vault`
  (Vault 1.20.4, token racine `root-token-formation`) et `postgres`
  (postgres:16-alpine, base `paylink`) sur le réseau `vault-lab`
- Démo 4.1 jouée : moteur `database/` activé, connexion
  `database/config/paylink-pg` configurée avec
  `allowed_roles="paylink-readonly,paylink-dml"`
- Démo 4.2 jouée : moteur `transit/` activé, clé `paylink-cards` créée
- Fichiers du TP : `code/module-04/`

### Vérification de l'environnement

```bash
alias v='podman exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root-token-formation vault vault'

v read database/config/paylink-pg      # allowed_roles doit contenir paylink-dml
v read transit/keys/paylink-cards      # la cle existe
podman exec postgres psql -U postgres -d paylink -c "SELECT 1;"
```

Si `database/` ou `transit/` manquent, rejouez les étapes 2.1-2.2 des démos
4.1 et 4.2 (5 minutes).

## Architecture cible

```text
                +--------------------------------------------+
                |                   VAULT                     |
                |                                             |
   token        |  database/creds/paylink-dml   (read)        |
   applicatif   |     -> cree un compte PG ephemere           |
   (policy   -->|                                             |
   paylink-app) |  transit/encrypt/paylink-cards (update)     |
                |     -> carte en clair (b64) -> vault:vN:... |
                +----------------------+----------------------+
                          |            ^
             CREATE ROLE  |            | encrypt / decrypt
             v-token-...  v            |
        +-----------------+--+   +-----+------------------+
        |    POSTGRES        |   |  insert-payment.sh     |
        |  base paylink      |<--|  (l'« application »)   |
        |  table payments    |   |  INSERT ... VALUES     |
        |  card_number_      |   |  ('PAY-1042', 4990,    |
        |  encrypted TEXT    |   |   'vault:v2:...')      |
        +--------------------+   +------------------------+
```

## Étapes

### Étape 1 — La table payments (5 min)

Objectif : disposer du schéma cible côté PostgreSQL.

1. Examinez `code/module-04/init-payments.sql` : notez que la colonne
   `card_number_encrypted` est un simple `TEXT` — le ciphertext transit s'y
   stocke tel quel.

2. Chargez la table :
   ```bash
   podman exec -i postgres psql -U postgres -d paylink -v ON_ERROR_STOP=1 \
     < code/module-04/init-payments.sql
   ```

Point de contrôle : la table existe et est vide.
```bash
podman exec postgres psql -U postgres -d paylink -c "\d payments"
podman exec postgres psql -U postgres -d paylink -c "SELECT count(*) FROM payments;"
```

### Étape 2 — Le rôle database paylink-dml (10 min)

Objectif : un modèle de compte éphémère limité au DML dont l'API a besoin.

1. Examinez `code/module-04/paylink-dml-role.json`. Trois instructions SQL :
   création du rôle avec `VALID UNTIL`, `GRANT SELECT, INSERT, UPDATE` sur
   les tables, et `GRANT USAGE, SELECT` sur les **séquences** — indispensable
   pour insérer dans une colonne `SERIAL`.

2. Créez le rôle via l'API (le JSON est prêt à l'emploi) :
   ```bash
   curl -s -H "X-Vault-Token: root-token-formation" -X POST \
     --data @code/module-04/paylink-dml-role.json \
     http://127.0.0.1:8200/v1/database/roles/paylink-dml
   ```

3. Vérifiez la définition enregistrée :
   ```bash
   v read database/roles/paylink-dml
   ```

Point de contrôle : une génération de credentials fonctionne et le compte
peut écrire dans `payments` mais pas créer de table.
```bash
v read database/creds/paylink-dml
# Avec le username/password renvoyes :
podman exec -e PGPASSWORD='<password>' postgres \
  psql -h 127.0.0.1 -U '<username>' -d paylink \
  -c "INSERT INTO payments (reference, amount_cents, card_number_encrypted)
      VALUES ('TEST-DML', 100, 'test-a-supprimer');"
podman exec -e PGPASSWORD='<password>' postgres \
  psql -h 127.0.0.1 -U '<username>' -d paylink -c "CREATE TABLE hack(i int);"
# Attendu : INSERT 0 1 pour le premier, "ERROR: permission denied for schema public"
# pour le second. Nettoyez la ligne de test :
podman exec postgres psql -U postgres -d paylink \
  -c "DELETE FROM payments WHERE reference = 'TEST-DML';"
```

### Étape 3 — La policy applicative et le token (10 min)

Objectif : un token qui ne peut faire QUE ce dont l'application a besoin.

1. Examinez `code/module-04/paylink-app.hcl` : trois paths, pas un de plus.
   Notez que `encrypt` et `decrypt` sont des `update` (ce sont des POST),
   pas des `read`.

2. Chargez la policy (attention : `podman exec -i`, l'alias `v` ne transmet
   pas stdin) :
   ```bash
   podman exec -i -e VAULT_ADDR=http://127.0.0.1:8200 \
     -e VAULT_TOKEN=root-token-formation vault \
     vault policy write paylink-app - < code/module-04/paylink-app.hcl
   ```

3. Créez le token applicatif et gardez-le dans une variable :
   ```bash
   APP_TOKEN=$(v token create -policy=paylink-app -ttl=1h -field=token)
   echo "$APP_TOKEN"
   ```

Point de contrôle : la policy est bien attachée.
```bash
v policy read paylink-app
podman exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN="$APP_TOKEN" \
  vault vault token lookup
# Attendu : policies [default paylink-app]
```

### Étape 4 — L'application de bout en bout (10 min)

Objectif : insérer des paiements sans aucun secret statique.

1. Parcourez `code/module-04/insert-payment.sh` : repérez les trois temps
   (creds dynamiques, encrypt, INSERT) et vérifiez qu'aucun mot de passe n'y
   figure en dur.

2. Exécutez-le pour deux paiements :
   ```bash
   chmod +x code/module-04/insert-payment.sh
   APP_TOKEN="$APP_TOKEN" ./code/module-04/insert-payment.sh PAY-1042 4990 4242-4242-4242-4242
   APP_TOKEN="$APP_TOKEN" ./code/module-04/insert-payment.sh PAY-1043 12550 4970-1234-5678-9010
   ```

Point de contrôle : deux lignes en base, et **aucun numéro de carte en
clair** — uniquement des ciphertexts `vault:vN:...`.
```bash
podman exec postgres psql -U postgres -d paylink \
  -c "SELECT reference, amount_cents, left(card_number_encrypted, 25) AS carte
      FROM payments ORDER BY id;"
```

### Étape 5 — Le tour du propriétaire : round-trip et moindre privilège (10 min)

Objectif : prouver que le chiffré est exploitable et que le token ne peut
rien faire d'autre.

1. Round-trip : récupérez le ciphertext de `PAY-1042` et déchiffrez-le avec
   le token **applicatif** :
   ```bash
   CT=$(podman exec postgres psql -U postgres -d paylink -t -A \
     -c "SELECT card_number_encrypted FROM payments WHERE reference='PAY-1042';")
   podman exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN="$APP_TOKEN" \
     vault vault write -field=plaintext transit/decrypt/paylink-cards \
     ciphertext="$CT" | base64 -d
   ```

2. Tests négatifs — chacun doit échouer en `permission denied` (403) :
   ```bash
   podman exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN="$APP_TOKEN" \
     vault vault read database/creds/paylink-readonly
   podman exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN="$APP_TOKEN" \
     vault vault read transit/keys/paylink-cards
   podman exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN="$APP_TOKEN" \
     vault vault write -f transit/keys/paylink-cards/rotate
   ```

3. Côté PostgreSQL, observez les comptes éphémères créés par vos exécutions
   du script :
   ```bash
   podman exec postgres psql -U postgres -d paylink \
     -c "SELECT usename, valuntil FROM pg_user WHERE usename LIKE 'v-token-%';"
   ```

Point de contrôle : le numéro `4242-4242-4242-4242` ressort du decrypt ; les
trois commandes du test négatif renvoient `permission denied` ; chaque
exécution du script a laissé son propre compte `v-token-paylink-d...` (qui
expirera avec son lease).

### Étape 6 — Teardown du TP (5 min)

```bash
# Revoquer tous les leases database du TP (les comptes v-token-... disparaissent)
v lease revoke -prefix database/creds/paylink-dml

# Revoquer le token applicatif
v token revoke "$APP_TOKEN"

# Verifier qu'il ne reste plus de compte ephemere du TP
podman exec postgres psql -U postgres -d paylink \
  -c "SELECT usename FROM pg_user WHERE usename LIKE 'v-token-paylink-d%';"

# (Conserver les moteurs database/ et transit/, la policy et la table :
#  les modules 5 et 6 reutilisent ce socle. Pour tout arreter en fin de
#  journee : code/lab/lab-down.sh)
```

## Livrable attendu

- La sortie du `SELECT` de l'étape 4 montrant les deux paiements avec des
  colonnes carte en `vault:vN:...`
- La sortie du round-trip (étape 5.1) restituant `4242-4242-4242-4242`
- Les trois `permission denied` de l'étape 5.2
- Votre réponse écrite : pourquoi la policy n'accorde-t-elle pas `read` sur
  `transit/encrypt/paylink-cards`, et faudrait-il séparer encrypt et decrypt
  en deux policies distinctes chez PayLink ?

