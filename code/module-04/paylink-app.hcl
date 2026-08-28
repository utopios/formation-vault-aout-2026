# Policy applicative PayLink — TP 4.
# Strictement le necessaire (deni par defaut pour tout le reste) :
#   1. obtenir des credentials PostgreSQL dynamiques DML,
#   2. chiffrer / dechiffrer avec la cle transit paylink-cards.
# Pas d'acces au KV, pas d'acces aux autres roles database, pas d'acces
# a la gestion des cles transit (rotation, config, lecture de la cle).

# Credentials dynamiques : chaque read fabrique un compte PostgreSQL ephemere.
path "database/creds/paylink-dml" {
  capabilities = ["read"]
}

# Chiffrement des numeros de carte (POST => capability update, pas read).
path "transit/encrypt/paylink-cards" {
  capabilities = ["update"]
}

# Dechiffrement (service de remboursement / verification).
path "transit/decrypt/paylink-cards" {
  capabilities = ["update"]
}
