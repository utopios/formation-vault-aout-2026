# Démo 3.2 — Policies templatées : pourquoi ça fait 403 ?




### Environnement

- [ ] Lab du module 1 démarré, alias en place :
      ```bash
      alias v='podman exec -i -e VAULT_TOKEN -e VAULT_ADDR=http://127.0.0.1:8200 vault vault'
      export VAULT_TOKEN=root-token-formation
      ```
- [ ] Auth AppRole activée et rôle `paylink-api` créé (module 2, TP 2).
      IMPORTANT : un login AppRole a DÉJÀ eu lieu au module 2 — c'est
      précisément ce qui rend cette démo possible (entité auto-créée).
- [ ] `jq` et `python3` disponibles sur le poste (loupe de diagnostic, acte 4)
- [ ] Terminal avec police lisible (min 16pt)
- [ ] Fenêtres positionnées (terminal + slide « entité / alias / auth method »)



#### Étape 1.1 — La policy templatée

```bash
v policy write service-scoped - <<'EOF'
# Chaque service ne voit que son propre espace
path "secret/data/services/{{identity.entity.name}}/*" {
  capabilities = ["read", "list"]
}
EOF
```

Résultat attendu à l'écran :
```
Success! Uploaded policy: service-scoped
```


#### Étape 1.2 — Deux espaces de secrets, deux services

```bash
v kv put secret/services/paylink-api/config db_host=pg.internal
v kv put secret/services/meditrack-api/config db_host=pg2.internal
```

Résultat attendu à l'écran (pour chacun, extrait) :
```
====== Secret Path ======
secret/data/services/paylink-api/config

======= Metadata =======
Key                Value
---                -----
created_time       2026-07-07T19:06:52.164838254Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1
```


#### Étape 2.1 — Entité + alias créés à la main

```bash
v write identity/entity name=paylink-api policies=service-scoped
```

Résultat attendu à l'écran :
```
Key        Value
---        -----
aliases    <nil>
id         c118d079-3d8f-6cc2-b028-dacf2c099ce6
name       paylink-api
```

```bash
ACCESSOR=$(v auth list -format=json | jq -r '."approle/".accessor')
v write identity/entity-alias name=paylink-api \
    canonical_id=c118d079-3d8f-6cc2-b028-dacf2c099ce6 \
    mount_accessor=$ACCESSOR
```

Résultat attendu à l'écran :
```
Key             Value
---             -----
canonical_id    c118d079-3d8f-6cc2-b028-dacf2c099ce6
id              9d0f1b23-a32b-d0ef-7deb-0e3d3b9923ae
```

#### Étape 2.2 — Login AppRole

```bash
v read auth/approle/role/paylink-api/role-id
```

Résultat attendu à l'écran :
```
Key        Value
---        -----
role_id    f33ea47d-7175-d0fb-5089-7ae531f967c2
```

```bash
v write -f auth/approle/role/paylink-api/secret-id
```

Résultat attendu à l'écran :
```
Key                   Value
---                   -----
secret_id             30c91e88-abcf-344b-e2fb-f7590aa08ac6
secret_id_accessor    a1370b04-446a-f084-8ba6-4e616e05973d
secret_id_num_uses    5
secret_id_ttl         1h
```

(5 utilisations : de quoi couvrir les logins successifs de la démo.)

```bash
v write auth/approle/login \
    role_id=f33ea47d-7175-d0fb-5089-7ae531f967c2 \
    secret_id=30c91e88-abcf-344b-e2fb-f7590aa08ac6
```

Résultat attendu à l'écran :
```
Key                     Value
---                     -----
token                   ...
token_accessor          UGlG0OwwzvNptgveEfbJVAx3
token_duration          15m
token_renewable         true
token_policies          ["default" "paylink-read"]
identity_policies       []
policies                ["default" "paylink-read"]
token_meta_role_name    paylink-api
```



```bash
T_APP=...   # copier depuis la sortie
VAULT_TOKEN=$T_APP v kv get secret/services/paylink-api/config
```

Résultat attendu à l'écran — LE 403 INATTENDU :
```
Error reading secret/data/services/paylink-api/config: Error making API request.

URL: GET http://127.0.0.1:8200/v1/secret/data/services/paylink-api/config
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```




```bash
v write identity/entity-alias \
    name=f33ea47d-7175-d0fb-5089-7ae531f967c2 \
    canonical_id=c118d079-3d8f-6cc2-b028-dacf2c099ce6 \
    mount_accessor=$ACCESSOR
```

Résultat attendu à l'écran :
```
Error writing data to identity/entity-alias: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/identity/entity-alias
Code: 400. Errors:

* Alias cannot be updated as the given entity already has an alias for this mount
```



```bash
v write identity/entity-alias/id/9d0f1b23-a32b-d0ef-7deb-0e3d3b9923ae \
    name=f33ea47d-7175-d0fb-5089-7ae531f967c2 \
    canonical_id=c118d079-3d8f-6cc2-b028-dacf2c099ce6 \
    mount_accessor=$ACCESSOR
```

Résultat attendu à l'écran :
```
Error writing data to identity/entity-alias/id/9d0f1b23-a32b-d0ef-7deb-0e3d3b9923ae: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/identity/entity-alias/id/9d0f1b23-a32b-d0ef-7deb-0e3d3b9923ae
Code: 400. Errors:

* alias with combination of mount accessor and name already exists
```
