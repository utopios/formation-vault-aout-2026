# Démo 2.1 — AppRole de bout en bout : du rôle au secret lu



```bash
v auth enable approle
```


```bash
v write auth/approle/role/paylink-api \
    token_policies=paylink-read \
    token_ttl=15m token_max_ttl=1h \
    secret_id_ttl=60m secret_id_num_uses=5
```



```bash
v read auth/approle/role/paylink-api
```

```
Key                        Value
---                        -----
bind_secret_id             true
local_secret_ids           false
secret_id_bound_cidrs      <nil>
secret_id_num_uses         5
secret_id_ttl              1h
token_bound_cidrs          []
token_explicit_max_ttl     0s
token_max_ttl              1h
token_no_default_policy    false
token_num_uses             0
token_period               0s
token_policies             [paylink-read]
token_ttl                  15m
token_type                 default
```



```bash
v read auth/approle/role/paylink-api/role-id
```

```
Key        Value
---        -----
role_id    ...
```



```bash
v write -f auth/approle/role/paylink-api/secret-id
```

```
Key                   Value
---                   -----
secret_id             ...
secret_id_accessor    ...
secret_id_num_uses    5
secret_id_ttl         1h
```


```bash
v write auth/approle/login \
    role_id=... \
    secret_id=...
```

```
Key                     Value
---                     -----
token                   ...
token_accessor          ...
token_duration          15m
token_renewable         true
token_policies          ["default" "paylink-read"]
identity_policies       []
policies                ["default" "paylink-read"]
token_meta_role_name    paylink-api
```

:

```bash
APP_TOKEN=...
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$APP_TOKEN \
    vault vault kv get secret/paylink/api
```

```
===== Secret Path =====
secret/data/paylink/api

======= Metadata =======
Key                Value
---                -----
created_time       2026-07-07T19:12:25.723492425Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            5

======= Data =======
Key            Value
---            -----
api_key        pk_live_99Z
db_password    NewRotation!42
db_user        paylink_app
```



```bash
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$APP_TOKEN \
    vault vault kv put secret/paylink/api api_key=hack
```

```
Error writing data to secret/data/paylink/api: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/secret/data/paylink/api
Code: 403. Errors:

* 1 error occurred:
	* permission denied
```



```bash
curl -s --request POST \
    --data '{"role_id":"f33ea47d-7175-d0fb-5089-7ae531f967c2","secret_id":"<secret_id>"}' \
    http://127.0.0.1:8200/v1/auth/approle/login \
    | jq '.auth | {client_token, token_policies, lease_duration, renewable}'
```

```
{
  "client_token": "...",
  "token_policies": [
    "default",
    "paylink-read"
  ],
  "lease_duration": 900,
  "renewable": true
}
```



```bash
curl -s --header "X-Vault-Token: <client_token>" \
    http://127.0.0.1:8200/v1/secret/data/paylink/api | jq '.data.data'
```

```
{
  "api_key": "pk_live_99Z",
  "db_password": "NewRotation!42",
  "db_user": "paylink_app"
}
```

