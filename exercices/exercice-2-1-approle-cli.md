# Exercice 2.1 — Un AppRole pour MediTrack

> Module : 2 — Authentification applicative
> Durée estimée : 25 min
> Difficulté : 2 / 5
> Type : Exercice d'application

## Objectifs pédagogiques

À la fin de cet exercice, vous serez capable de :

- Créer un rôle AppRole avec des TTL et des compteurs d'usage adaptés à un service
- Obtenir un token applicatif par login AppRole et vérifier les policies qu'il porte
- Constater l'isolation entre services imposée par les policies
- Observer ce qui se passe quand un secret_id épuise son `secret_id_num_uses`

## Prérequis

- Avoir suivi la partie `AppRole en profondeur` du module 2 (démo 2.1 comprise)
- Environnement : lab Podman du cours, conteneur `vault` démarré (Vault 1.20.4)
- Outils : l'alias du lab chargé dans votre shell :

```bash
alias v='podman exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root-token-formation vault vault'
```

## Contexte

PayLink a son identité AppRole depuis la démo 2.1. Au tour du deuxième
service du groupe : **MediTrack**, l'API santé. Ses secrets vivent sous
`secret/services/meditrack-api/` (déjà peuplés au module 1). Les exigences
de l'équipe sécurité sont plus strictes que pour PayLink : tokens de
10 minutes renouvelables 30 minutes maximum, secret_id valable 30 minutes
et **3 utilisations** seulement.

La policy à utiliser vous est fournie (l'écriture de policies est l'objet
du module 3) :

```bash
podman exec -i -e VAULT_ADDR=http://127.0.0.1:8200 \
  -e VAULT_TOKEN=root-token-formation vault \
  vault policy write meditrack-read - <<'EOF'
# Lecture seule des secrets du service MediTrack
path "secret/data/services/meditrack-api/*" {
  capabilities = ["read"]
}
path "secret/metadata/services/meditrack-api/*" {
  capabilities = ["read", "list"]
}
EOF
```

(Remarquez le `-i` : l'alias `v` ne transmet pas l'entrée standard,
il faut la version longue de `podman exec` pour le heredoc.)

## Énoncé

### Partie 1 — Créer le rôle meditrack-api

Après avoir chargé la policy `meditrack-read` ci-dessus, créez le rôle
`meditrack-api` sur la méthode `approle/` (déjà activée) avec les
paramètres exigés par l'équipe sécurité :

- policies des tokens : `meditrack-read`
- TTL du token : 10 minutes, plafond absolu : 30 minutes
- TTL du secret_id : 30 minutes, nombre d'usages : 3

Relisez ensuite le rôle pour contrôler vos paramètres.

Résultat attendu : `v read auth/approle/role/meditrack-api` affiche
`secret_id_num_uses 3`, `secret_id_ttl 30m`, `token_max_ttl 30m`,
`token_policies [meditrack-read]` et `token_ttl 10m`.

### Partie 2 — Login et vérification des policies

1. Récupérez le `role_id` du rôle.
2. Générez un `secret_id`.
3. Authentifiez-vous en AppRole avec ce couple et observez le token rendu.
4. Comparez le champ `token_policies` de votre token avec celui obtenu en
   démo 2.1 pour PayLink : qu'est-ce qui change, qu'est-ce qui est commun ?
5. Avec le token obtenu (et lui seul), lisez
   `secret/services/meditrack-api/config`, puis tentez de lire
   `secret/paylink/api`. Expliquez les deux résultats.

Résultat attendu : la lecture MediTrack réussit ; la lecture PayLink échoue
avec un code 403 `permission denied`. Le token porte
`["default" "meditrack-read"]` et dure 10 minutes.

### Partie 3 — Épuiser le secret_id

Votre login de la partie 2 a déjà consommé 1 des 3 usages du secret_id.

1. Rejouez le login jusqu'à épuisement du compteur.
2. Observez précisément l'erreur du login de trop : code HTTP et message.
3. Que faut-il faire pour que MediTrack puisse à nouveau se loguer ?
   Faites-le et vérifiez par un login réussi.

Résultat attendu : le 4e login échoue en 400 avec
`invalid role or secret ID` ; un nouveau `secret_id` permet de repartir.

