-- ============================================================================
-- API Key Management System
-- Phase 2.7 - Production-Ready Authentication
--
-- This migration creates a comprehensive API key management system with:
-- - Secure key storage (SHA-256 hashed)
-- - Usage tracking and analytics
-- - Rate limiting state
-- - Row-level security
-- - Audit logging support
-- ============================================================================

-- Create app schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS app;

-- ============================================================================
-- Core API Keys Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.api_keys (
  -- Identity
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key_hash TEXT NOT NULL UNIQUE, -- SHA-256 hash of the full key
  key_prefix TEXT NOT NULL, -- First 12 chars for display (sk_live_xxxx)

  -- Ownership
  tenant_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES auth.users(id),

  -- Metadata
  name TEXT NOT NULL,
  description TEXT,

  -- Permissions & Scopes
  scopes TEXT[] DEFAULT ARRAY['read']::TEXT[],
  allowed_tools TEXT[], -- NULL means all tools allowed
  blocked_tools TEXT[] DEFAULT ARRAY[]::TEXT[],
  allowed_spaces TEXT[], -- NULL means all spaces allowed

  -- Rate Limiting & Quotas
  rate_limit_tier TEXT DEFAULT 'free' CHECK (rate_limit_tier IN ('free', 'pro', 'enterprise', 'custom')),
  requests_per_minute INT DEFAULT 60,
  requests_per_hour INT DEFAULT 1000,
  requests_per_day INT DEFAULT 10000,
  max_concurrent_queries INT DEFAULT 5,
  max_query_duration_ms INT DEFAULT 10000,
  max_rows_per_query INT DEFAULT 1000,

  -- Lifecycle Management
  is_active BOOLEAN DEFAULT true,
  expires_at TIMESTAMPTZ,
  last_used_at TIMESTAMPTZ,
  last_used_ip INET,
  last_used_user_agent TEXT,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  -- Revocation
  revoked_at TIMESTAMPTZ,
  revoked_by UUID REFERENCES auth.users(id),
  revoked_reason TEXT,

  -- Constraints
  CONSTRAINT valid_scopes CHECK (
    scopes <@ ARRAY['read', 'write', 'delete', 'admin', 'search', 'analyze', 'export', 'execute', 'execute:network']::TEXT[]
  ),
  CONSTRAINT name_not_empty CHECK (char_length(name) > 0),
  CONSTRAINT valid_expiry CHECK (expires_at IS NULL OR expires_at > created_at)
);

-- ============================================================================
-- Usage Tracking Table (Partitioned by Month)
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.api_key_usage (
  -- Identity
  id BIGSERIAL,
  api_key_id UUID NOT NULL REFERENCES app.api_keys(id) ON DELETE CASCADE,
  tenant_id UUID NOT NULL,

  -- Request Details
  endpoint TEXT NOT NULL,
  method TEXT NOT NULL CHECK (method IN ('GET', 'POST', 'PUT', 'DELETE', 'PATCH')),
  tool_name TEXT,
  tool_params JSONB,

  -- Response Details
  status_code INT NOT NULL,
  error_message TEXT,

  -- Performance Metrics
  request_size_bytes INT,
  response_size_bytes INT,
  latency_ms INT,
  database_time_ms INT,

  -- Context
  ip_address INET,
  user_agent TEXT,
  referer TEXT,

  -- Timestamp
  created_at TIMESTAMPTZ DEFAULT NOW(),

  -- Partitioning
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- Create partitions for the next 12 months
DO $$
DECLARE
    start_date DATE := DATE_TRUNC('month', CURRENT_DATE);
    partition_date DATE;
    partition_name TEXT;
BEGIN
    FOR i IN 0..11 LOOP
        partition_date := start_date + (i || ' months')::INTERVAL;
        partition_name := 'api_key_usage_' || TO_CHAR(partition_date, 'YYYY_MM');

        EXECUTE format('
            CREATE TABLE IF NOT EXISTS app.%I PARTITION OF app.api_key_usage
            FOR VALUES FROM (%L) TO (%L)',
            partition_name,
            partition_date,
            partition_date + INTERVAL '1 month'
        );
    END LOOP;
END $$;

-- ============================================================================
-- Rate Limiting State Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.api_key_rate_limits (
  -- Identity
  api_key_id UUID NOT NULL REFERENCES app.api_keys(id) ON DELETE CASCADE,

  -- Window Configuration
  window_type TEXT NOT NULL CHECK (window_type IN ('minute', 'hour', 'day')),
  window_start TIMESTAMPTZ NOT NULL,

  -- Counters
  request_count INT DEFAULT 0,
  error_count INT DEFAULT 0,

  -- Constraints
  PRIMARY KEY (api_key_id, window_type, window_start)
);

-- ============================================================================
-- API Key Audit Log
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.api_key_audit (
  id BIGSERIAL PRIMARY KEY,
  api_key_id UUID NOT NULL REFERENCES app.api_keys(id) ON DELETE CASCADE,
  tenant_id UUID NOT NULL,

  -- Event Details
  event_type TEXT NOT NULL CHECK (event_type IN (
    'created', 'activated', 'deactivated', 'revoked',
    'rotated', 'updated', 'expired', 'deleted'
  )),
  event_data JSONB,

  -- Actor
  performed_by UUID REFERENCES auth.users(id),
  ip_address INET,
  user_agent TEXT,

  -- Timestamp
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- Indexes for Performance
-- ============================================================================

-- API Keys indexes
CREATE INDEX IF NOT EXISTS idx_api_keys_tenant ON app.api_keys(tenant_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_hash ON app.api_keys(key_hash);
CREATE INDEX IF NOT EXISTS idx_api_keys_active ON app.api_keys(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_api_keys_expires ON app.api_keys(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_api_keys_last_used ON app.api_keys(last_used_at);
CREATE INDEX IF NOT EXISTS idx_api_keys_created ON app.api_keys(created_at);

-- Usage tracking indexes
CREATE INDEX IF NOT EXISTS idx_api_key_usage_key ON app.api_key_usage(api_key_id);
CREATE INDEX IF NOT EXISTS idx_api_key_usage_tenant ON app.api_key_usage(tenant_id);
CREATE INDEX IF NOT EXISTS idx_api_key_usage_created ON app.api_key_usage(created_at);
CREATE INDEX IF NOT EXISTS idx_api_key_usage_endpoint ON app.api_key_usage(endpoint);
CREATE INDEX IF NOT EXISTS idx_api_key_usage_status ON app.api_key_usage(status_code);

-- Rate limits indexes
CREATE INDEX IF NOT EXISTS idx_rate_limits_key_window ON app.api_key_rate_limits(api_key_id, window_type, window_start);
CREATE INDEX IF NOT EXISTS idx_rate_limits_window_start ON app.api_key_rate_limits(window_start);

-- Audit log indexes
CREATE INDEX IF NOT EXISTS idx_api_key_audit_key ON app.api_key_audit(api_key_id);
CREATE INDEX IF NOT EXISTS idx_api_key_audit_tenant ON app.api_key_audit(tenant_id);
CREATE INDEX IF NOT EXISTS idx_api_key_audit_event ON app.api_key_audit(event_type);
CREATE INDEX IF NOT EXISTS idx_api_key_audit_created ON app.api_key_audit(created_at);

-- ============================================================================
-- Row-Level Security (RLS)
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE app.api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.api_key_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.api_key_rate_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.api_key_audit ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DO $$
BEGIN
    -- API Keys policies
    DROP POLICY IF EXISTS "Users can view own API keys" ON app.api_keys;
    DROP POLICY IF EXISTS "Users can create own API keys" ON app.api_keys;
    DROP POLICY IF EXISTS "Users can update own API keys" ON app.api_keys;
    DROP POLICY IF EXISTS "Users can delete own API keys" ON app.api_keys;

    -- Usage tracking policies
    DROP POLICY IF EXISTS "Users can view own usage" ON app.api_key_usage;
    DROP POLICY IF EXISTS "System can insert usage" ON app.api_key_usage;

    -- Rate limits policies
    DROP POLICY IF EXISTS "Users can view own rate limits" ON app.api_key_rate_limits;
    DROP POLICY IF EXISTS "System can manage rate limits" ON app.api_key_rate_limits;

    -- Audit log policies
    DROP POLICY IF EXISTS "Users can view own audit log" ON app.api_key_audit;
    DROP POLICY IF EXISTS "System can insert audit log" ON app.api_key_audit;
END $$;

-- API Keys policies
CREATE POLICY "Users can view own API keys" ON app.api_keys
  FOR SELECT USING (auth.uid() = tenant_id);

CREATE POLICY "Users can create own API keys" ON app.api_keys
  FOR INSERT WITH CHECK (auth.uid() = tenant_id AND auth.uid() = created_by);

CREATE POLICY "Users can update own API keys" ON app.api_keys
  FOR UPDATE USING (auth.uid() = tenant_id);

CREATE POLICY "Users can delete own API keys" ON app.api_keys
  FOR DELETE USING (auth.uid() = tenant_id);

-- Usage tracking policies
CREATE POLICY "Users can view own usage" ON app.api_key_usage
  FOR SELECT USING (tenant_id = auth.uid());

CREATE POLICY "System can insert usage" ON app.api_key_usage
  FOR INSERT WITH CHECK (true); -- Only system/service role can insert

-- Rate limits policies
CREATE POLICY "Users can view own rate limits" ON app.api_key_rate_limits
  FOR SELECT USING (
    api_key_id IN (SELECT id FROM app.api_keys WHERE tenant_id = auth.uid())
  );

CREATE POLICY "System can manage rate limits" ON app.api_key_rate_limits
  FOR ALL USING (true); -- Only system/service role can manage

-- Audit log policies
CREATE POLICY "Users can view own audit log" ON app.api_key_audit
  FOR SELECT USING (tenant_id = auth.uid());

CREATE POLICY "System can insert audit log" ON app.api_key_audit
  FOR INSERT WITH CHECK (true); -- Only system/service role can insert

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Function to validate API key and return details
CREATE OR REPLACE FUNCTION app.validate_api_key(p_key_hash TEXT)
RETURNS TABLE (
  key_id UUID,
  tenant_id UUID,
  scopes TEXT[],
  rate_limit_tier TEXT,
  is_valid BOOLEAN,
  error_message TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    ak.id AS key_id,
    ak.tenant_id,
    ak.scopes,
    ak.rate_limit_tier,
    CASE
      WHEN ak.id IS NULL THEN false
      WHEN NOT ak.is_active THEN false
      WHEN ak.expires_at IS NOT NULL AND ak.expires_at < NOW() THEN false
      ELSE true
    END AS is_valid,
    CASE
      WHEN ak.id IS NULL THEN 'Invalid API key'
      WHEN NOT ak.is_active THEN 'API key is inactive'
      WHEN ak.expires_at IS NOT NULL AND ak.expires_at < NOW() THEN 'API key has expired'
      ELSE NULL
    END AS error_message
  FROM app.api_keys ak
  WHERE ak.key_hash = p_key_hash;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to track API key usage
CREATE OR REPLACE FUNCTION app.track_api_key_usage(
  p_api_key_id UUID,
  p_tenant_id UUID,
  p_endpoint TEXT,
  p_method TEXT,
  p_status_code INT,
  p_latency_ms INT,
  p_ip_address INET DEFAULT NULL,
  p_user_agent TEXT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
  -- Insert usage record
  INSERT INTO app.api_key_usage (
    api_key_id,
    tenant_id,
    endpoint,
    method,
    status_code,
    latency_ms,
    ip_address,
    user_agent
  ) VALUES (
    p_api_key_id,
    p_tenant_id,
    p_endpoint,
    p_method,
    p_status_code,
    p_latency_ms,
    p_ip_address,
    p_user_agent
  );

  -- Update last used timestamp
  UPDATE app.api_keys
  SET
    last_used_at = NOW(),
    last_used_ip = p_ip_address,
    last_used_user_agent = p_user_agent
  WHERE id = p_api_key_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check rate limits
CREATE OR REPLACE FUNCTION app.check_rate_limit(
  p_api_key_id UUID,
  p_window_type TEXT,
  p_limit INT
)
RETURNS TABLE (
  allowed BOOLEAN,
  current_count INT,
  remaining INT
) AS $$
DECLARE
  v_window_start TIMESTAMPTZ;
  v_current_count INT;
BEGIN
  -- Calculate window start based on type
  v_window_start := CASE p_window_type
    WHEN 'minute' THEN DATE_TRUNC('minute', NOW())
    WHEN 'hour' THEN DATE_TRUNC('hour', NOW())
    WHEN 'day' THEN DATE_TRUNC('day', NOW())
  END;

  -- Get or create rate limit record
  INSERT INTO app.api_key_rate_limits (api_key_id, window_type, window_start, request_count)
  VALUES (p_api_key_id, p_window_type, v_window_start, 0)
  ON CONFLICT (api_key_id, window_type, window_start) DO NOTHING;

  -- Get current count
  SELECT request_count INTO v_current_count
  FROM app.api_key_rate_limits
  WHERE api_key_id = p_api_key_id
    AND window_type = p_window_type
    AND window_start = v_window_start;

  -- Check if allowed and increment
  IF v_current_count < p_limit THEN
    UPDATE app.api_key_rate_limits
    SET request_count = request_count + 1
    WHERE api_key_id = p_api_key_id
      AND window_type = p_window_type
      AND window_start = v_window_start;

    RETURN QUERY SELECT
      true AS allowed,
      v_current_count + 1 AS current_count,
      p_limit - (v_current_count + 1) AS remaining;
  ELSE
    RETURN QUERY SELECT
      false AS allowed,
      v_current_count AS current_count,
      0 AS remaining;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get API key usage statistics
CREATE OR REPLACE FUNCTION app.get_api_key_stats(
  p_api_key_id UUID,
  p_period INTERVAL DEFAULT '30 days'
)
RETURNS TABLE (
  total_requests BIGINT,
  successful_requests BIGINT,
  failed_requests BIGINT,
  average_latency_ms NUMERIC,
  top_endpoints JSONB,
  daily_usage JSONB
) AS $$
BEGIN
  RETURN QUERY
  WITH usage_stats AS (
    SELECT
      COUNT(*) AS total_requests,
      COUNT(*) FILTER (WHERE status_code < 400) AS successful_requests,
      COUNT(*) FILTER (WHERE status_code >= 400) AS failed_requests,
      AVG(latency_ms) AS average_latency_ms
    FROM app.api_key_usage
    WHERE api_key_id = p_api_key_id
      AND created_at > NOW() - p_period
  ),
  top_endpoints AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'endpoint', endpoint,
        'count', request_count
      ) ORDER BY request_count DESC
    ) AS endpoints
    FROM (
      SELECT endpoint, COUNT(*) AS request_count
      FROM app.api_key_usage
      WHERE api_key_id = p_api_key_id
        AND created_at > NOW() - p_period
      GROUP BY endpoint
      ORDER BY request_count DESC
      LIMIT 10
    ) t
  ),
  daily_usage AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'date', usage_date,
        'requests', request_count
      ) ORDER BY usage_date
    ) AS daily
    FROM (
      SELECT
        DATE(created_at) AS usage_date,
        COUNT(*) AS request_count
      FROM app.api_key_usage
      WHERE api_key_id = p_api_key_id
        AND created_at > NOW() - p_period
      GROUP BY DATE(created_at)
      ORDER BY usage_date
    ) t
  )
  SELECT
    us.total_requests,
    us.successful_requests,
    us.failed_requests,
    us.average_latency_ms,
    te.endpoints AS top_endpoints,
    du.daily AS daily_usage
  FROM usage_stats us
  CROSS JOIN top_endpoints te
  CROSS JOIN daily_usage du;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Triggers
-- ============================================================================

-- Update timestamp trigger
CREATE OR REPLACE FUNCTION app.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS api_keys_updated_at ON app.api_keys;
CREATE TRIGGER api_keys_updated_at
  BEFORE UPDATE ON app.api_keys
  FOR EACH ROW
  EXECUTE FUNCTION app.update_updated_at();

-- Audit log trigger
CREATE OR REPLACE FUNCTION app.audit_api_key_changes()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO app.api_key_audit (
    api_key_id,
    tenant_id,
    event_type,
    event_data,
    performed_by
  ) VALUES (
    COALESCE(NEW.id, OLD.id),
    COALESCE(NEW.tenant_id, OLD.tenant_id),
    CASE
      WHEN TG_OP = 'INSERT' THEN 'created'
      WHEN TG_OP = 'UPDATE' AND OLD.is_active AND NOT NEW.is_active THEN 'deactivated'
      WHEN TG_OP = 'UPDATE' AND NOT OLD.is_active AND NEW.is_active THEN 'activated'
      WHEN TG_OP = 'UPDATE' AND NEW.revoked_at IS NOT NULL AND OLD.revoked_at IS NULL THEN 'revoked'
      WHEN TG_OP = 'UPDATE' THEN 'updated'
      WHEN TG_OP = 'DELETE' THEN 'deleted'
    END,
    jsonb_build_object(
      'old', to_jsonb(OLD),
      'new', to_jsonb(NEW),
      'operation', TG_OP
    ),
    auth.uid()
  );

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS api_keys_audit_trigger ON app.api_keys;
CREATE TRIGGER api_keys_audit_trigger
  AFTER INSERT OR UPDATE OR DELETE ON app.api_keys
  FOR EACH ROW
  EXECUTE FUNCTION app.audit_api_key_changes();

-- ============================================================================
-- Initial Data / Examples
-- ============================================================================

-- Create rate limit tier configurations (metadata table)
CREATE TABLE IF NOT EXISTS app.rate_limit_tiers (
  name TEXT PRIMARY KEY,
  requests_per_minute INT NOT NULL,
  requests_per_hour INT NOT NULL,
  requests_per_day INT NOT NULL,
  max_concurrent_queries INT NOT NULL,
  max_query_duration_ms INT NOT NULL,
  max_rows_per_query INT NOT NULL,
  description TEXT
);

INSERT INTO app.rate_limit_tiers (name, requests_per_minute, requests_per_hour, requests_per_day, max_concurrent_queries, max_query_duration_ms, max_rows_per_query, description)
VALUES
  ('free', 60, 1000, 10000, 5, 10000, 1000, 'Free tier with basic limits'),
  ('pro', 300, 5000, 50000, 10, 30000, 5000, 'Professional tier with increased limits'),
  ('enterprise', 1000, 20000, 200000, 20, 60000, 10000, 'Enterprise tier with high limits'),
  ('custom', 0, 0, 0, 0, 0, 0, 'Custom limits configured per key')
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- Cleanup Function (for old partitions)
-- ============================================================================

CREATE OR REPLACE FUNCTION app.cleanup_old_usage_partitions()
RETURNS VOID AS $$
DECLARE
    partition_date DATE;
    partition_name TEXT;
BEGIN
    -- Keep only last 12 months of partitions
    partition_date := DATE_TRUNC('month', CURRENT_DATE - INTERVAL '12 months');
    partition_name := 'api_key_usage_' || TO_CHAR(partition_date, 'YYYY_MM');

    -- Drop old partition if it exists
    EXECUTE format('DROP TABLE IF EXISTS app.%I', partition_name);

    -- Create new partition for next month
    partition_date := DATE_TRUNC('month', CURRENT_DATE + INTERVAL '1 month');
    partition_name := 'api_key_usage_' || TO_CHAR(partition_date, 'YYYY_MM');

    EXECUTE format('
        CREATE TABLE IF NOT EXISTS app.%I PARTITION OF app.api_key_usage
        FOR VALUES FROM (%L) TO (%L)',
        partition_name,
        partition_date,
        partition_date + INTERVAL '1 month'
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Grant Permissions (for service role)
-- ============================================================================

-- Grant necessary permissions to service role
GRANT ALL ON SCHEMA app TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA app TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA app TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA app TO service_role;

-- Grant read permissions to authenticated users (they use RLS)
GRANT USAGE ON SCHEMA app TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON app.api_keys TO authenticated;
GRANT SELECT ON app.api_key_usage TO authenticated;
GRANT SELECT ON app.api_key_rate_limits TO authenticated;
GRANT SELECT ON app.api_key_audit TO authenticated;
GRANT SELECT ON app.rate_limit_tiers TO authenticated;

-- ============================================================================
-- Comments for Documentation
-- ============================================================================

COMMENT ON TABLE app.api_keys IS 'Stores API keys for authentication with SHA-256 hashed keys';
COMMENT ON TABLE app.api_key_usage IS 'Tracks API key usage for analytics and billing, partitioned by month';
COMMENT ON TABLE app.api_key_rate_limits IS 'Stores rate limiting state for each API key and time window';
COMMENT ON TABLE app.api_key_audit IS 'Audit log for all API key operations for compliance';
COMMENT ON TABLE app.rate_limit_tiers IS 'Configuration for different rate limit tiers';

COMMENT ON FUNCTION app.validate_api_key IS 'Validates an API key hash and returns details if valid';
COMMENT ON FUNCTION app.track_api_key_usage IS 'Records API key usage and updates last used timestamp';
COMMENT ON FUNCTION app.check_rate_limit IS 'Checks and updates rate limit for an API key';
COMMENT ON FUNCTION app.get_api_key_stats IS 'Returns usage statistics for an API key over a period';
COMMENT ON FUNCTION app.cleanup_old_usage_partitions IS 'Removes old usage partitions and creates new ones';
