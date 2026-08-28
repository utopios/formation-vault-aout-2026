# Exercice 3.1 — Écrire une policy de moindre privilège

> Module : 3 — Policies et moindre privilège
> Durée estimée : 30 min
> Difficulté : 2 / 5
> Type : Exercice d'application

## Objectifs pédagogiques

À la fin de cet exercice, vous serez capable de :

- Traduire un besoin d'accès exprimé en langage métier en une policy HCL
  qui n'accorde rien de plus ;
- Cibler correctement les chemins KV v2 (`data/`, `metadata/`, `delete/`) ;
- Prouver le comportement d'une policy avec `vault token capabilities`
  avant toute mise en production.

## Prérequis

- Avoir suivi la partie « Syntaxe HCL » du module 3 et la démo 3.1
- Environnement : lab Podman du module 1 (conteneur `vault`, Vault 1.20.4),
  alias en place :
  ```bash
  alias v='podman exec -i -e VAULT_TOKEN -e VAULT_ADDR=http://127.0.0.1:8200 vault vault'
  export VAULT_TOKEN=root-token-formation
  ```
- Outils : `podman`, la CLI `vault` via l'alias
- Secrets présents (modules 1 et 2) : `secret/paylink/api`,
  `secret/paylink/smtp`, `secret/paylink/webhooks`

## Contexte

L'équipe plateforme de PayLink outille son pipeline de déploiement. Le
runner CI/CD doit accéder à Vault, et l'équipe vous a transmis son besoin,
tel quel, dans le ticket OPS-1187 :

> « Le pipeline doit pouvoir lire tous les secrets sous `paylink/`.
> Il doit pouvoir écrire — mais uniquement `paylink/webhooks`, pour la
> rotation du webhook secret à chaque déploiement. Il doit pouvoir lister
> les secrets existants. Et il ne doit JAMAIS pouvoir supprimer quoi que
> ce soit, même pas une version. »

Votre mission : traduire ce ticket en une policy `paylink-cicd`, puis la
prouver.

## Énoncé

### Partie 1 — Traduire le besoin en HCL

Écrivez la policy `paylink-cicd` et chargez-la dans Vault
(`v policy write paylink-cicd -`).

Contraintes :

1. Lecture de tous les secrets sous `paylink/` — lecture seule ;
2. Écriture (création ET mise à jour) du seul secret `paylink/webhooks` ;
3. Listing des secrets sous `paylink/` (pensez au mount KV v2 : quelle
   arborescence sert au listing ?) ;
4. Interdiction de toute suppression : la suppression de la dernière
   version, la suppression de versions ciblées et la destruction
   définitive doivent être refusées — on veut un refus EXPLICITE pour les
   chemins de suppression de versions, pas seulement une absence de droit.

Résultat attendu : `Success! Uploaded policy: paylink-cicd`, et
`v policy read paylink-cicd` affiche votre HCL.

### Partie 2 — Prouver la policy avec token capabilities

Créez un token de test qui porte la policy :

```bash
v token create -policy=paylink-cicd -ttl=1h
```

Copiez le token dans une variable (`T_CICD=hvs.…`), puis vérifiez ses
droits sur les 6 chemins suivants. Votre policy est correcte si et
seulement si vous obtenez EXACTEMENT ces verdicts :

| # | Chemin | Verdict attendu |
|---|--------|-----------------|
| 1 | `secret/data/paylink/api` | `read` |
| 2 | `secret/data/paylink/webhooks` | `create, read, update` |
| 3 | `secret/data/paylink/webhooks/github` | `read` |
| 4 | `secret/metadata/paylink/` | `list, read` |
| 5 | `secret/delete/paylink/api` | `deny` |
| 6 | `secret/data/meditrack/api` | `deny` |

```bash
v token capabilities $T_CICD <chemin>
```

Questions à vous poser (elles seront reprises au débrief) :

- Pourquoi le chemin 3 ne donne-t-il QUE `read`, alors qu'il commence par
  `secret/data/paylink/webhooks` ?
- Pourquoi le chemin 6 est-il `deny` alors qu'aucune de vos règles ne
  mentionne `meditrack` ?

### Partie 3 — La preuve par l'usage

Avec le token de test (`VAULT_TOKEN=$T_CICD v …`), vérifiez le comportement
réel :

1. Lire `secret/paylink/api` → doit réussir ;
2. Écrire `secret/paylink/webhooks` (par exemple
   `webhook_secret=whsec_v2_rotated`) → doit réussir ;
3. Écrire `secret/paylink/api` → doit échouer en 403 ;
4. Lister `secret/paylink` → doit réussir ;
5. Supprimer `secret/paylink/webhooks` (`kv delete`) → doit échouer en 403 ;
6. Supprimer une version précise
   (`kv delete -versions=1 secret/paylink/webhooks`) → doit échouer en 403,
   et l'URL de l'erreur doit montrer le chemin `secret/delete/…`.

Résultat attendu : chaque commande se comporte comme prévu ; notez pour
les cas 5 et 6 l'URL exacte que la CLI a appelée (elles diffèrent !).

## Indices (à consulter si bloqué)

<details>
<summary>Indice 1 — le listing ne marche pas</summary>

`vault kv list secret/paylink` n'appelle pas `secret/data/…` : il émet une
requête LIST sur `secret/metadata/paylink`. Vault ajoute un `/` final aux
requêtes LIST, ce qui permet au glob `secret/metadata/paylink/*` de
matcher. Vérifiez avec :
`VAULT_TOKEN=$T_CICD v kv list -output-curl-string secret/paylink`

</details>

<details>
<summary>Indice 2 — webhooks est en lecture seule alors que j'ai bien une règle dessus</summary>

Quand plusieurs règles peuvent matcher un chemin, Vault n'en applique
qu'UNE : celle du chemin le plus spécifique. Un chemin exact
(`secret/data/paylink/webhooks`) gagne sur un glob
(`secret/data/paylink/*`). Les capabilities ne s'additionnent pas entre
règles : mettez sur le chemin exact TOUT ce dont webhooks a besoin,
y compris `read`.

</details>

<details>
<summary>Indice 3 — interdire la suppression de versions</summary>

Sur KV v2, trois opérations distinctes : `kv delete` (dernière version) est
un DELETE sur `secret/data/…` ; `kv delete -versions=…` écrit sur
`secret/delete/…` ; `kv destroy` écrit sur `secret/destroy/…`. La première
se bloque en n'accordant pas `delete` sur `data/` ; les deux autres se
bloquent avec la capability `deny` sur leurs chemins respectifs — et `deny`
l'emporte sur tout, même si une autre policy accordait ces chemins.

</details>

