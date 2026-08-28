# Exercice 4.1 — Cycle de vie d'un lease en accéléré

> Module : 4 — Secrets dynamiques et chiffrement as a service
> Durée estimée : 25 min
> Difficulté : 2 / 5
> Type : Exercice d'application

## Objectifs pédagogiques

À la fin de cet exercice, vous serez capable de :

- Créer un rôle database avec un TTL court et générer des credentials éphémères
- Inspecter, renouveler et laisser expirer un lease, et prédire ce qui se passe côté PostgreSQL
- Expliquer la différence entre `default_ttl` et `max_ttl` et qui doit renouveler

## Prérequis

- Avoir suivi la partie « Cycle de vie des leases » du module 4 (démo 4.1 jouée : moteur `database` activé et connexion `database/config/paylink-pg` configurée)
- Environnement : lab Podman (`code/lab/lab-up.sh`), conteneurs `vault` (Vault 1.20.4) et `postgres` sur le réseau `vault-lab`
- Outils : alias `v` (cf. module 1) :
  ```bash
  alias v='podman exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root-token-formation vault vault'
  ```

## Contexte

L'équipe PayLink veut comprendre ce qui arrivera à son API si elle « oublie »
de renouveler ses credentials PostgreSQL. Plutôt que d'attendre une heure en
production, vous allez rejouer tout le cycle de vie d'un lease en accéléré,
avec un TTL de 2 minutes : génération, observation, renouvellement,
expiration, et constat côté base de données.

## Énoncé

### Partie 1 — Un rôle à durée de vie courte (5 min)

Créez un rôle `database/roles/paylink-court` qui s'appuie sur la connexion
`paylink-pg` existante, avec :

- les mêmes `creation_statements` que `paylink-readonly` (rôle `LOGIN`,
  `VALID UNTIL '{{expiration}}'`, `GRANT SELECT` sur le schéma `public`) ;
- `default_ttl=2m` et `max_ttl=4m`.

Attention : la connexion `paylink-pg` a une liste `allowed_roles`. Ajoutez-y
`paylink-court` (sans perdre les rôles déjà autorisés).

Résultat attendu : `v read database/creds/paylink-court` renvoie un
`lease_duration` de `2m` et un `username` en `v-token-paylink-c...`.

### Partie 2 — Observer le lease (5 min)

1. Générez des credentials et notez le `lease_id` complet.
2. Inspectez le lease avec `v lease lookup <lease_id>` : repérez `ttl`,
   `expire_time` et `renewable`.
3. Vérifiez côté PostgreSQL que le compte existe et notez son `valuntil` :

```bash
podman exec postgres psql -U postgres -d paylink \
  -c "SELECT usename, valuntil FROM pg_user WHERE usename LIKE 'v-token-%';"
```

Résultat attendu : le compte apparaît dans `pg_user`, avec un `valuntil`
environ 2 minutes dans le futur.

### Partie 3 — Renouveler, puis buter sur max_ttl (8 min)

1. Attendez environ 1 minute, puis renouvelez : `v lease renew <lease_id>`.
   Observez le nouveau `lease_duration`.
2. Renouvelez encore une ou deux fois, environ toutes les minutes, en
   observant `lease_duration` à chaque fois.
3. Notez ce qui change quand le lease approche de `max_ttl` (4 minutes après
   la création) : que devient `lease_duration` ? Que renvoie un renew une
   fois `max_ttl` atteint ?

Résultat attendu : les premiers renew repartent à `2m` ; à l'approche de
`max_ttl`, la durée accordée est tronquée, puis le renew est refusé.

### Partie 4 — Laisser expirer et constater (7 min)

1. Cessez de renouveler et attendez l'expiration complète.
2. Vérifiez que le lease a disparu : `v lease lookup <lease_id>`.
3. Re-vérifiez `pg_user` côté PostgreSQL : que reste-t-il du compte ?
4. Tentez une connexion `psql` avec les credentials expirés :

```bash
podman exec -e PGPASSWORD='<password note en partie 2>' postgres \
  psql -h 127.0.0.1 -U '<username note en partie 2>' -d paylink -c "SELECT 1;"
```

Résultat attendu : lease introuvable, compte absent de `pg_user`, connexion
refusée avec `FATAL: role ... does not exist`.

### Questions de compréhension

Répondez par écrit (2-3 phrases chacune) :

1. Quelle est la différence de *déclencheur* entre l'expiration observée ici
   et le `lease revoke` de la démo 4.1 ? La conséquence côté PostgreSQL
   est-elle différente ?
2. Dans une API PayLink qui tourne 24h/24, qui devrait exécuter le
   `lease renew` que vous avez tapé à la main ? Citez deux options.
3. Que doit faire l'application quand `max_ttl` est atteint et que le renew
   est refusé ?
4. À quoi sert le `VALID UNTIL` vu dans `pg_user`, alors que Vault supprime
   déjà le compte à l'expiration du lease ?
