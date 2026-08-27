# TP 2 — Livrer le secret_id à l'API PayLink sans jamais l'exposer

> Module : 2 — Authentification applicative
> Durée estimée : 45 min
> Difficulté : 3 / 5
> Type : Travaux pratiques guidés

## Mise en situation

L'API PayLink passe en pré-production. L'équipe sécurité a validé AppRole,
mais a posé une exigence non négociable dans la revue d'architecture :

> « Le secret_id ne doit apparaître **nulle part** : ni dans un terminal,
> ni dans un fichier de configuration, ni dans les logs du déploiement.
> Et si quelqu'un l'intercepte pendant la livraison, on veut le savoir. »

Vous allez mettre en place la chaîne complète avec response wrapping :
un script *opérateur* (`deploy-wrap.sh`) qui génère un secret_id wrappé,
et l'*application* (`app-unwrap-login.sh`, qui simule le démarrage de
l'API PayLink) qui unwrappe, se logue, lit ses secrets et entretient son
token par renew. Vous jouerez ensuite le rôle de l'attaquant pour vérifier
que l'interception se détecte.

## Objectifs

- Livrer un secret_id AppRole par response wrapping, sans exposition en clair
- Consommer la livraison côté application : unwrap, login, lecture des secrets
- Entretenir le token applicatif par une boucle de renew
- Détecter une compromission du canal de livraison (échec d'unwrap)

## Prérequis techniques

### Logiciels à installer

- docker version 5.x (lab du cours démarré : `code/lab/lab-up.sh`)
- bash version 3.2 ou supérieure (celui de votre poste convient)

### Vérification de l'environnement

```bash
alias v='docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root-token-formation vault vault'
v status
v read auth/approle/role/paylink-api
v kv get secret/paylink/api
```

Les trois commandes doivent réussir (rôle créé en démo 2.1, secret peuplé
au module 1). Si le rôle manque, rejouez l'étape 2.2 de la démo 2.1 :

```bash
v write auth/approle/role/paylink-api \
    token_policies=paylink-read \
    token_ttl=15m token_max_ttl=1h \
    secret_id_ttl=60m secret_id_num_uses=5
```

## Architecture cible

```text
 POSTE OPÉRATEUR (vous)                        CONTENEUR docker "vault"
+--------------------------+                 +---------------------------+
| deploy-wrap.sh           |                 |  Vault 1.20.4 (dev)       |
|  token opérateur         |--- (1) POST --->|  auth/approle/role/       |
|  (root-token-formation)  |    secret-id    |    paylink-api/secret-id  |
|                          |    -wrap-ttl    |                           |
|                          |<-- (2) ---------|  secret_id rangé dans le  |
|                          |  wrapping_token |  cubbyhole du wrapping    |
+-----------+--------------+                 |  token (TTL 120s, 1 usage)|
            |                                +---------------------------+
     (3) dépôt fichiers                                  ^   ^
            v                                            |   |
   ./handoff/role-id.txt        (canal de                |   |
   ./handoff/wrapping-token.txt  livraison)              |   |
            |                                            |   |
+-----------v--------------+                             |   |
| app-unwrap-login.sh      |---- (4) unwrap -------------+   |
|  "API PayLink"           |<--- secret_id (usage unique)    |
|  AUCUN token admin       |---- (5) login role_id+secret_id-+
|                          |<--- token applicatif (TTL 15m)
|                          |---- (6) kv get secret/paylink/api
|                          |---- (7) token renew (boucle)
+--------------------------+
```

## Étapes

### Étape 1 — Préparer et comprendre le script opérateur (10 min)

Objectif : générer la livraison wrappée sans jamais voir le secret_id.

1. Copiez les scripts du dépôt dans un répertoire de travail et rendez-les
   exécutables :
   ```bash
   mkdir -p ~/tp2 && cd ~/tp2
   cp "<chemin_du_depot>/code/module-02/deploy-wrap.sh" .
   cp "<chemin_du_depot>/code/module-02/app-unwrap-login.sh" .
   chmod +x deploy-wrap.sh app-unwrap-login.sh
   ```

2. Ouvrez `deploy-wrap.sh` et répondez par écrit à ces deux questions
   avant de le lancer :
   - À quel moment le secret_id est-il créé, et pourquoi le script ne
     peut-il pas l'afficher ?
   - À quoi sert l'appel à `sys/wrapping/lookup` à la fin du script ?

3. Lancez la livraison :
   ```bash
   ./deploy-wrap.sh ./handoff
   ```

4. Inspectez le répertoire `./handoff` et vérifiez qu'aucun fichier ne
   contient de secret_id :
   ```bash
   ls -l ./handoff
   cat ./handoff/role-id.txt
   cat ./handoff/wrapping-lookup.txt
   grep -r "secret_id" ./handoff || echo "aucun secret_id en clair : OK"
   ```

Point de contrôle : `./handoff` contient `role-id.txt`,
`wrapping-token.txt` (permissions `600`) et `wrapping-lookup.txt` dont le
`creation_path` vaut `auth/approle/role/paylink-api/secret-id`. Le mot
`secret_id` n'apparaît dans aucun fichier livré.

### Étape 2 — Démarrer l'« application » PayLink (10 min)

Objectif : consommer la livraison — unwrap, login, lecture, renew.

Attention au chrono : le wrapping token expire 120 secondes après l'étape 1.
S'il est déjà périmé, relancez simplement `./deploy-wrap.sh ./handoff`.

1. Ouvrez `app-unwrap-login.sh` et repérez les 5 phases (livraison, unwrap,
   login, lecture, renew). Notez quel token est utilisé pour chaque appel à
   Vault : l'application reçoit-elle à un moment un token d'administration ?

2. Lancez l'application avec une boucle de renew raccourcie pour le lab
   (2 renews espacés de 5 secondes) :
   ```bash
   RENEW_INTERVAL=5 RENEW_MAX=2 ./app-unwrap-login.sh ./handoff
   ```

3. Pendant l'exécution, notez : la confirmation d'unwrap, les policies et
   le TTL du token obtenu, les valeurs lues, et le TTL rechargé à chaque
   renew.

Point de contrôle : le script affiche `unwrap OK`, un login avec
`policies [default paylink-read]` et `ttl 15m`, la lecture de
`db_user = paylink_app`, puis `renew #1 OK — TTL rechargé à 900s` et
`renew #2 OK — TTL rechargé à 900s`. Le fichier
`./handoff/wrapping-token.txt` a été supprimé par l'application.

### Étape 3 — Jouer l'attaquant : interception du wrapping token (10 min)

Objectif : constater que le vol du secret_id en transit est détecté.

1. Préparez une nouvelle livraison dans un second répertoire :
   ```bash
   ./deploy-wrap.sh ./handoff2
   ```

2. Mettez votre casquette d'attaquant : vous avez copié
   `wrapping-token.txt` pendant son transit. Consommez-le AVANT
   l'application (ici avec l'alias, peu importe le token utilisé pour
   unwrapper) :
   ```bash
   v unwrap "$(cat ./handoff2/wrapping-token.txt)"
   ```
   Vous venez de voler un secret_id parfaitement valide.

3. Reprenez votre casquette d'exploitant : l'application démarre et
   consomme sa livraison, comme à l'étape 2 :
   ```bash
   RENEW_INTERVAL=5 RENEW_MAX=1 ./app-unwrap-login.sh ./handoff2
   echo "code retour : $?"
   ```

4. Analysez la sortie : quel code HTTP reçoit l'application ? Que doit
   faire l'équipe dans ce cas (trois actions) ?

Point de contrôle : l'application affiche l'erreur 400
`wrapping token is not valid or does not exist`, le message
`ALERTE : unwrap impossible` et sort en code retour 1. Sans wrapping, ce
vol serait passé totalement inaperçu.

### Étape 4 — Neutraliser le secret_id volé (10 min)

Objectif : terminer la réponse à incident entamée à l'étape 3.

1. Le secret_id volé à l'étape 3 est toujours actif (TTL 60 min,
   5 usages). Listez les accessors des secret_id du rôle :
   ```bash
   v list auth/approle/role/paylink-api/secret-id
   ```

2. Retrouvez l'accessor du secret_id volé : il figure dans la sortie de
   votre `v unwrap` de l'étape 3 (`secret_id_accessor`). Détruisez-le :
   ```bash
   v write auth/approle/role/paylink-api/secret-id-accessor/destroy \
       secret_id_accessor=<accessor_du_secret_id_volé>
   ```

3. Vérifiez que l'accessor a disparu de la liste, puis relivrez proprement
   (nouvelle livraison + application) pour remettre PayLink en service :
   ```bash
   ./deploy-wrap.sh ./handoff3
   RENEW_INTERVAL=5 RENEW_MAX=1 ./app-unwrap-login.sh ./handoff3
   ```

Point de contrôle : la destruction répond `Success! Data written to: ...`,
l'accessor volé n'apparaît plus dans la liste, et la nouvelle livraison
aboutit à un login et une lecture réussis.
