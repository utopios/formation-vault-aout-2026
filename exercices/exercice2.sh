v write auth/approle/role/meditrack-api \
    token_policies=meditrack-read \
    token_ttl=10m token_max_ttl=30m \
    secret_id_ttl=30m secret_id_num_uses=3

ROLE_ID=$(v read -field=role_id auth/approle/role/meditrack-api/role-id)

SECRET_ID=$(v write -f -field=secret_id auth/approle/role/meditrack-api/secret-id)


## Login 1

v write auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID"

## Login 2

MT_TOKEN=$(v write -f -field=token \
    auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID" 2>/dev/null \
  || v write -field=token auth/approle/login \
       role_id="$ROLE_ID" secret_id="$SECRET_ID")