v secrets enable database 


v write database/config/paylink-pg \
    plugin_name=postgresql-database-plugin \
    connection_url="postgresql://{{username}}:{{password}}@postgres:5432/paylink?sslmode=disable" \
    allowed_roles="paylink-readonly,paylink-dml, paylink-court" \
    username="postgres" \
    password="rootpg"

v write database/roles/paylink-court \
    db_name=paylink-pg \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl=2m max_ttl=4m

v read database/creds/paylink-court

v lease lookup database/creds/paylink-court/<identifiant>

docker exec postgres psql -U postgres -d paylink \
  -c "SELECT usename, valuntil FROM pg_user WHERE usename LIKE 'v-token-%';"


v lease renew database/creds/paylink-court/<identifiant>

v lease lookup database/creds/paylink-court/<identifiant>

docker exec postgres psql -U postgres -d paylink \
  -c "SELECT usename FROM pg_user WHERE usename LIKE 'v-token-%';"