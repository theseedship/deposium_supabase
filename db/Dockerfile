FROM supabase/postgres:15.8.1.085

# --- pgonrails Supabase init scripts ---
# NOTE: init-scripts/ run in ASCII sort order. '9' > '1' so 98-xxx sorts AFTER 100-xxx.
# Use 04-/05-/06- prefixes to ensure these run BEFORE Deposium scripts.
COPY ./scripts/realtime.sql /docker-entrypoint-initdb.d/migrations/99-realtime.sql
COPY ./scripts/webhooks.sql /docker-entrypoint-initdb.d/init-scripts/04-webhooks.sql
COPY ./scripts/roles.sql /docker-entrypoint-initdb.d/init-scripts/05-roles.sql
COPY ./scripts/jwt.sql /docker-entrypoint-initdb.d/init-scripts/06-jwt.sql
COPY ./scripts/_supabase.sql /docker-entrypoint-initdb.d/migrations/97-_supabase.sql
COPY ./scripts/logs.sql /docker-entrypoint-initdb.d/migrations/99-logs.sql

# --- Deposium application init scripts ---
# Run after Supabase scripts (prefixed 07+) — only on first init (empty PGDATA)
COPY ./scripts/10-deposium-init.sql /docker-entrypoint-initdb.d/init-scripts/07-deposium-init.sql
COPY ./scripts/11-deposium-api-keys.sql /docker-entrypoint-initdb.d/init-scripts/08-deposium-api-keys.sql
COPY ./scripts/12-deposium-code-execution.sql /docker-entrypoint-initdb.d/init-scripts/09-deposium-code-execution.sql

COPY --chmod=755 wrapper.sh /usr/local/bin/wrapper.sh

ENTRYPOINT ["wrapper.sh"]
CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf", "-c", "log_min_messages=fatal", "--port=5432"]