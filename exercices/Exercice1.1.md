# Exercice 1.1 — Le service Ledger entre dans Vault

> Module : 1 — Vault côté consommateur : concepts, CLI & API REST
> Durée estimée : 30 min
> Difficulté : 2 / 5
> Type : Exercice d'application

## Objectifs pédagogiques

À la fin de cet exercice, vous serez capable de :

- Démarrer le lab Vault (docker) et vérifier son état par deux canaux
- Écrire, versionner et faire tourner un secret KV v2 en CLI
- Lire et écrire un secret via l'API REST, en manipulant les chemins réels
- Utiliser le cycle `delete` / `undelete` / `destroy` à bon escient

## Prérequis

- Avoir suivi les parties « CLI » et « API REST » du module 1
- Environnement : Podman opérationnel, port 8200 libre
- Outils : `curl` ; `jq` recommandé

## Contexte

`ledger-api` est le service de **rapprochement comptable** du groupe
PayLink : chaque nuit, il rapproche les paiements encaissés des relevés
bancaires, puis dépose un rapport sur un stockage objet.

Il est en production depuis dix-huit mois. Ses credentials vivent dans un
fichier `config/ledger.properties`, présent sur les trois serveurs qui
exécutent le batch :

```properties
ledger.db.user=ledger_batch
ledger.db.password=Ldg#Init2024
ledger.s3.access_key=AKIA7TQX9LEDGER01
ledger.s3.secret_key=wJalr0XUtnFEMI1K7MDENG2bPxRfiCY
```

L'audit de clôture d'exercice a produit deux constats :

1. Ces valeurs n'ont **jamais** été changées depuis la mise en production.
2. Trois personnes ayant quitté l'entreprise les ont eues sous les yeux.

Votre mission : faire entrer ces secrets dans Vault sous
`secret/ledger/*`, tourner ce qui doit l'être, et **détruire
définitivement** les valeurs compromises — celles que les partants ont
connues.

## Énoncé

### Partie 1 — Monter le lab et vérifier le serveur

Démarrez le lab avec le script fourni, puis définissez l'alias CLI :

```bash
cd code/lab && ./lab-up.sh
alias v='docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root-token-formation vault vault'
```

Vérifiez que le serveur répond **de deux façons différentes** : avec la
CLI, puis avec l'endpoint de santé de l'API — celui qui ne demande aucun
token.

Puis répondez : quels moteurs de secrets sont montés sur ce Vault, et
lequel allez-vous utiliser ?

Résultat attendu : `Sealed: false` côté CLI ; côté API, un JSON contenant
`"initialized": true` et `"sealed": false`. Le moteur à utiliser est
`secret/`, de type `kv` (version 2, monté d'office en mode dev).

### Partie 2 — Faire entrer Ledger dans Vault

1. Créez le secret `secret/ledger/db` avec les clés `user` et `password`
   (valeurs du fichier de configuration ci-dessus).
2. Créez le secret `secret/ledger/s3` avec les clés `access_key` et
   `secret_key`.
3. Vérifiez que `secret/ledger` contient bien deux entrées.

Résultat attendu : deux secrets en `version 1`, et un listing affichant
`db` et `s3`.

### Partie 3 — Tourner le mot de passe compromis

La règle interne est claire : après un départ, les credentials connus de
la personne sont réputés compromis. Vous tournez donc le mot de passe de
la base.

1. Écrivez une **version 2** de `secret/ledger/db` où `password` devient
   `Ldg#Rot2026` — sans perdre la clé `user`.
2. La clé d'accès S3 doit elle aussi tourner, mais **seule la clé secrète
   change** (l'access key reste la même, c'est un identifiant) : passez
   `secret_key` à `wJalr9NEWKEY4RotatedX2026abcDEF` avec la commande faite
   pour ne toucher qu'une seule clé.
3. Vérifiez sur les deux secrets : quelle est la version courante de
   chacun ? La version 1 de `secret/ledger/db` contient-elle encore
   l'ancien mot de passe ?

Résultat attendu : `secret/ledger/db` et `secret/ledger/s3` sont tous deux
en `version 2` ; la version 1 de `db` contient toujours `Ldg#Init2024`.

**Question de compréhension** — pourquoi les étapes 1 et 2 n'utilisent-elles
pas la même commande ? Que se serait-il passé si vous aviez employé celle
de l'étape 1 pour l'étape 2, en ne passant que `secret_key` ?

### Partie 4 — Consommer les secrets comme le ferait le batch

Le script de démarrage du batch ne sait pas lire un tableau : il lui faut
des valeurs brutes.

1. En CLI, extrayez la seule valeur de `password` depuis
   `secret/ledger/db` — une ligne de sortie, sans tableau.
2. En `curl`, lisez `secret/ledger/s3` avec le token root et retrouvez vos
   deux valeurs dans la réponse JSON. **Où sont-elles exactement dans la
   structure ?**
3. Le batch doit désormais écrire lui-même un secret : la file de
   notification qu'il utilise vient d'être provisionnée. Créez
   `secret/ledger/queue` **en `curl`**, avec les clés
   `url=amqp://mq.paylink.internal:5672` et `vhost=ledger`.

Résultat attendu : `Ldg#Rot2026` en 1 ; en 2, les valeurs sous
`data.data` ; en 3, une réponse HTTP contenant `"version": 1`.

**Question de compréhension** — le chemin que vous avez écrit dans vos
deux commandes `curl` n'est pas celui que vous tapez en CLI. Quelle est la
différence, et pourquoi existe-t-elle ?

### Partie 5 — Effacer ce qui doit l'être

Le rapport d'audit exige que les valeurs connues des trois partants ne
soient **plus récupérables**, y compris par un administrateur Vault.

1. Avant d'agir, listez l'historique de `secret/ledger/db` : combien de
   versions existe-t-il, et laquelle contient les valeurs compromises ?
2. La file de notification `secret/ledger/queue` a été créée par erreur
   avec un mauvais `vhost` : retirez-la de la circulation, puis vérifiez
   ce que renvoie une lecture. Le secret a-t-il disparu ?
3. Finalement, ce n'était pas une erreur : restaurez-la.
4. Traitez maintenant l'exigence de l'audit sur `secret/ledger/db` : la
   version qui contient `Ldg#Init2024` doit devenir irrécupérable.
   Vérifiez ensuite que la version courante fonctionne toujours.

Résultat attendu : après l'étape 2, un `deletion_time` renseigné et plus
aucun bloc `Data` ; après l'étape 3, la valeur est de retour ; après
l'étape 4, la version 1 affiche `destroyed true` et sa lecture ne renvoie
plus aucune donnée, tandis que `password` vaut toujours `Ldg#Rot2026` en
version courante.

**Question de compréhension** — quelle est la différence entre ce que vous
avez fait à l'étape 2 et ce que vous avez fait à l'étape 4 ? Laquelle des
deux répond à une exigence réglementaire d'effacement ?

## Indices (à consulter si bloqué)

<details>
<summary>Indice 1 — Vérifier le serveur sans token</summary>

Un seul endpoint de l'API se lit sans en-tête `X-Vault-Token` :

```bash
curl -s http://127.0.0.1:8200/v1/sys/health | jq
```

Pour lister les moteurs montés, c'est `v secrets list`.

</details>

<details>
<summary>Indice 2 — Deux commandes d'écriture, deux comportements</summary>

`kv put` remplace **tout** le secret : les clés que vous ne repassez pas
disparaissent de la nouvelle version. `kv patch` fusionne avec la version
courante : il ne touche qu'aux clés que vous lui donnez.

Les deux créent une nouvelle version.

</details>

<details>
<summary>Indice 3 — Une valeur brute en CLI</summary>

Regardez l'option `-field=<clé>` de `vault kv get`. L'alternative :
`-format=json` suivi de `jq -r .data.data.password`.

</details>

<details>
<summary>Indice 4 — Écrire en curl</summary>

Le chemin logique `secret/ledger/queue` devient `/v1/secret/data/ledger/queue`.
La méthode est `POST`, et — c'est le piège — les clés doivent être
**enveloppées** :

```bash
-d '{"data":{"cle":"valeur"}}'
```

Sans l'enveloppe `data`, Vault répond 400.

</details>

<details>
<summary>Indice 5 — Voir l'historique complet</summary>

`v kv metadata get <chemin>` affiche la version courante, le nombre de
versions conservées, et l'état de chaque version (`deletion_time`,
`destroyed`).

</details>

<details>
<summary>Indice 6 — Retirer, restaurer, effacer</summary>

Trois commandes, trois niveaux :

- `kv delete` masque la version courante — réversible
- `kv undelete -versions=N` la restaure
- `kv destroy -versions=N` efface les données de la version N — définitif

</details>

## Pour aller plus loin (bonus)

1. **Étiquetez vos secrets** : ajoutez à `secret/ledger/db` les
   `custom_metadata` `owner=team-finance` et `rotation=quarterly`
   (voyez `vault kv metadata put -custom-metadata=...`), puis vérifiez
   qu'elles apparaissent en CLI et dans la réponse `curl`. Question :
   pourrait-on y mettre une valeur sensible ? Regardez sous quel chemin
   elles sont lisibles.

2. **Limitez l'historique** : configurez `secret/ledger/db` pour ne
   conserver que 3 versions (`kv metadata put -max-versions=3`), puis
   écrivez quatre nouvelles versions d'affilée. Que devient la version la
   plus ancienne ? Vérifiez avec `kv metadata get`.

3. **Le code HTTP du soft delete** : refaites un `kv delete` sur
   `secret/ledger/queue`, puis relisez-le en `curl` avec
   `-o /dev/null -w '%{http_code}\n'`. Quel code obtenez-vous ? Est-ce
   cohérent avec ce que renvoie la CLI ?