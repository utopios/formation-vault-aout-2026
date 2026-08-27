



```bash

curl -s http://127.0.0.1:8200/v1/sys/health | jq
```

Résultat attendu à l'écran :

```json
{
    "initialized": true,
    "sealed": false,
    "standby": false,
    "performance_standby": false,
    "replication_performance_mode": "disabled",
    "replication_dr_mode": "disabled",
    "server_time_utc": 1783451194,
    "version": "1.20.4",
    "enterprise": false,
    "cluster_name": "vault-cluster-14428c25",
    "cluster_id": "ef1f42be-1d8d-71a0-bc9d-4b09ec625843",
    "echo_duration_ms": 0,
    "clock_skew_ms": 0,
    "replication_primary_canary_age_ms": 0
}
```



```bash

curl -s -H "X-Vault-Token: root-token-formation" \
  http://127.0.0.1:8200/v1/secret/data/paylink/api | jq
```

```json
{
    "request_id": "a1806ca7-fd40-7ef3-8e94-a9cfae870139",
    "lease_id": "",
    "renewable": false,
    "lease_duration": 0,
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
    "wrap_info": null,
    "warnings": null,
    "auth": null,
    "mount_type": "kv"
}
```




```bash

curl -s -H "X-Vault-Token: root-token-formation" \
  -X POST \
  -d '{"data":{"url":"https://hooks.paylink.io/pay","hmac_secret":"whk_7f3a"}}' \
  http://127.0.0.1:8200/v1/secret/data/paylink/webhook | jq
```

```json
{
    "request_id": "14da8460-f63f-54b1-c787-972b5348518f",
    "lease_id": "",
    "renewable": false,
    "lease_duration": 0,
    "data": {
        "created_time": "2026-07-07T19:06:34.52339549Z",
        "custom_metadata": null,
        "deletion_time": "",
        "destroyed": false,
        "version": 1
    },
    "wrap_info": null,
    "warnings": null,
    "auth": null,
    "mount_type": "kv"
}
```


```bash

curl -s -H "X-Vault-Token: root-token-formation" \
  "http://127.0.0.1:8200/v1/secret/data/paylink/api?version=2" | jq .data
```

```json
{
  "data": {
    "api_key": "pk_live_51J",
    "db_password": "Rot4ted!2026",
    "db_user": "paylink_app"
  },
  "metadata": {
    "created_time": "2026-07-07T19:05:19.320325124Z",
    "custom_metadata": null,
    "deletion_time": "",
    "destroyed": false,
    "version": 2
  }
}
```


```bash

curl -s -o /dev/null -w '%{http_code}\n' \
  -H "X-Vault-Token: mauvais-token" \
  http://127.0.0.1:8200/v1/secret/data/paylink/api
curl -s -H "X-Vault-Token: mauvais-token" \
  http://127.0.0.1:8200/v1/secret/data/paylink/api
```

```
403
{"errors":["2 errors occurred:\n\t* permission denied\n\t* invalid token\n\n"]}
```
