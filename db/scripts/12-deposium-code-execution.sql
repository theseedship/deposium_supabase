-- ============================================================================
-- Sync Local Database with Railway Schema
-- Code Execution Tables + Shared Spaces
-- Date: 2025-11-10
-- ============================================================================

-- ============================================================================
-- 1. Helper Function for Updated Timestamps
-- ============================================================================

CREATE OR REPLACE FUNCTION app.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 2. Shared Spaces Table (Railway Schema)
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.shared_spaces (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT NULL,
  is_active BOOLEAN NULL DEFAULT true,
  owner_id UUID NOT NULL,
  created_at TIMESTAMPTZ NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NULL DEFAULT NOW(),
  settings JSONB NULL DEFAULT '{"require_approval": true, "default_member_role": "viewer", "allow_member_invites": false}'::jsonb,
  CONSTRAINT shared_spaces_pkey PRIMARY KEY (id),
  CONSTRAINT shared_spaces_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users (id)
);

-- Indexes for shared_spaces
CREATE INDEX IF NOT EXISTS idx_shared_spaces_owner ON app.shared_spaces USING btree (owner_id);
CREATE INDEX IF NOT EXISTS idx_shared_spaces_active ON app.shared_spaces USING btree (is_active);

-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_shared_spaces_updated_at ON app.shared_spaces;
CREATE TRIGGER update_shared_spaces_updated_at
  BEFORE UPDATE ON app.shared_spaces
  FOR EACH ROW
  EXECUTE FUNCTION app.update_updated_at_column();

-- ============================================================================
-- 3. Space Members Helper Function
-- ============================================================================

CREATE OR REPLACE FUNCTION app.add_creator_as_space_admin()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO app.space_members (space_id, user_id, role, status, joined_at)
  VALUES (NEW.id, NEW.owner_id, 'admin', 'active', NOW())
  ON CONFLICT (space_id, user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to add creator as admin
DROP TRIGGER IF EXISTS add_creator_as_admin ON app.shared_spaces;
CREATE TRIGGER add_creator_as_admin
  AFTER INSERT ON app.shared_spaces
  FOR EACH ROW
  EXECUTE FUNCTION app.add_creator_as_space_admin();

-- ============================================================================
-- 4. Space Members Table (Railway Schema)
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.space_members (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  space_id UUID NOT NULL,
  user_id UUID NOT NULL,
  role TEXT NULL DEFAULT 'viewer'::text,
  invited_by UUID NULL,
  joined_at TIMESTAMPTZ NULL DEFAULT NOW(),
  status TEXT NOT NULL DEFAULT 'active'::text,
  created_at TIMESTAMPTZ NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NULL DEFAULT NOW(),
  CONSTRAINT space_members_pkey PRIMARY KEY (id),
  CONSTRAINT unique_space_user_membership UNIQUE (space_id, user_id),
  CONSTRAINT space_members_space_id_user_id_key UNIQUE (space_id, user_id),
  CONSTRAINT space_members_space_id_fkey FOREIGN KEY (space_id) REFERENCES app.shared_spaces (id) ON DELETE CASCADE,
  CONSTRAINT space_members_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES auth.users (id),
  CONSTRAINT space_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE,
  CONSTRAINT space_members_status_check CHECK (
    status = ANY (ARRAY['pending'::text, 'active'::text, 'suspended'::text])
  ),
  CONSTRAINT space_members_role_check CHECK (
    role = ANY (ARRAY['viewer'::text, 'editor'::text, 'admin'::text])
  )
);

-- Indexes for space_members
CREATE INDEX IF NOT EXISTS idx_space_members_user_space ON app.space_members USING btree (user_id, space_id);
CREATE INDEX IF NOT EXISTS idx_space_members_space_role ON app.space_members USING btree (space_id, role);

-- ============================================================================
-- 5. Insert System Space
-- ============================================================================

-- Use a deterministic system UUID as owner (no auth.users exist during init)
INSERT INTO app.shared_spaces (id, name, description, is_active, owner_id, settings)
SELECT
  '00000000-0000-0000-0000-000000000001'::uuid,
  'System Orchestration',
  'Internal system space for automated code execution',
  true,
  '00000000-0000-0000-0000-000000000000'::uuid, -- System owner placeholder
  '{"is_system_space": true, "require_approval": false, "auto_cleanup": true}'::jsonb
WHERE NOT EXISTS (
  SELECT 1 FROM app.shared_spaces WHERE id = '00000000-0000-0000-0000-000000000001'
);

-- ============================================================================
-- 6. Code Runs Table (Railway Schema)
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.code_runs (
  run_id UUID NOT NULL DEFAULT gen_random_uuid(),
  tenant_id TEXT NOT NULL,
  space_id UUID NOT NULL,
  user_id UUID NULL,
  code TEXT NOT NULL,
  language TEXT NOT NULL,
  status TEXT NOT NULL,
  timeout INTEGER NOT NULL DEFAULT 300000,
  packages TEXT[] NULL DEFAULT ARRAY[]::text[],
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at TIMESTAMPTZ NULL,
  completed_at TIMESTAMPTZ NULL,
  result JSONB NULL,
  error_message TEXT NULL,
  metadata JSONB NULL DEFAULT '{}'::jsonb,
  CONSTRAINT code_runs_run_id_key PRIMARY KEY (run_id),
  CONSTRAINT code_runs_space_id_fkey FOREIGN KEY (space_id) REFERENCES app.shared_spaces (id) ON DELETE CASCADE,
  CONSTRAINT code_runs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE SET NULL,
  CONSTRAINT code_runs_language_check CHECK (
    language = ANY (ARRAY['python'::text, 'javascript'::text, 'typescript'::text])
  ),
  CONSTRAINT code_runs_status_check CHECK (
    status = ANY (ARRAY['pending'::text, 'running'::text, 'completed'::text, 'failed'::text, 'cancelled'::text])
  )
);

-- Indexes for code_runs (Railway Schema)
CREATE INDEX IF NOT EXISTS idx_code_runs_tenant_space ON app.code_runs USING btree (tenant_id, space_id);
CREATE INDEX IF NOT EXISTS idx_code_runs_space ON app.code_runs USING btree (space_id);
CREATE INDEX IF NOT EXISTS idx_code_runs_user ON app.code_runs USING btree (user_id) WHERE (user_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_code_runs_status ON app.code_runs USING btree (status);
CREATE INDEX IF NOT EXISTS idx_code_runs_created_at ON app.code_runs USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_code_runs_space_status ON app.code_runs USING btree (space_id, status);

-- ============================================================================
-- 7. Run Logs Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.run_logs (
  id SERIAL PRIMARY KEY,
  run_id UUID NOT NULL REFERENCES app.code_runs(run_id) ON DELETE CASCADE,
  level TEXT NOT NULL CHECK (level IN ('info', 'warn', 'error', 'debug')),
  message TEXT NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for run_logs
CREATE INDEX IF NOT EXISTS idx_run_logs_run_id ON app.run_logs USING btree (run_id, timestamp ASC);
CREATE INDEX IF NOT EXISTS idx_run_logs_timestamp ON app.run_logs USING btree (timestamp DESC);

-- ============================================================================
-- 8. Run Artifacts Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.run_artifacts (
  id SERIAL PRIMARY KEY,
  run_id UUID NOT NULL REFERENCES app.code_runs(run_id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  minio_path TEXT NOT NULL,
  size BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(run_id, name)
);

-- Indexes for run_artifacts
CREATE INDEX IF NOT EXISTS idx_run_artifacts_run_id ON app.run_artifacts USING btree (run_id);
CREATE INDEX IF NOT EXISTS idx_run_artifacts_created_at ON app.run_artifacts USING btree (created_at DESC);

-- ============================================================================
-- 9. Row Level Security (RLS)
-- ============================================================================

ALTER TABLE app.shared_spaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.space_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.code_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.run_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.run_artifacts ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "service_role_all_spaces" ON app.shared_spaces;
DROP POLICY IF EXISTS "service_role_all_members" ON app.space_members;
DROP POLICY IF EXISTS "service_role_all_runs" ON app.code_runs;
DROP POLICY IF EXISTS "service_role_all_logs" ON app.run_logs;
DROP POLICY IF EXISTS "service_role_all_artifacts" ON app.run_artifacts;

-- Service role has full access (for tests and backend)
CREATE POLICY "service_role_all_spaces" ON app.shared_spaces FOR ALL USING (true);
CREATE POLICY "service_role_all_members" ON app.space_members FOR ALL USING (true);
CREATE POLICY "service_role_all_runs" ON app.code_runs FOR ALL USING (true);
CREATE POLICY "service_role_all_logs" ON app.run_logs FOR ALL USING (true);
CREATE POLICY "service_role_all_artifacts" ON app.run_artifacts FOR ALL USING (true);

-- ============================================================================
-- 10. Grant Permissions
-- ============================================================================

GRANT USAGE ON SCHEMA app TO authenticated, service_role;

-- Full access for service_role
GRANT ALL ON app.shared_spaces TO service_role;
GRANT ALL ON app.space_members TO service_role;
GRANT ALL ON app.code_runs TO service_role;
GRANT ALL ON app.run_logs TO service_role;
GRANT ALL ON app.run_artifacts TO service_role;

-- Limited access for authenticated users
GRANT SELECT, INSERT, UPDATE, DELETE ON app.shared_spaces TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON app.space_members TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON app.code_runs TO authenticated;
GRANT SELECT, INSERT ON app.run_logs TO authenticated;
GRANT SELECT ON app.run_artifacts TO authenticated;

-- Sequences
GRANT USAGE, SELECT ON SEQUENCE app.run_logs_id_seq TO authenticated, service_role;
GRANT USAGE, SELECT ON SEQUENCE app.run_artifacts_id_seq TO authenticated, service_role;

-- ============================================================================
-- 11. Verification
-- ============================================================================

DO $$
DECLARE
  table_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO table_count
  FROM information_schema.tables
  WHERE table_schema = 'app'
    AND table_name IN ('shared_spaces', 'space_members', 'code_runs', 'run_logs', 'run_artifacts');

  IF table_count = 5 THEN
    RAISE NOTICE '✅ All 5 tables created successfully';
    RAISE NOTICE '📊 Tables: shared_spaces, space_members, code_runs, run_logs, run_artifacts';
    RAISE NOTICE '🤖 System space: 00000000-0000-0000-0000-000000000001';
    RAISE NOTICE '🔒 RLS enabled with service_role bypass';
  ELSE
    RAISE WARNING '⚠️  Expected 5 tables but found %', table_count;
  END IF;
END $$;
