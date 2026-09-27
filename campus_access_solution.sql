
-- ----------------------------
--  CLEAN RESET
-- ----------------------------

DROP SCHEMA IF EXISTS api CASCADE;
DROP SCHEMA IF EXISTS audit CASCADE;
DROP SCHEMA IF EXISTS config CASCADE;
DROP SCHEMA IF EXISTS finance CASCADE;
DROP SCHEMA IF EXISTS ops CASCADE;
DROP SCHEMA IF EXISTS identity CASCADE;

-- ----------------------------
-- 1) CREATE SCHEMAS
-- ----------------------------
CREATE SCHEMA IF NOT EXISTS identity;
CREATE SCHEMA IF NOT EXISTS ops;
CREATE SCHEMA IF NOT EXISTS finance;
CREATE SCHEMA IF NOT EXISTS config;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS api;

-- ----------------------------
-- 2) CREATE LOGIN ROLES (NO GROUP ROLES)
-- ----------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='student_user') THEN
    CREATE ROLE student_user LOGIN PASSWORD 'student_pw';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='staff_user') THEN
    CREATE ROLE staff_user LOGIN PASSWORD 'staff_pw';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='security_officer') THEN
    CREATE ROLE security_officer LOGIN PASSWORD 'security_pw';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='finance_officer') THEN
    CREATE ROLE finance_officer LOGIN PASSWORD 'finance_pw';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='system_admin') THEN
    CREATE ROLE system_admin LOGIN PASSWORD 'admin_pw';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='auditor') THEN
    CREATE ROLE auditor LOGIN PASSWORD 'auditor_pw';
  END IF;
END $$;

-- ----------------------------
-- 3) HARDEN DEFAULTS
-- ----------------------------
REVOKE ALL ON SCHEMA identity, ops, finance, config, audit, api FROM PUBLIC;

-- =========================================================
-- 4) TABLES + CONSTRAINTS
-- =========================================================

-- ----------------------------
-- 4.1 identity
-- ----------------------------
CREATE TABLE IF NOT EXISTS identity.access_levels (
  level_id     SERIAL PRIMARY KEY,
  level_name   VARCHAR(50) NOT NULL UNIQUE,
  level_value  SMALLINT NOT NULL UNIQUE CHECK (level_value BETWEEN 0 AND 10)
);

CREATE TABLE IF NOT EXISTS identity.users (
  user_id       BIGSERIAL PRIMARY KEY,
  username      VARCHAR(50)  NOT NULL UNIQUE,
  email         VARCHAR(254) NOT NULL UNIQUE,
  full_name     VARCHAR(150) NOT NULL,
  password_hash TEXT         NOT NULL,
  is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
  level_id      INT          NOT NULL REFERENCES identity.access_levels(level_id) ON DELETE RESTRICT,
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS identity.roles (
  role_id   SERIAL PRIMARY KEY,
  role_name VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS identity.user_roles (
  user_id BIGINT NOT NULL REFERENCES identity.users(user_id) ON DELETE CASCADE,
  role_id INT    NOT NULL REFERENCES identity.roles(role_id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, role_id)
);

-- ----------------------------
-- 4.2 ops
-- ----------------------------
CREATE TABLE IF NOT EXISTS ops.zones (
  zone_id   SERIAL PRIMARY KEY,
  zone_name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS ops.buildings (
  building_id          SERIAL PRIMARY KEY,
  building_name        VARCHAR(120) NOT NULL UNIQUE,
  zone_id              INT NOT NULL REFERENCES ops.zones(zone_id) ON DELETE RESTRICT,
  required_level_value SMALLINT NOT NULL CHECK (required_level_value BETWEEN 0 AND 10),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops.devices (
  device_id   SERIAL PRIMARY KEY,
  building_id INT NOT NULL REFERENCES ops.buildings(building_id) ON DELETE CASCADE,
  device_name VARCHAR(100) NOT NULL,
  device_ip   INET NOT NULL UNIQUE,
  device_type VARCHAR(30) NOT NULL CHECK (device_type IN ('door_controller','camera','router','kiosk','other')),
  is_managed  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ops.building_permissions (
  user_id     BIGINT NOT NULL REFERENCES identity.users(user_id) ON DELETE CASCADE,
  building_id INT    NOT NULL REFERENCES ops.buildings(building_id) ON DELETE CASCADE,
  granted_by  BIGINT NOT NULL REFERENCES identity.users(user_id) ON DELETE RESTRICT,
  granted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, building_id)
);

CREATE TABLE IF NOT EXISTS ops.access_overrides (
  override_id BIGSERIAL PRIMARY KEY,
  user_id     BIGINT NOT NULL REFERENCES identity.users(user_id) ON DELETE CASCADE,
  building_id INT    NOT NULL REFERENCES ops.buildings(building_id) ON DELETE CASCADE,
  approved_by BIGINT NOT NULL REFERENCES identity.users(user_id) ON DELETE RESTRICT,
  reason      TEXT   NOT NULL,
  valid_from  TIMESTAMPTZ NOT NULL,
  valid_to    TIMESTAMPTZ NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (valid_to > valid_from)
);

CREATE TABLE IF NOT EXISTS ops.access_events (
  event_id        BIGSERIAL PRIMARY KEY,
  user_id         BIGINT NOT NULL REFERENCES identity.users(user_id) ON DELETE RESTRICT,
  building_id     INT    NOT NULL REFERENCES ops.buildings(building_id) ON DELETE RESTRICT,
  device_id       INT    NULL REFERENCES ops.devices(device_id) ON DELETE SET NULL,
  event_time      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  status          VARCHAR(10) NOT NULL CHECK (status IN ('granted','denied')),
  decision_reason TEXT NULL,
  source_ip       INET NULL,
  request_id      UUID NULL
);

CREATE INDEX IF NOT EXISTS idx_access_events_user_time ON ops.access_events(user_id, event_time DESC);
CREATE INDEX IF NOT EXISTS idx_access_events_building_time ON ops.access_events(building_id, event_time DESC);

CREATE TABLE IF NOT EXISTS ops.feedback (
  feedback_id BIGSERIAL PRIMARY KEY,
  user_id     BIGINT NOT NULL REFERENCES identity.users(user_id) ON DELETE CASCADE,
  comment     TEXT NOT NULL,
  rating      SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------
-- 4.3 finance
-- ----------------------------
CREATE TABLE IF NOT EXISTS finance.payment_methods (
  method_id     BIGSERIAL PRIMARY KEY,
  user_id       BIGINT NOT NULL REFERENCES identity.users(user_id) ON DELETE CASCADE,
  provider      VARCHAR(40) NOT NULL,
  token_ref     TEXT NOT NULL,
  last4         CHAR(4) NULL CHECK (last4 ~ '^[0-9]{4}$'),
  expiry_month  SMALLINT NULL CHECK (expiry_month BETWEEN 1 AND 12),
  expiry_year   SMALLINT NULL CHECK (expiry_year BETWEEN 2000 AND 2100),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS finance.payments (
  payment_id      BIGSERIAL PRIMARY KEY,
  user_id         BIGINT NOT NULL REFERENCES identity.users(user_id) ON DELETE RESTRICT,
  method_id       BIGINT NULL REFERENCES finance.payment_methods(method_id) ON DELETE SET NULL,
  amount          NUMERIC(10,2) NOT NULL CHECK (amount > 0),
  currency        CHAR(3) NOT NULL DEFAULT 'GBP',
  status          VARCHAR(12) NOT NULL CHECK (status IN ('pending','successful','failed','refunded')),
  transaction_ref VARCHAR(100) NULL UNIQUE,
  paid_at         TIMESTAMPTZ NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------
-- 4.4 config
-- ----------------------------
CREATE TABLE IF NOT EXISTS config.system_config (
  config_id    SERIAL PRIMARY KEY,
  config_key   VARCHAR(100) NOT NULL UNIQUE,
  config_value TEXT NOT NULL,
  is_locked    BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by   BIGINT NULL REFERENCES identity.users(user_id) ON DELETE SET NULL
);

-- ----------------------------
-- 4.5 audit
-- ----------------------------
CREATE TABLE IF NOT EXISTS audit.audit_log (
  audit_id      BIGSERIAL PRIMARY KEY,
  event_time    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  actor_user_id BIGINT NULL REFERENCES identity.users(user_id) ON DELETE SET NULL,
  action        VARCHAR(40) NOT NULL,
  entity        VARCHAR(80) NOT NULL,
  entity_id     TEXT NULL,
  after_data    JSONB NULL,
  source_ip     INET NULL
);

-- =========================================================
-- 5) SIMPLE AUDIT HELPER (NO TRIGGERS)
-- =========================================================
CREATE OR REPLACE FUNCTION audit.log(
  p_actor_user_id BIGINT,
  p_action TEXT,
  p_entity TEXT,
  p_entity_id TEXT DEFAULT NULL,
  p_details JSONB DEFAULT NULL,
  p_source_ip INET DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
BEGIN
  INSERT INTO audit.audit_log(actor_user_id, action, entity, entity_id, after_data, source_ip)
  VALUES (p_actor_user_id, p_action, p_entity, p_entity_id, p_details, p_source_ip);
END $$;

-- =========================================================
-- 6) API VIEWS (SAFE READ SURFACE)
-- =========================================================
CREATE OR REPLACE VIEW api.v_building_catalogue AS
SELECT
  b.building_id,
  b.building_name,
  z.zone_name,
  b.required_level_value
FROM ops.buildings b
JOIN ops.zones z ON z.zone_id = b.zone_id;

CREATE OR REPLACE VIEW api.v_user_directory_limited AS
SELECT
  u.user_id,
  u.username,
  u.full_name,
  u.is_active,
  al.level_value
FROM identity.users u
JOIN identity.access_levels al ON al.level_id = u.level_id;

CREATE OR REPLACE VIEW api.v_access_events_recent AS
SELECT
  e.event_id,
  e.event_time,
  e.user_id,
  e.building_id,
  e.device_id,
  e.status,
  e.decision_reason,
  e.source_ip
FROM ops.access_events e
WHERE e.event_time >= NOW() - INTERVAL '30 days';

CREATE OR REPLACE VIEW api.v_finance_payments_overview AS
SELECT
  p.payment_id,
  p.user_id,
  p.amount,
  p.currency,
  p.status,
  p.transaction_ref,
  p.paid_at,
  p.created_at
FROM finance.payments p;

CREATE OR REPLACE VIEW api.v_config_readonly AS
SELECT
  c.config_key,
  c.config_value,
  c.is_locked,
  c.updated_at,
  c.updated_by
FROM config.system_config c;

CREATE OR REPLACE VIEW api.v_audit_summary AS
SELECT
  a.audit_id,
  a.event_time,
  a.actor_user_id,
  a.action,
  a.entity,
  a.entity_id,
  a.source_ip
FROM audit.audit_log a;

-- =========================================================
-- 7) API FUNCTIONS (VALIDATION + SIMPLE AUDIT)
-- =========================================================

-- Role membership helper (DB table roles)
CREATE OR REPLACE FUNCTION api.user_has_role(p_user_id BIGINT, p_role_name TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM identity.user_roles ur
    JOIN identity.roles r ON r.role_id = ur.role_id
    WHERE ur.user_id = p_user_id AND r.role_name = p_role_name
  );
$$;

-- 7.1 Request access (always logs to access_events; optional audit entry)
CREATE OR REPLACE FUNCTION api.request_access(
  p_user_id BIGINT,
  p_building_id INT,
  p_device_id INT DEFAULT NULL,
  p_source_ip INET DEFAULT NULL
) RETURNS TABLE(status TEXT, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = api, identity, ops, finance, config, audit, public
AS $$
DECLARE
  v_user_level SMALLINT;
  v_req_level SMALLINT;
  v_has_perm BOOLEAN;
  v_has_override BOOLEAN;
  v_status TEXT := 'denied';
  v_reason TEXT := 'insufficient_privilege';
BEGIN
  IF p_user_id IS NULL OR p_building_id IS NULL THEN
    RAISE EXCEPTION 'Missing required parameters' USING ERRCODE='P0002';
  END IF;

  -- user exists + active
  SELECT al.level_value INTO v_user_level
  FROM identity.users u
  JOIN identity.access_levels al ON al.level_id = u.level_id
  WHERE u.user_id = p_user_id AND u.is_active = TRUE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % not found or inactive', p_user_id USING ERRCODE='P0002';
  END IF;

  -- building exists
  SELECT required_level_value INTO v_req_level
  FROM ops.buildings
  WHERE building_id = p_building_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Building % not found', p_building_id USING ERRCODE='P0002';
  END IF;

  -- optional device validation
  IF p_device_id IS NOT NULL THEN
    PERFORM 1 FROM ops.devices d WHERE d.device_id=p_device_id AND d.building_id=p_building_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Device % invalid for building %', p_device_id, p_building_id USING ERRCODE='P0002';
    END IF;
  END IF;

  v_has_perm := EXISTS (
    SELECT 1 FROM ops.building_permissions bp
    WHERE bp.user_id = p_user_id AND bp.building_id = p_building_id
  );

  v_has_override := EXISTS (
    SELECT 1 FROM ops.access_overrides ao
    WHERE ao.user_id = p_user_id AND ao.building_id = p_building_id
      AND NOW() BETWEEN ao.valid_from AND ao.valid_to
  );

  IF v_user_level >= v_req_level THEN
    v_status := 'granted'; v_reason := 'clearance_level';
  ELSIF v_has_perm THEN
    v_status := 'granted'; v_reason := 'explicit_permission';
  ELSIF v_has_override THEN
    v_status := 'granted'; v_reason := 'time_bound_override';
  END IF;

  INSERT INTO ops.access_events(user_id, building_id, device_id, status, decision_reason, source_ip)
  VALUES (p_user_id, p_building_id, p_device_id, v_status, v_reason, p_source_ip);

 
  PERFORM audit.log(
    p_user_id,
    'ACCESS_' || upper(v_status),
    'ops.access_events',
    NULL,
    jsonb_build_object('user_id',p_user_id,'building_id',p_building_id,'status',v_status,'reason',v_reason),
    p_source_ip
  );

  status := v_status;
  reason := v_reason;
  RETURN NEXT;
END $$;

-- 7.2 Grant permission (security officer)
CREATE OR REPLACE FUNCTION api.grant_building_permission(
  p_user_id BIGINT,
  p_building_id INT,
  p_granted_by BIGINT,
  p_source_ip INET DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = api, identity, ops, audit, public
AS $$
BEGIN
  IF NOT api.user_has_role(p_granted_by, 'security_officer') THEN
    RAISE EXCEPTION 'Not authorised to grant permissions' USING ERRCODE='P0001';
  END IF;

  PERFORM 1 FROM identity.users WHERE user_id=p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target user % not found', p_user_id USING ERRCODE='P0002';
  END IF;

  PERFORM 1 FROM ops.buildings WHERE building_id=p_building_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Building % not found', p_building_id USING ERRCODE='P0002';
  END IF;

  BEGIN
    INSERT INTO ops.building_permissions(user_id, building_id, granted_by)
    VALUES (p_user_id, p_building_id, p_granted_by);
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Permission already exists for user % and building %', p_user_id, p_building_id USING ERRCODE='23505';
  END;

  PERFORM audit.log(
    p_granted_by,
    'GRANT_PERMISSION',
    'ops.building_permissions',
    p_user_id||','||p_building_id,
    jsonb_build_object('user_id',p_user_id,'building_id',p_building_id,'granted_by',p_granted_by),
    p_source_ip
  );
END $$;

-- 7.3 Approve override (security officer)
CREATE OR REPLACE FUNCTION api.approve_override(
  p_user_id BIGINT,
  p_building_id INT,
  p_approved_by BIGINT,
  p_reason TEXT,
  p_valid_from TIMESTAMPTZ,
  p_valid_to TIMESTAMPTZ,
  p_source_ip INET DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = api, identity, ops, audit, public
AS $$
DECLARE
  v_id BIGINT;
BEGIN
  IF NOT api.user_has_role(p_approved_by, 'security_officer') THEN
    RAISE EXCEPTION 'Not authorised to approve overrides' USING ERRCODE='P0001';
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason))=0 THEN
    RAISE EXCEPTION 'Override reason must not be empty' USING ERRCODE='P0002';
  END IF;

  IF p_valid_to <= p_valid_from THEN
    RAISE EXCEPTION 'Invalid override window' USING ERRCODE='P0002';
  END IF;

  PERFORM 1 FROM identity.users WHERE user_id=p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target user % not found', p_user_id USING ERRCODE='P0002';
  END IF;

  PERFORM 1 FROM ops.buildings WHERE building_id=p_building_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Building % not found', p_building_id USING ERRCODE='P0002';
  END IF;

  INSERT INTO ops.access_overrides(user_id, building_id, approved_by, reason, valid_from, valid_to)
  VALUES (p_user_id, p_building_id, p_approved_by, p_reason, p_valid_from, p_valid_to)
  RETURNING override_id INTO v_id;

  PERFORM audit.log(
    p_approved_by,
    'APPROVE_OVERRIDE',
    'ops.access_overrides',
    v_id::text,
    jsonb_build_object('override_id',v_id,'user_id',p_user_id,'building_id',p_building_id,'valid_from',p_valid_from,'valid_to',p_valid_to),
    p_source_ip
  );

  RETURN v_id;
END $$;

-- 7.4 Add payment method (tokenised)
CREATE OR REPLACE FUNCTION api.add_payment_method(
  p_user_id BIGINT,
  p_provider VARCHAR,
  p_token_ref TEXT,
  p_last4 CHAR(4) DEFAULT NULL,
  p_expiry_month SMALLINT DEFAULT NULL,
  p_expiry_year SMALLINT DEFAULT NULL,
  p_source_ip INET DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = api, identity, finance, audit, public
AS $$
DECLARE
  v_id BIGINT;
BEGIN
  PERFORM 1 FROM identity.users WHERE user_id=p_user_id AND is_active=TRUE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % not found or inactive', p_user_id USING ERRCODE='P0002';
  END IF;

  IF p_token_ref IS NULL OR length(trim(p_token_ref))=0 THEN
    RAISE EXCEPTION 'token_ref must not be empty' USING ERRCODE='P0002';
  END IF;

  IF p_expiry_month IS NOT NULL AND (p_expiry_month < 1 OR p_expiry_month > 12) THEN
    RAISE EXCEPTION 'expiry_month out of range' USING ERRCODE='P0002';
  END IF;

  IF p_expiry_year IS NOT NULL AND (p_expiry_year < 2000 OR p_expiry_year > 2100) THEN
    RAISE EXCEPTION 'expiry_year out of range' USING ERRCODE='P0002';
  END IF;

  INSERT INTO finance.payment_methods(user_id, provider, token_ref, last4, expiry_month, expiry_year)
  VALUES (p_user_id, p_provider, p_token_ref, p_last4, p_expiry_month, p_expiry_year)
  RETURNING method_id INTO v_id;

  PERFORM audit.log(
    p_user_id,
    'ADD_PAYMENT_METHOD',
    'finance.payment_methods',
    v_id::text,
    jsonb_build_object('method_id',v_id,'provider',p_provider,'last4',p_last4),
    p_source_ip
  );

  RETURN v_id;
END $$;

-- 7.5 Make payment
CREATE OR REPLACE FUNCTION api.make_payment(
  p_user_id BIGINT,
  p_method_id BIGINT,
  p_amount NUMERIC,
  p_currency CHAR(3) DEFAULT 'GBP',
  p_source_ip INET DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = api, identity, finance, audit, public
AS $$
DECLARE
  v_id BIGINT;
BEGIN
  PERFORM 1 FROM identity.users WHERE user_id=p_user_id AND is_active=TRUE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % not found or inactive', p_user_id USING ERRCODE='P0002';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive' USING ERRCODE='P0002';
  END IF;

  IF p_method_id IS NOT NULL THEN
    PERFORM 1 FROM finance.payment_methods pm WHERE pm.method_id=p_method_id AND pm.user_id=p_user_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Payment method % does not belong to user %', p_method_id, p_user_id USING ERRCODE='P0002';
    END IF;
  END IF;

  INSERT INTO finance.payments(user_id, method_id, amount, currency, status)
  VALUES (p_user_id, p_method_id, p_amount, COALESCE(p_currency,'GBP'), 'pending')
  RETURNING payment_id INTO v_id;

  PERFORM audit.log(
    p_user_id,
    'CREATE_PAYMENT',
    'finance.payments',
    v_id::text,
    jsonb_build_object('payment_id',v_id,'amount',p_amount,'currency',p_currency,'status','pending'),
    p_source_ip
  );

  RETURN v_id;
END $$;

-- 7.6 Set payment status (finance)
CREATE OR REPLACE FUNCTION api.set_payment_status(
  p_payment_id BIGINT,
  p_new_status VARCHAR,
  p_actor_user_id BIGINT,
  p_source_ip INET DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = api, identity, finance, audit, public
AS $$
DECLARE
  v_old_status TEXT;
BEGIN
  IF NOT api.user_has_role(p_actor_user_id, 'finance_officer') THEN
    RAISE EXCEPTION 'Not authorised to update payment status' USING ERRCODE='P0001';
  END IF;

  SELECT status INTO v_old_status FROM finance.payments WHERE payment_id=p_payment_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment % not found', p_payment_id USING ERRCODE='P0002';
  END IF;

  IF p_new_status NOT IN ('pending','successful','failed','refunded') THEN
    RAISE EXCEPTION 'Invalid payment status: %', p_new_status USING ERRCODE='P0002';
  END IF;

  -- Simple transition rules 
  IF v_old_status = 'pending' AND p_new_status NOT IN ('successful','failed') THEN
    RAISE EXCEPTION 'Invalid status transition % -> %', v_old_status, p_new_status USING ERRCODE='P0002';
  END IF;
  IF v_old_status = 'successful' AND p_new_status <> 'refunded' THEN
    RAISE EXCEPTION 'Invalid status transition % -> %', v_old_status, p_new_status USING ERRCODE='P0002';
  END IF;
  IF v_old_status IN ('failed','refunded') THEN
    RAISE EXCEPTION 'Cannot transition from terminal state %', v_old_status USING ERRCODE='P0002';
  END IF;

  UPDATE finance.payments
  SET status = p_new_status,
      paid_at = CASE WHEN p_new_status='successful' THEN NOW() ELSE paid_at END
  WHERE payment_id = p_payment_id;

  PERFORM audit.log(
    p_actor_user_id,
    'UPDATE_PAYMENT_STATUS',
    'finance.payments',
    p_payment_id::text,
    jsonb_build_object('payment_id',p_payment_id,'old_status',v_old_status,'new_status',p_new_status),
    p_source_ip
  );
END $$;

-- 7.7 Update config with lock enforcement (system admin)
CREATE OR REPLACE FUNCTION api.update_config(
  p_key VARCHAR,
  p_value TEXT,
  p_actor_user_id BIGINT,
  p_source_ip INET DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = api, identity, config, audit, public
AS $$
DECLARE
  v_locked BOOLEAN;
BEGIN
  IF NOT api.user_has_role(p_actor_user_id, 'system_admin') THEN
    RAISE EXCEPTION 'Not authorised to update configuration' USING ERRCODE='P0001';
  END IF;

  IF p_key IS NULL OR length(trim(p_key))=0 THEN
    RAISE EXCEPTION 'Config key must not be empty' USING ERRCODE='P0002';
  END IF;

  SELECT is_locked INTO v_locked FROM config.system_config WHERE config_key=p_key;
  IF FOUND AND v_locked = TRUE THEN
    RAISE EXCEPTION 'Config % is locked', p_key USING ERRCODE='P0002';
  END IF;

  INSERT INTO config.system_config(config_key, config_value, updated_by)
  VALUES (p_key, p_value, p_actor_user_id)
  ON CONFLICT (config_key) DO UPDATE
    SET config_value = EXCLUDED.config_value,
        updated_at = NOW(),
        updated_by = EXCLUDED.updated_by;

  PERFORM audit.log(
    p_actor_user_id,
    'UPDATE_CONFIG',
    'config.system_config',
    p_key,
    jsonb_build_object('config_key',p_key,'is_locked',false),
    p_source_ip
  );
END $$;

-- 7.8 Submit feedback
CREATE OR REPLACE FUNCTION api.submit_feedback(
  p_user_id BIGINT,
  p_rating SMALLINT,
  p_comment TEXT,
  p_source_ip INET DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = api, identity, ops, audit, public
AS $$
DECLARE
  v_id BIGINT;
BEGIN
  PERFORM 1 FROM identity.users WHERE user_id=p_user_id AND is_active=TRUE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % not found or inactive', p_user_id USING ERRCODE='P0002';
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Rating must be between 1 and 5' USING ERRCODE='P0002';
  END IF;

  IF p_comment IS NULL OR length(trim(p_comment))=0 THEN
    RAISE EXCEPTION 'Comment must not be empty' USING ERRCODE='P0002';
  END IF;

  INSERT INTO ops.feedback(user_id, rating, comment)
  VALUES (p_user_id, p_rating, p_comment)
  RETURNING feedback_id INTO v_id;

  -- (Optional) light audit
  PERFORM audit.log(
    p_user_id,
    'SUBMIT_FEEDBACK',
    'ops.feedback',
    v_id::text,
    jsonb_build_object('feedback_id',v_id,'rating',p_rating),
    p_source_ip
  );

  RETURN v_id;
END $$;

-- =========================================================
-- 8)  ROLE NAMES (used by user_roles mapping)
-- =========================================================
INSERT INTO identity.roles(role_name) VALUES
 ('student_user'),
 ('staff_user'),
 ('security_officer'),
 ('finance_officer'),
 ('system_admin'),
 ('auditor')
ON CONFLICT DO NOTHING;

-- =========================================================
-- 9) GRANTS (API-FIRST, LEAST PRIVILEGE)
-- =========================================================

-- Allow using API schema
GRANT USAGE ON SCHEMA api TO student_user, staff_user, security_officer, finance_officer, system_admin, auditor;

-- Allow auditors/admin to see audit summary view (not necessarily full audit table)
GRANT USAGE ON SCHEMA audit TO auditor, system_admin;

-- Views
GRANT SELECT ON api.v_building_catalogue TO student_user, staff_user, security_officer;
GRANT SELECT ON api.v_access_events_recent TO security_officer;
GRANT SELECT ON api.v_user_directory_limited TO security_officer, system_admin;
GRANT SELECT ON api.v_finance_payments_overview TO finance_officer;
GRANT SELECT ON api.v_config_readonly TO system_admin;
GRANT SELECT ON api.v_audit_summary TO auditor, system_admin;

-- Functions (execute)
GRANT EXECUTE ON FUNCTION api.request_access(bigint,int,int,inet) TO student_user, staff_user, security_officer;
GRANT EXECUTE ON FUNCTION api.submit_feedback(bigint,smallint,text,inet) TO student_user, staff_user;

GRANT EXECUTE ON FUNCTION api.grant_building_permission(bigint,int,bigint,inet) TO security_officer;
GRANT EXECUTE ON FUNCTION api.approve_override(bigint,int,bigint,text,timestamptz,timestamptz,inet) TO security_officer;

GRANT EXECUTE ON FUNCTION api.add_payment_method(bigint,varchar,text,char,smallint,smallint,inet) TO student_user, staff_user;
GRANT EXECUTE ON FUNCTION api.make_payment(bigint,bigint,numeric,char,inet) TO student_user, staff_user;
GRANT EXECUTE ON FUNCTION api.set_payment_status(bigint,varchar,bigint,inet) TO finance_officer;

GRANT EXECUTE ON FUNCTION api.update_config(varchar,text,bigint,inet) TO system_admin;

-- Deny direct table access broadly
REVOKE ALL ON ALL TABLES IN SCHEMA identity FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA ops FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA finance FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA config FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA audit FROM PUBLIC;

 --allow auditor to read full audit table
GRANT SELECT ON audit.audit_log TO auditor;


-- ======================================================
-- 10) INSERTING DATA
-- ======================================================
-- -----------------------------
-- Access levels
-- -----------------------------
INSERT INTO identity.access_levels(level_name, level_value) VALUES
('Student', 1),
('Staff', 5),
('Security', 8),
('Admin', 10)
ON CONFLICT DO NOTHING;

-- -----------------------------
-- Users
-- -----------------------------
INSERT INTO identity.users(username,email,full_name,password_hash,level_id)
VALUES
('alice','alice@student.edu','Alice Student','hash1',
 (SELECT level_id FROM identity.access_levels WHERE level_name='Student')),

('bob','bob@security.edu','Bob Security','hash2',
 (SELECT level_id FROM identity.access_levels WHERE level_name='Security')),

('carol','carol@finance.edu','Carol Finance','hash3',
 (SELECT level_id FROM identity.access_levels WHERE level_name='Staff')),

('dave','dave@admin.edu','Dave Admin','hash4',
 (SELECT level_id FROM identity.access_levels WHERE level_name='Admin')),

('eve','eve@student.edu','Eve Student','hash5',
 (SELECT level_id FROM identity.access_levels WHERE level_name='Student'))
ON CONFLICT DO NOTHING;

-- -----------------------------
-- Role definitions (already created but safe)
-- -----------------------------
INSERT INTO identity.roles(role_name) VALUES
('student_user'),
('staff_user'),
('security_officer'),
('finance_officer'),
('system_admin'),
('auditor')
ON CONFLICT DO NOTHING;

-- -----------------------------
-- Assign roles to users
-- -----------------------------
INSERT INTO identity.user_roles(user_id, role_id)
SELECT u.user_id, r.role_id
FROM identity.users u, identity.roles r
WHERE u.username='alice' AND r.role_name='student_user'
ON CONFLICT DO NOTHING;

INSERT INTO identity.user_roles(user_id, role_id)
SELECT u.user_id, r.role_id
FROM identity.users u, identity.roles r
WHERE u.username='eve' AND r.role_name='student_user'
ON CONFLICT DO NOTHING;

INSERT INTO identity.user_roles(user_id, role_id)
SELECT u.user_id, r.role_id
FROM identity.users u, identity.roles r
WHERE u.username='bob' AND r.role_name='security_officer'
ON CONFLICT DO NOTHING;

INSERT INTO identity.user_roles(user_id, role_id)
SELECT u.user_id, r.role_id
FROM identity.users u, identity.roles r
WHERE u.username='carol' AND r.role_name='finance_officer'
ON CONFLICT DO NOTHING;

INSERT INTO identity.user_roles(user_id, role_id)
SELECT u.user_id, r.role_id
FROM identity.users u, identity.roles r
WHERE u.username='dave' AND r.role_name='system_admin'
ON CONFLICT DO NOTHING;

-- -----------------------------
-- Zones
-- -----------------------------
INSERT INTO ops.zones(zone_name) VALUES
('North Campus'),
('South Campus')
ON CONFLICT DO NOTHING;

-- -----------------------------
-- Buildings
-- -----------------------------
INSERT INTO ops.buildings(building_name, zone_id, required_level_value)
SELECT 'Library', z.zone_id, 1 FROM ops.zones z WHERE z.zone_name='North Campus'
ON CONFLICT DO NOTHING;

INSERT INTO ops.buildings(building_name, zone_id, required_level_value)
SELECT 'Engineering Lab', z.zone_id, 5 FROM ops.zones z WHERE z.zone_name='North Campus'
ON CONFLICT DO NOTHING;

INSERT INTO ops.buildings(building_name, zone_id, required_level_value)
SELECT 'Data Centre', z.zone_id, 10 FROM ops.zones z WHERE z.zone_name='South Campus'
ON CONFLICT DO NOTHING;

-- -----------------------------
-- Devices
-- -----------------------------
INSERT INTO ops.devices(building_id, device_name, device_ip, device_type)
SELECT building_id,'Library Door Controller','192.168.1.10','door_controller'
FROM ops.buildings WHERE building_name='Library'
ON CONFLICT DO NOTHING;

INSERT INTO ops.devices(building_id, device_name, device_ip, device_type)
SELECT building_id,'Engineering Access Panel','192.168.1.20','door_controller'
FROM ops.buildings WHERE building_name='Engineering Lab'
ON CONFLICT DO NOTHING;

-- -----------------------------
-- Example building permission
-- (Alice allowed into Engineering Lab)
-- -----------------------------
INSERT INTO ops.building_permissions(user_id,building_id,granted_by)
SELECT 
 (SELECT user_id FROM identity.users WHERE username='alice'),
 (SELECT building_id FROM ops.buildings WHERE building_name='Engineering Lab'),
 (SELECT user_id FROM identity.users WHERE username='bob')
ON CONFLICT DO NOTHING;

-- -----------------------------
-- Example payment method
-- -----------------------------
INSERT INTO finance.payment_methods(user_id,provider,token_ref,last4,expiry_month,expiry_year)
SELECT
 (SELECT user_id FROM identity.users WHERE username='alice'),
 'Stripe',
 'tok_test_123',
 '4242',
 12,
 2030
ON CONFLICT DO NOTHING;

-- -----------------------------
-- Example system config
-- -----------------------------
INSERT INTO config.system_config(config_key,config_value)
VALUES
('lockdown_mode','false'),
('maintenance_mode','false')
ON CONFLICT DO NOTHING;

