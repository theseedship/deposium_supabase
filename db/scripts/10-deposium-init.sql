-- ============================================================================
-- Deposium: Base Schema & Permissions
-- Adapted from deposium-local init-scripts/01-init.sql + 02-supabase-roles-schemas.sql
--
-- NOTE: supabase/postgres:15.8.1.085 already provides:
--   Roles: postgres, anon, authenticated, service_role, authenticator,
--          pgbouncer, supabase_admin, supabase_auth_admin, supabase_storage_admin
--   Schemas: public, auth, extensions, storage
--   Extensions: pgvector, pg_cron, pg_graphql, vault, http, pg_net, etc.
--
-- This script adds what's specific to Deposium.
-- ============================================================================

-- Enable additional extensions if needed
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- ============================================================================
-- 1. Create app schema (Deposium-specific)
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS app;
COMMENT ON SCHEMA app IS 'Schema for Deposium application tables (API keys, spaces, code runs)';

-- ============================================================================
-- 2. Ensure auth enum types exist (idempotent)
-- GoTrue auto-migrates these, but pre-creating avoids race conditions
-- ============================================================================

DO $$ BEGIN
  CREATE TYPE auth.factor_type AS ENUM ('totp', 'webauthn');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE auth.factor_status AS ENUM ('unverified', 'verified');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE auth.aal_level AS ENUM ('aal1', 'aal2', 'aal3');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE auth.code_challenge_method AS ENUM ('S256', 'plain');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================================
-- 3. Schema permissions
-- ============================================================================

-- Grant usage on all schemas
GRANT USAGE ON SCHEMA public, app, auth, extensions TO anon, authenticated, service_role;

-- service_role gets full access
GRANT ALL ON SCHEMA app TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT ALL ON SEQUENCES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT ALL ON FUNCTIONS TO service_role;

-- authenticated gets CRUD on app schema
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT USAGE ON SEQUENCES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT EXECUTE ON FUNCTIONS TO authenticated, service_role;

-- public schema defaults
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO anon, authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;

-- ============================================================================
-- 4. Set database search path
-- ============================================================================

\set dbname `echo "$POSTGRES_DB"`
ALTER DATABASE :"dbname" SET search_path TO public, auth, extensions, app;
