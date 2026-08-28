# Démo 4.2 — Transit : encrypt, rotate, rewrap, datakey

#### Étape 2.1 — Activer transit et créer la clé

```bash

v secrets enable transit
```

Résultat attendu à l'écran :

```
Success! Enabled the transit secrets engine at: transit/
```

```bash
v write -f transit/keys/paylink-cards type=aes256-gcm96
v read transit/keys/paylink-cards
```

Résultat attendu à l'écran :

```
Key                       Value
---                       -----
allow_plaintext_backup    false
auto_rotate_period        0s
deletion_allowed          false
derived                   false
exportable                false
imported_key              false
keys                      map[1:1783451454]
latest_version            1
min_available_version     0
min_decryption_version    1
min_encryption_version    0
name                      paylink-cards
supports_decryption       true
supports_derivation       true
supports_encryption       true
supports_signing          false
type                      aes256-gcm96
```


#### Étape 2.2 — Chiffrer (le plaintext est en base64 !)

```bash
printf '%s' '4970-1234-5678-9010' | base64
```

Résultat attendu à l'écran :

```
NDk3MC0xMjM0LTU2NzgtOTAxMA==
```

```bash
v write transit/encrypt/paylink-cards plaintext=NDk3MC0xMjM0LTU2NzgtOTAxMA==
```

Résultat attendu à l'écran :

```
Key            Value
---            -----
ciphertext     vault:v1:FQ9Dhk+8tFzHSZSHkMzboJrrJoBZJVzZhxQOIh4BQbgMekkntBKtJNUvAhwXbvI=
key_version    1
```


```bash
v write -field=ciphertext transit/encrypt/paylink-cards \
    plaintext=NDk3MC0xMjM0LTU2NzgtOTAxMA==
```

Résultat attendu à l'écran :

```
vault:v1:rli0NrfcQrJAhqYw3AEgjxkp56jQgAyQjuNuWNyL2XOEOPqNOnqDlm2pFWbcqkk=
```

#### Étape 2.3 — Déchiffrer

```bash
v write -field=plaintext transit/decrypt/paylink-cards \
    ciphertext="vault:v1:FQ9Dhk+8tFzHSZSHkMzboJrrJoBZJVzZhxQOIh4BQbgMekkntBKtJNUvAhwXbvI=" \
  | base64 -d
```

Résultat attendu à l'écran :

```
4970-1234-5678-9010
```

#### Étape 2.4 — Rotation de clé

```bash
v write -f transit/keys/paylink-cards/rotate
v read transit/keys/paylink-cards
```

Résultat attendu à l'écran (extrait) :

```
keys                      map[1:1783451454 2:1783451454]
latest_version            2
min_decryption_version    1
```



#### Étape 2.5 — Rewrap : re-chiffrer sans exposer le clair

```bash
v write transit/rewrap/paylink-cards \
    ciphertext="vault:v1:rli0NrfcQrJAhqYw3AEgjxkp56jQgAyQjuNuWNyL2XOEOPqNOnqDlm2pFWbcqkk="
```

Résultat attendu à l'écran :

```
Key            Value
---            -----
ciphertext     vault:v2:cT0S2AV+skh1lE/rFgXdsYhY86QcYZoXw99MpOWhPGUV6cwCCSuMGFW167g1TTo=
key_version    2
```


#### Étape 2.6 — Datakey : l'enveloppe pour les gros volumes



```bash

v write -f transit/datakey/plaintext/paylink-cards
```

Résultat attendu à l'écran :

```
Key            Value
---            -----
ciphertext     vault:v2:xmKl2hXjc7W5VovmI/a5LRqJnLGcBTBRsKT7SSrV91/mYtoo8alfZsXm9mYDffGdryA9eIS/6IG0fJVO
key_version    2
plaintext      cow+DrivxRem5FDv5RxGAlfh1MvmNFijxH/QjD4owZU=
```


#### Étape 2.7 — L'ancien ciphertext v1 reste déchiffrable

```bash
v write -field=plaintext transit/decrypt/paylink-cards \
    ciphertext="vault:v1:FQ9Dhk+8tFzHSZSHkMzboJrrJoBZJVzZhxQOIh4BQbgMekkntBKtJNUvAhwXbvI=" \
  | base64 -d
```

Résultat attendu à l'écran :

```
4970-1234-5678-9010
```