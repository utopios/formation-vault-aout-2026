

```bash
v write -wrap-ttl=120s -f auth/approle/role/paylink-api/secret-id
```


```

```bash
v write sys/wrapping/lookup token=<wrapping_token>
```

```
Key              Value
---              -----
creation_path    auth/approle/role/paylink-api/secret-id
creation_time    2026-07-07T19:50:36.729394622Z
creation_ttl     2m
```



#### Étape 2.3 — Unwrap : la seule et unique ouverture

```bash
v unwrap hvs.<token>
```

```
Key                   Value
---                   -----
secret_id             ...
secret_id_accessor    ...
secret_id_num_uses    5
secret_id_ttl         1h
```



#### Étape 2.4 — Second unwrap : la preuve d'usage unique

```bash
v unwrap hvs.<token>
```

```
Error unwrapping: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/sys/wrapping/unwrap
Code: 400. Errors:

* wrapping token is not valid or does not exist
```
