#!/bin/bash
# ============================================================================
# Setup Railway environment variables for v2_deposium
# Run from the deposium_supabase directory
# ============================================================================
set -euo pipefail

PROJECT="ea14d897-60c1-4d75-a9f9-25c62653666d"

# --- Shared secrets (reused from old staging for migration compatibility) ---
JWT_SECRET="EzDHUxNo5RQZJxEK4vzV3KlvceiTz51pjTRSGP9d"
ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewogICJyb2xlIjogImFub24iLAogICJpc3MiOiAic3VwYWJhc2UiLAogICJpYXQiOiAxNzQ0NzU0NDAwLAogICJleHAiOiAxOTAyNTIwODAwCn0.f7PtLBL_HslX_5tMFMLAWEV1Ii5XPKc3CRyOKjVQOPc"
SERVICE_ROLE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ewogICJyb2xlIjogInNlcnZpY2Vfcm9sZSIsCiAgImlzcyI6ICJzdXBhYmFzZSIsCiAgImlhdCI6IDE3NDQ3NTQ0MDAsCiAgImV4cCI6IDE5MDI1MjA4MDAKfQ.aJ42LbD5ahuUShBi_WSuMXy8k-IEr_ZcrdPSUnDlLwA"

# --- New DB passwords ---
DB_SUPERUSER_PASSWORD="Fh78pm1Rkyr1u45TxTtLNqT1BBjyfw_JqrWYm6wuK7k"
DB_AUTHENTICATOR_PASSWORD="T9lJvaiVRvwkMCpKq7iZLv3Vs-xGSrhUMjvfRNGzEQY"
DB_PGBOUNCER_PASSWORD="Y0BXWDqV7TOSUsg-y0qiOpPvIi9kh0nefkR2xuPL7kQ"
DB_AUTH_PASSWORD="CJIfEe9fxWikOl4CoR1Nxvqe267QTiW7MurCS9FcjJ4"
DB_WEBHOOKS_PASSWORD="J9rt_GrbqoMpe2PjYSS2bYAUwjNWaqLgLMFZ1PHSNg0"
DB_STORAGE_PASSWORD="ywX24-2ingtBBrKkHbakiEztGl1hPwnDEx5YAzNHhw0"

# --- Other secrets ---
DASHBOARD_USERNAME="deposium"
DASHBOARD_PASSWORD="Gf68C0IWV7fp2_Xiz1AhdeuzywRgG7mcj9CEQpOuKDM"
S3_ID="supa-storage"
S3_SECRET="ycoRZ6BkXeftGtOE4H6z1kvxuGlFzDnNQ36B1b0n6S4"
PG_META_CRYPTO_KEY="VTL_wLtiCjLksCH5SaXeDGB025GhNFz-Ex4af2YDA04"
LOGFLARE_PUBLIC_TOKEN="R4p2Ucn0ndvSK_NmWsNTTaWSu7swF4CO4iIa6xVh0cM"
LOGFLARE_PRIVATE_TOKEN="t6qIzFnU7kuKoSa3Ay9MYWAP4AOSySQPp9YOq_VyHBk"
REALTIME_DB_ENC_KEY="supabaserealtime"
REALTIME_SECRET_KEY_BASE="fJBMmr6uIgQNXfy-QzJdAjTq02bSGCnx3zeTNNUCM5M"

# --- Railway private networking ---
DB_HOST="db.railway.internal"
DB_PORT="5432"
DB_NAME="postgres"
PGBOUNCER_HOST="pgbouncer.railway.internal"

set_vars() {
  local service="$1"
  shift
  echo "=== Setting vars for $service ==="
  # Build --set flags
  local args=()
  while [ $# -gt 0 ]; do
    local key="${1%%=*}"
    args+=("--set" "$1")
    echo "  $key=****"
    shift
  done
  railway variables -s "$service" --skip-deploys "${args[@]}"
  echo "  -> Done"
  echo ""
}

# ============================================================================
# 1. db (PostgreSQL)
# ============================================================================
set_vars "db" \
  "POSTGRES_PASSWORD=$DB_SUPERUSER_PASSWORD" \
  "POSTGRES_USER=supabase_admin" \
  "POSTGRES_DB=$DB_NAME" \
  "PGPASSWORD=$DB_SUPERUSER_PASSWORD" \
  "PGDATABASE=$DB_NAME" \
  "PGDATA=/var/lib/postgresql/data/pgdata" \
  "PGPORT=$DB_PORT" \
  "POSTGRES_PORT=$DB_PORT" \
  "POSTGRES_HOST=/var/run/postgresql" \
  "LISTEN_ADDRESSES=*" \
  "JWT_SECRET=$JWT_SECRET" \
  "JWT_EXP=3600" \
  "DB_AUTHENTICATOR_PASSWORD=$DB_AUTHENTICATOR_PASSWORD" \
  "DB_PGBOUNCER_PASSWORD=$DB_PGBOUNCER_PASSWORD" \
  "DB_AUTH_PASSWORD=$DB_AUTH_PASSWORD" \
  "DB_WEBHOOKS_PASSWORD=$DB_WEBHOOKS_PASSWORD" \
  "DB_STORAGE_PASSWORD=$DB_STORAGE_PASSWORD" \
  "PORT=$DB_PORT"

# ============================================================================
# 2. auth (GoTrue)
# ============================================================================
set_vars "auth" \
  "GOTRUE_API_HOST=::" \
  "GOTRUE_API_PORT=9999" \
  "GOTRUE_DB_DRIVER=postgres" \
  "GOTRUE_DB_DATABASE_URL=postgres://supabase_auth_admin:${DB_AUTH_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}" \
  "API_EXTERNAL_URL=http://kong.railway.internal:8000" \
  "GOTRUE_SITE_URL=https://solid.deposium.vip" \
  "GOTRUE_JWT_ADMIN_ROLES=service_role" \
  "GOTRUE_JWT_AUD=authenticated" \
  "GOTRUE_JWT_DEFAULT_GROUP_NAME=authenticated" \
  "GOTRUE_JWT_EXP=3600" \
  "GOTRUE_JWT_SECRET=$JWT_SECRET" \
  "GOTRUE_MAILER_AUTOCONFIRM=true" \
  "GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_REAUTHENTICATION=false" \
  "GOTRUE_MAILER_URLPATHS_INVITE=/auth/v1/verify" \
  "GOTRUE_MAILER_URLPATHS_CONFIRMATION=/auth/v1/verify" \
  "GOTRUE_MAILER_URLPATHS_RECOVERY=/auth/v1/verify" \
  "GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE=/auth/v1/verify" \
  "GOTRUE_MAILER_SUBJECTS_REAUTHENTICATION=Your One-Time Passcode" \
  "GOTRUE_MAILER_TEMPLATES_INVITE=http://localhost:8080/invite.html" \
  "GOTRUE_MAILER_TEMPLATES_CONFIRMATION=http://localhost:8080/confirmation.html" \
  "GOTRUE_MAILER_TEMPLATES_RECOVERY=http://localhost:8080/recovery.html" \
  "GOTRUE_MAILER_TEMPLATES_MAGIC_LINK=http://localhost:8080/magiclink.html" \
  "GOTRUE_MAILER_TEMPLATES_EMAIL_CHANGE=http://localhost:8080/emailchange.html" \
  "PORT=9999"

# ============================================================================
# 3. rest (PostgREST) — routed through pgbouncer for connection pooling
# ============================================================================
set_vars "rest" \
  "PGRST_SERVER_HOST=::" \
  "PGRST_SERVER_PORT=3000" \
  "PGRST_ADMIN_SERVER_HOST=::" \
  "PGRST_ADMIN_SERVER_PORT=3001" \
  "PGRST_DB_URI=postgres://authenticator:${DB_AUTHENTICATOR_PASSWORD}@${PGBOUNCER_HOST}:${DB_PORT}/${DB_NAME}" \
  "PGRST_DB_SCHEMAS=public,storage,graphql_public" \
  "PGRST_DB_ANON_ROLE=anon" \
  "PGRST_JWT_SECRET=$JWT_SECRET" \
  "PGRST_DB_USE_LEGACY_GUCS=false" \
  "PGRST_APP_SETTINGS_JWT_SECRET=$JWT_SECRET" \
  "PGRST_APP_SETTINGS_JWT_EXP=3600" \
  "PORT=3000"

# ============================================================================
# 4. realtime
# ============================================================================
set_vars "realtime" \
  "PORT=4000" \
  "ERL_AFLAGS=-proto_dist inet6_tcp" \
  "DB_USER=supabase_admin" \
  "DB_PASSWORD=$DB_SUPERUSER_PASSWORD" \
  "DB_HOST=$DB_HOST" \
  "DB_PORT=$DB_PORT" \
  "DB_NAME=$DB_NAME" \
  "DB_AFTER_CONNECT_QUERY=SET search_path TO _realtime" \
  "DB_ENC_KEY=$REALTIME_DB_ENC_KEY" \
  "SECRET_KEY_BASE=$REALTIME_SECRET_KEY_BASE" \
  "API_JWT_SECRET=$JWT_SECRET" \
  "DNS_NODES=''" \
  "RLIMIT_NOFILE=10000" \
  "APP_NAME=realtime" \
  "SELF_HOST_TENANT_NAME=default-tenant" \
  "SEED_SELF_HOST=true" \
  "RUN_JANITOR=true" \
  "DISABLE_HEALTHCHECK_LOGGING=true"

# ============================================================================
# 5. kong (API Gateway)
# ============================================================================
set_vars "kong" \
  "PORT=8000" \
  "KONG_PROXY_LISTEN=[::]:8000 reuseport backlog=16384, 0.0.0.0:8000 reuseport backlog=16384" \
  "KONG_STATUS_LISTEN=[::]:8100, 0.0.0.0:8100" \
  "KONG_DNS_ORDER=LAST,A,CNAME,AAAA" \
  "KONG_DATABASE=off" \
  "KONG_DECLARATIVE_CONFIG=/home/kong/kong.yml" \
  "KONG_PLUGINS=request-transformer,cors,key-auth,acl,basic-auth,request-termination,ip-restriction" \
  "KONG_NGINX_PROXY_PROXY_BUFFER_SIZE=160k" \
  "KONG_NGINX_PROXY_PROXY_BUFFERS=64 160k" \
  "KONG_NGINX_WORKER_PROCESSES=2" \
  "SUPABASE_ANON_KEY=$ANON_KEY" \
  "SUPABASE_SERVICE_KEY=$SERVICE_ROLE_KEY" \
  "DASHBOARD_USERNAME=$DASHBOARD_USERNAME" \
  "DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD" \
  "AUTH_HOST=auth.railway.internal" \
  "AUTH_PORT=9999" \
  "REST_HOST=rest.railway.internal" \
  "REST_PORT=3000" \
  "META_HOST=meta.railway.internal" \
  "META_PORT=8080" \
  "STUDIO_HOST=studio.railway.internal" \
  "STUDIO_PORT=3000" \
  "FUNCTIONS_HOST=functions.railway.internal" \
  "FUNCTIONS_PORT=9000" \
  "REALTIME_HOST=realtime.railway.internal" \
  "REALTIME_PORT=4000" \
  "STORAGE_HOST=storage.railway.internal" \
  "STORAGE_PORT=5000" \
  "ANALYTICS_HOST=analytics.railway.internal" \
  "ANALYTICS_PORT=4000" \
  "DEPOSIUM_EDGE_HOST=deposium_edge_runtime.railway.internal" \
  "DEPOSIUM_EDGE_PORT=9000" \
  "DEPOSIUM_MCPS_HOST=deposium_MCPs.railway.internal" \
  "DEPOSIUM_MCPS_PORT=4000" \
  "DEPOSIUM_N8N_HOST=n8n.railway.internal" \
  "DEPOSIUM_N8N_PORT=5678"

# ============================================================================
# 6. studio
# ============================================================================
set_vars "studio" \
  "PORT=3000" \
  "HOSTNAME=::" \
  "SUPABASE_URL=http://kong.railway.internal:8000" \
  "SUPABASE_PUBLIC_URL=https://supa.deposium.vip" \
  "STUDIO_PG_META_URL=http://meta.railway.internal:8080" \
  "SUPABASE_ANON_KEY=$ANON_KEY" \
  "SUPABASE_SERVICE_KEY=$SERVICE_ROLE_KEY" \
  "AUTH_JWT_SECRET=$JWT_SECRET" \
  "POSTGRES_HOST=$DB_HOST" \
  "POSTGRES_PORT=$DB_PORT" \
  "POSTGRES_DB=$DB_NAME" \
  "POSTGRES_PASSWORD=$DB_SUPERUSER_PASSWORD" \
  "PG_META_CRYPTO_KEY=$PG_META_CRYPTO_KEY" \
  "DEFAULT_ORGANIZATION_NAME=Deposium" \
  "DEFAULT_PROJECT_NAME=Deposium" \
  "LOGFLARE_PUBLIC_ACCESS_TOKEN=$LOGFLARE_PUBLIC_TOKEN" \
  "LOGFLARE_PRIVATE_ACCESS_TOKEN=$LOGFLARE_PRIVATE_TOKEN" \
  "NEXT_PUBLIC_ENABLE_LOGS=false"

# ============================================================================
# 7. meta (PGMeta)
# ============================================================================
set_vars "meta" \
  "PORT=8080" \
  "PG_META_HOST=::" \
  "PG_META_PORT=8080" \
  "PG_META_DB_USER=supabase_admin" \
  "PG_META_DB_PASSWORD=$DB_SUPERUSER_PASSWORD" \
  "PG_META_DB_HOST=$DB_HOST" \
  "PG_META_DB_PORT=$DB_PORT" \
  "PG_META_DB_NAME=$DB_NAME" \
  "CRYPTO_KEY=$PG_META_CRYPTO_KEY"

# ============================================================================
# 8. pgbouncer
# ============================================================================
set_vars "pgbouncer" \
  "PORT=5432" \
  "LISTEN_ADDR=*" \
  "LISTEN_PORT=5432" \
  "DB_USER=pgbouncer" \
  "DB_PASSWORD=$DB_PGBOUNCER_PASSWORD" \
  "DB_HOST=$DB_HOST" \
  "DB_PORT=$DB_PORT" \
  "AUTH_QUERY=SELECT * FROM pgbouncer.get_auth(\$1)" \
  "AUTH_TYPE=scram-sha-256" \
  "POOL_MODE=transaction" \
  "MAX_CLIENT_CONN=100" \
  "DEFAULT_POOL_SIZE=20"

# ============================================================================
# 9. minio
# ============================================================================
set_vars "minio" \
  "PORT=9000" \
  "MINIO_ROOT_USER=$S3_ID" \
  "MINIO_ROOT_PASSWORD=$S3_SECRET" \
  "MINIO_CONCURRENCY_MAX=50" \
  "MINIO_COMPRESSION=on" \
  "MINIO_API_REQUESTS_MAX=200" \
  "STORAGE_S3_BUCKET=deposium"

# ============================================================================
# (REMOVED) analytics (Logflare) — incompatible Railway: useless without Vector, 200MB RAM wasted
# (REMOVED) vector — incompatible Railway: needs /var/run/docker.sock
# ============================================================================

# ============================================================================
# 10. storage (Storage API) — uses pgbouncer via DATABASE_POOL_URL
# ============================================================================
set_vars "storage" \
  "PORT=5000" \
  "SERVER_HOST=::" \
  "SERVER_PORT=5000" \
  "SERVER_ADMIN_PORT=5001" \
  "ANON_KEY=$ANON_KEY" \
  "SERVICE_KEY=$SERVICE_ROLE_KEY" \
  "AUTH_JWT_SECRET=$JWT_SECRET" \
  "AUTH_JWT_ALGORITHM=HS256" \
  "DATABASE_URL=postgres://supabase_storage_admin:${DB_STORAGE_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}" \
  "DATABASE_POOL_URL=postgres://supabase_storage_admin:${DB_STORAGE_PASSWORD}@${PGBOUNCER_HOST}:${DB_PORT}/${DB_NAME}" \
  "DATABASE_CONNECTION_TIMEOUT=3000" \
  "DB_INSTALL_ROLES=false" \
  "DB_ALLOW_MIGRATION_REFRESH=false" \
  "DB_ANON_ROLE=anon" \
  "DB_SERVICE_ROLE=service_role" \
  "DB_AUTHENTICATED_ROLE=authenticated" \
  "DB_SUPER_USER=postgres" \
  "STORAGE_BACKEND=s3" \
  "STORAGE_S3_ENDPOINT=http://minio.railway.internal:9000" \
  "STORAGE_S3_FORCE_PATH_STYLE=true" \
  "STORAGE_S3_MAX_SOCKETS=200" \
  "STORAGE_S3_REGION=default-region" \
  "STORAGE_S3_BUCKET=deposium" \
  "TENANT_ID=default-tenant" \
  "AWS_ACCESS_KEY_ID=$S3_ID" \
  "AWS_SECRET_ACCESS_KEY=$S3_SECRET" \
  "FILE_SIZE_LIMIT=52428800" \
  "UPLOAD_FILE_SIZE_LIMIT=524288000" \
  "IMAGE_TRANSFORMATION_ENABLED=true" \
  "IMGPROXY_URL=http://imgproxy.railway.internal:5001" \
  "POSTGREST_URL=http://rest.railway.internal:3000" \
  "PGRST_JWT_SECRET=$JWT_SECRET"

# ============================================================================
# 11. imgproxy
# ============================================================================
set_vars "imgproxy" \
  "PORT=5001" \
  "IMGPROXY_BIND=[::]:5001" \
  "IMGPROXY_USE_S3=true" \
  "IMGPROXY_S3_ENDPOINT=http://minio.railway.internal:9000" \
  "AWS_ACCESS_KEY_ID=$S3_ID" \
  "AWS_SECRET_ACCESS_KEY=$S3_SECRET" \
  "IMGPROXY_USE_ETAG=true" \
  "IMGPROXY_AUTO_WEBP=true" \
  "IMGPROXY_JPEG_PROGRESSIVE=true" \
  "IMGPROXY_IGNORE_SSL_VERIFICATION=true"

echo ""
echo "=== DONE ==="
echo "All variables set for v2_deposium."
echo ""
echo "Next steps:"
echo "1. Add volumes: db → /var/lib/postgresql/data, minio → /data"
echo "2. Redeploy db first, wait for SUCCESS"
echo "3. Redeploy auth, rest, realtime, pgbouncer, minio"
echo "4. Redeploy kong, studio, meta"
echo "5. Redeploy storage, imgproxy"
echo ""
echo "PgBouncer routing:"
echo "  - rest (PostgREST) → pgbouncer.railway.internal (pooled)"
echo "  - storage           → pgbouncer via DATABASE_POOL_URL (pooled)"
echo "  - auth, realtime    → db.railway.internal (direct — prepared stmts / CDC)"
echo "  - meta              → db.railway.internal (direct — admin catalog queries)"
