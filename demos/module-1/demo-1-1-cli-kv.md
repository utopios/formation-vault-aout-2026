# Démo 1.1 — CLI et KV v2 : le cycle de vie complet d'un secret PayLink

```bash
v secrets list
```

Résultat attendu à l'écran :

```
Path          Type         Accessor              Description
----          ----         --------              -----------
cubbyhole/    cubbyhole    cubbyhole_bbf250a7    per-token private secret storage
identity/     identity     identity_930ed060     identity store
secret/       kv           kv_35caf6de           key/value secret storage
sys/          system       system_e11248ad       system endpoints used for control, policy and debugging
```


```bash
v kv put secret/paylink/api \
    db_user=paylink_app db_password='S3cret!2026' api_key=pk_live_51J
```

Résultat attendu à l'écran :

```
===== Secret Path =====
secret/data/paylink/api

======= Metadata =======
Key                Value
---                -----
created_time       2026-07-07T19:05:19.126661792Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1
```


```bash
v kv get secret/paylink/api
```

```
===== Secret Path =====
secret/data/paylink/api

======= Metadata =======
Key                Value
---                -----
created_time       2026-07-07T19:05:19.126661792Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1

======= Data =======
Key            Value
---            -----
api_key        pk_live_51J
db_password    S3cret!2026
db_user        paylink_app
```

```bash
v kv put secret/paylink/api \
    db_user=paylink_app db_password='Rot4ted!2026' api_key=pk_live_51J
```

```
===== Secret Path =====
secret/data/paylink/api

======= Metadata =======
Key                Value
---                -----
created_time       2026-07-07T19:05:19.320325124Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            2
```

```bash
v kv get -version=1 secret/paylink/api
```

```
======= Metadata =======
Key                Value
---                -----
created_time       2026-07-07T19:05:19.126661792Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1

======= Data =======
Key            Value
---            -----
api_key        pk_live_51J
db_password    S3cret!2026
db_user        paylink_app
```


```bash
v kv patch secret/paylink/api api_key=pk_live_99Z
```

```
===== Secret Path =====
secret/data/paylink/api

======= Metadata =======
Key                Value
---                -----
created_time       2026-07-07T19:05:19.520495063Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            3
```



```bash
v kv get -field=db_password secret/paylink/api
```

```
Rot4ted!2026
```

```bash
v kv get -format=json secret/paylink/api
```

```json
{
  "request_id": "786e2a95-4585-578f-3622-611c335142bf",
  "lease_id": "",
  "lease_duration": 0,
  "renewable": false,
  "data": {
    "data": {
      "api_key": "pk_live_99Z",
      "db_password": "Rot4ted!2026",
      "db_user": "paylink_app"
    },
    "metadata": {
      "created_time": "2026-07-07T19:05:19.520495063Z",
      "custom_metadata": null,
      "deletion_time": "",
      "destroyed": false,
      "version": 3
    }
  },
  "warnings": null,
  "mount_type": "kv"
}
```



```bash
v kv metadata get secret/paylink/api
```

```
====== Metadata Path ======
secret/metadata/paylink/api

========== Metadata ==========
Key                     Value
---                     -----
cas_required            false
created_time            2026-07-07T19:05:19.126661792Z
current_version         3
custom_metadata         <nil>
delete_version_after    0s
max_versions            0
oldest_version          0
updated_time            2026-07-07T19:05:19.520495063Z

====== Version 1 ======
Key              Value
---              -----
created_time     2026-07-07T19:05:19.126661792Z
deletion_time    n/a
destroyed        false

====== Version 2 ======
Key              Value
---              -----
created_time     2026-07-07T19:05:19.320325124Z
deletion_time    n/a
destroyed        false

====== Version 3 ======
Key              Value
---              -----
created_time     2026-07-07T19:05:19.520495063Z
deletion_time    n/a
destroyed        false
```

```bash
v kv delete secret/paylink/api
```

```
Success! Data deleted (if it existed) at: secret/data/paylink/api
```

```bash
v kv get secret/paylink/api
```

```
===== Secret Path =====
secret/data/paylink/api

======= Metadata =======
Key                Value
---                -----
created_time       2026-07-07T19:05:19.520495063Z
custom_metadata    <nil>
deletion_time      2026-07-07T19:05:19.90114358Z
destroyed          false
version            3
```


```bash
v kv undelete -versions=3 secret/paylink/api
```

```
Success! Data written to: secret/undelete/paylink/api
```

```bash
v kv destroy -versions=1 secret/paylink/api
```

```
Success! Data written to: secret/destroy/paylink/api
```

