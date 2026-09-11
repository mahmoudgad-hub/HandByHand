-- =====================================================================
-- Hand By Hand (new) - migration 0002: authentication, roles, and the
-- child access gate.
--
-- Children and guardians are in this migration rather than the next
-- one for a single reason: the security gate cannot be PROVEN without
-- them. A phase that ships an access rule with no way to demonstrate a
-- real refusal has shipped an opinion, not a control.
--
-- Error classes added here:
--   HB010  number series is not defined for this centre
--
-- Deliberately NOT an error class: a wrong one-time code.
-- See "THE COUNTER PROBLEM" below - it is the whole reason
-- verify_otp returns a status instead of raising.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0002') THEN
    RAISE EXCEPTION 'migration 0002 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0001') THEN
    RAISE EXCEPTION 'migration 0001 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- USER-VISIBLE NUMBERS
--
-- CH-2026-00021 and the like. A sequence cannot do this: the number is
-- per centre, per series, formatted, and must have no gaps that a
-- receptionist would have to explain. So it is a row, locked while it
-- is read and incremented.
-- =====================================================================
CREATE TABLE hbh.number_series (
  series_id      integer     GENERATED ALWAYS AS IDENTITY,
  center_id      integer     NOT NULL,
  code           text        NOT NULL,
  prefix         text        NOT NULL DEFAULT '',
  include_year_flg boolean   NOT NULL DEFAULT true,
  current_year   integer,
  next_value     integer     NOT NULL DEFAULT 1,
  width          smallint    NOT NULL DEFAULT 5,
  active_flg     boolean     NOT NULL DEFAULT true,
  deleted_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at     timestamptz,
  updated_by     text,
  CONSTRAINT pk_number_series PRIMARY KEY (series_id),
  CONSTRAINT fk_number_series_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT uq_number_series UNIQUE (center_id, code),
  CONSTRAINT ck_number_series_width CHECK (width BETWEEN 3 AND 10)
);

CREATE INDEX ix_number_series_center ON hbh.number_series (center_id);

-- SECURITY DEFINER: the API never touches this table directly, and the
-- row lock is what stops two receptionists getting the same number.
CREATE OR REPLACE FUNCTION hbh.next_number(p_center_id integer, p_code text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_row  hbh.number_series%ROWTYPE;
  l_year integer := extract(year FROM now() AT TIME ZONE 'UTC')::integer;
  l_seq  integer;
BEGIN
  SELECT * INTO l_row
  FROM   hbh.number_series
  WHERE  center_id = p_center_id AND code = p_code AND active_flg
  FOR    UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'number series % is not defined for centre %', p_code, p_center_id
      USING ERRCODE = 'HB010';
  END IF;

  IF l_row.include_year_flg AND l_row.current_year IS DISTINCT FROM l_year THEN
    l_seq := 1;
    UPDATE hbh.number_series
       SET current_year = l_year, next_value = 2
     WHERE series_id = l_row.series_id;
  ELSE
    l_seq := l_row.next_value;
    UPDATE hbh.number_series
       SET next_value = l_row.next_value + 1,
           current_year = coalesce(l_row.current_year, l_year)
     WHERE series_id = l_row.series_id;
  END IF;

  RETURN l_row.prefix
      || CASE WHEN l_row.include_year_flg THEN l_year::text || '-' ELSE '' END
      || lpad(l_seq::text, l_row.width, '0');
END
$$;

-- =====================================================================
-- ROLES AND PERMISSIONS
-- =====================================================================
CREATE TABLE hbh.permissions (
  permission_id integer     GENERATED ALWAYS AS IDENTITY,
  code          text        NOT NULL,
  name_ar       text        NOT NULL,
  name_en       text,
  active_flg    boolean     NOT NULL DEFAULT true,
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at    timestamptz,
  updated_by    text,
  CONSTRAINT pk_permissions PRIMARY KEY (permission_id),
  CONSTRAINT uq_permissions_code UNIQUE (code),
  CONSTRAINT ck_permissions_code CHECK (code ~ '^[A-Z][A-Z0-9_.]{2,59}$')
);

CREATE TABLE hbh.roles (
  role_id       integer     GENERATED ALWAYS AS IDENTITY,
  center_id     integer     NOT NULL,
  code          text        NOT NULL,
  name_ar       text        NOT NULL,
  name_en       text,
  is_system_flg boolean     NOT NULL DEFAULT false,
  active_flg    boolean     NOT NULL DEFAULT true,
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at    timestamptz,
  updated_by    text,
  CONSTRAINT pk_roles PRIMARY KEY (role_id),
  CONSTRAINT fk_roles_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT uq_roles_code UNIQUE (center_id, code)
);

CREATE INDEX ix_roles_center ON hbh.roles (center_id);

CREATE TABLE hbh.role_permissions (
  role_id       integer     NOT NULL,
  permission_id integer     NOT NULL,
  active_flg    boolean     NOT NULL DEFAULT true,
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at    timestamptz,
  updated_by    text,
  CONSTRAINT pk_role_permissions PRIMARY KEY (role_id, permission_id),
  CONSTRAINT fk_role_permissions_role FOREIGN KEY (role_id)       REFERENCES hbh.roles (role_id),
  CONSTRAINT fk_role_permissions_perm FOREIGN KEY (permission_id) REFERENCES hbh.permissions (permission_id)
);

-- The primary key already leads with role_id; the other direction needs
-- its own index or a permission delete locks the whole table.
CREATE INDEX ix_role_permissions_perm ON hbh.role_permissions (permission_id);

CREATE TABLE hbh.user_roles (
  user_id     integer     NOT NULL,
  role_id     integer     NOT NULL,
  active_flg  boolean     NOT NULL DEFAULT true,
  deleted_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at  timestamptz,
  updated_by  text,
  CONSTRAINT pk_user_roles PRIMARY KEY (user_id, role_id),
  CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id) REFERENCES hbh.users (user_id),
  CONSTRAINT fk_user_roles_role FOREIGN KEY (role_id) REFERENCES hbh.roles (role_id)
);

CREATE INDEX ix_user_roles_role ON hbh.user_roles (role_id);

-- =====================================================================
-- CHILDREN AND GUARDIANS
-- =====================================================================
CREATE TABLE hbh.children (
  child_id     integer     GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,
  branch_id    integer,
  child_no     text        NOT NULL,
  full_name_ar text        NOT NULL,
  birth_date   date        NOT NULL,
  gender       char(1)     NOT NULL,
  national_id  text,
  status       text        NOT NULL DEFAULT 'ACTIVE',
  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,
  CONSTRAINT pk_children PRIMARY KEY (child_id),
  CONSTRAINT fk_children_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_children_branch FOREIGN KEY (branch_id) REFERENCES hbh.branches (branch_id),
  CONSTRAINT uq_children_no UNIQUE (center_id, child_no),
  CONSTRAINT ck_children_gender CHECK (gender IN ('M','F')),
  CONSTRAINT ck_children_status CHECK (status IN ('ACTIVE','INACTIVE','GRADUATED','WITHDRAWN')),
  CONSTRAINT ck_children_birth  CHECK (birth_date <= current_date)
);

-- A PARTIAL unique index, and the distinction matters more than it looks.
--
-- sys_params uses UNIQUE NULLS NOT DISTINCT because there NULL is a
-- real value: it means "global". Two global rows with one code is a
-- genuine duplicate.
--
-- Here NULL means "we do not know it yet" - and this is a centre for
-- small children in Egypt, where many have no national id at all. Two
-- unknowns are not a duplicate. NULLS NOT DISTINCT here would reject
-- the SECOND child without a national id, which is exactly the defect
-- that reached production in the Oracle system and would have hit
-- reception on its first day.
--
-- The rule: NULLS NOT DISTINCT when NULL is a value; a partial index
-- when NULL is an absence.
CREATE UNIQUE INDEX uix_children_national
  ON hbh.children (center_id, national_id)
  WHERE national_id IS NOT NULL;

CREATE INDEX ix_children_center    ON hbh.children (center_id);
CREATE INDEX ix_children_branch    ON hbh.children (branch_id);
CREATE INDEX ix_children_name_srch ON hbh.children (hbh.normalize_arabic(full_name_ar));

CREATE TABLE hbh.guardians (
  guardian_id  integer     GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,
  branch_id    integer,
  user_id      integer,
  full_name_ar text        NOT NULL,
  mobile       text        NOT NULL,
  national_id  text,
  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,
  CONSTRAINT pk_guardians PRIMARY KEY (guardian_id),
  CONSTRAINT fk_guardians_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_guardians_branch FOREIGN KEY (branch_id) REFERENCES hbh.branches (branch_id),
  CONSTRAINT fk_guardians_user   FOREIGN KEY (user_id)   REFERENCES hbh.users (user_id),
  CONSTRAINT ck_guardians_mobile CHECK (mobile ~ '^[0-9+]{6,20}$')
);

CREATE INDEX ix_guardians_center    ON hbh.guardians (center_id);
CREATE INDEX ix_guardians_branch    ON hbh.guardians (branch_id);
CREATE INDEX ix_guardians_mobile    ON hbh.guardians (mobile);
CREATE INDEX ix_guardians_name_srch ON hbh.guardians (hbh.normalize_arabic(full_name_ar));

-- One account, one guardian record.
CREATE UNIQUE INDEX uix_guardians_user ON hbh.guardians (user_id) WHERE user_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- guardian_children - the link the whole portal hangs on
--
-- can_view_live_flg defaults to FALSE. Watching a child in a therapy
-- session is the most sensitive thing this system does, and a
-- permission flag with no explicit default takes whatever the form
-- happens to send. The Oracle system shipped exactly this switch with
-- no default. Default deny; granting is a deliberate act.
-- ---------------------------------------------------------------------
CREATE TABLE hbh.guardian_children (
  guardian_id          integer     NOT NULL,
  child_id             integer     NOT NULL,
  relationship_code    text        NOT NULL,
  is_primary_flg       boolean     NOT NULL DEFAULT false,
  can_view_live_flg    boolean     NOT NULL DEFAULT false,
  can_view_reports_flg boolean     NOT NULL DEFAULT true,
  active_flg           boolean     NOT NULL DEFAULT true,
  deleted_at           timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  created_by           text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at           timestamptz,
  updated_by           text,
  CONSTRAINT pk_guardian_children PRIMARY KEY (guardian_id, child_id),
  CONSTRAINT fk_guardian_children_guardian FOREIGN KEY (guardian_id) REFERENCES hbh.guardians (guardian_id),
  CONSTRAINT fk_guardian_children_child    FOREIGN KEY (child_id)    REFERENCES hbh.children (child_id)
);

CREATE INDEX ix_guardian_children_child ON hbh.guardian_children (child_id);

-- =====================================================================
-- ONE-TIME CODES AND LOGIN SESSIONS
--
-- Named auth_sessions, not sessions. A therapy session is the central
-- object of this domain; a table called "sessions" that means a login
-- would collide with it in every query and every conversation.
--
-- Neither table is granted to hbh_app. They are reachable only through
-- the SECURITY DEFINER functions below, so the API cannot read a code
-- hash or a token hash even by accident.
-- =====================================================================
CREATE TABLE hbh.otp_codes (
  otp_id      bigint      GENERATED ALWAYS AS IDENTITY,
  center_id   integer     NOT NULL,
  user_id     integer     NOT NULL,
  mobile      text        NOT NULL,
  code_hash   text        NOT NULL,
  purpose     text        NOT NULL DEFAULT 'LOGIN',
  attempts    smallint    NOT NULL DEFAULT 0,
  issued_at   timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL,
  consumed_at timestamptz,
  CONSTRAINT pk_otp_codes PRIMARY KEY (otp_id),
  CONSTRAINT fk_otp_codes_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_otp_codes_user   FOREIGN KEY (user_id)   REFERENCES hbh.users (user_id),
  CONSTRAINT ck_otp_codes_purpose CHECK (purpose IN ('LOGIN','RESET')),
  CONSTRAINT ck_otp_codes_window  CHECK (expires_at > issued_at)
);

CREATE INDEX ix_otp_codes_user   ON hbh.otp_codes (user_id, issued_at DESC);
CREATE INDEX ix_otp_codes_center ON hbh.otp_codes (center_id);
CREATE INDEX ix_otp_codes_live   ON hbh.otp_codes (user_id) WHERE consumed_at IS NULL;

CREATE TABLE hbh.auth_sessions (
  auth_session_id bigint      GENERATED ALWAYS AS IDENTITY,
  center_id       integer     NOT NULL,
  user_id         integer     NOT NULL,
  token_hash      bytea       NOT NULL,
  issued_at       timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL,
  last_seen_at    timestamptz,
  revoked_at      timestamptz,
  revoked_reason  text,
  client_ip       inet,
  user_agent      text,
  CONSTRAINT pk_auth_sessions PRIMARY KEY (auth_session_id),
  CONSTRAINT fk_auth_sessions_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_auth_sessions_user   FOREIGN KEY (user_id)   REFERENCES hbh.users (user_id),
  CONSTRAINT uq_auth_sessions_token  UNIQUE (token_hash),
  CONSTRAINT ck_auth_sessions_window CHECK (expires_at > issued_at)
);

CREATE INDEX ix_auth_sessions_user   ON hbh.auth_sessions (user_id, issued_at DESC);
CREATE INDEX ix_auth_sessions_center ON hbh.auth_sessions (center_id);

-- =====================================================================
-- IDENTITY, PERMISSIONS, AND THE CHILD GATE
-- =====================================================================

CREATE OR REPLACE FUNCTION hbh.current_user_id()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT u.user_id
  FROM   hbh.users u
  WHERE  lower(u.username) = lower(hbh.current_portal_user())
  AND    u.active_flg
  AND    u.status = 'ACTIVE'
$$;

-- Fails closed: with no identity, current_user_id() is NULL, the join
-- matches nothing, and EXISTS is false. Never NULL, never true.
CREATE OR REPLACE FUNCTION hbh.has_permission(p_code text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM   hbh.user_roles ur
    JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id AND rp.active_flg
    JOIN   hbh.permissions p       ON p.permission_id = rp.permission_id AND p.active_flg
    JOIN   hbh.roles r             ON r.role_id = ur.role_id AND r.active_flg
    WHERE  ur.user_id = hbh.current_user_id()
    AND    ur.active_flg
    AND    p.code = p_code
  )
$$;

-- ---------------------------------------------------------------------
-- The gate.
--
-- This is the single rule that stops a parent reaching another child by
-- editing a URL. It is enforced HERE, inside the policy, and never by a
-- condition on a page.
--
-- SECURITY DEFINER is required, not convenient: the policy on children
-- calls this function, and this function reads children. Without it,
-- Postgres raises "infinite recursion detected in policy".
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.can_access_child(p_child_id integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT EXISTS (
    -- Staff or therapist holding CHILD.VIEW_ALL, in the child's centre.
    SELECT 1
    FROM   hbh.users u
    JOIN   hbh.children c ON c.child_id = p_child_id AND c.center_id = u.center_id
    WHERE  u.user_id = hbh.current_user_id()
    AND    u.user_type IN ('STAFF','THERAPIST')
    AND    hbh.has_permission('CHILD.VIEW_ALL')

    UNION ALL

    -- A guardian, but only for a child actually linked to them.
    SELECT 1
    FROM   hbh.guardian_children gc
    JOIN   hbh.guardians g ON g.guardian_id = gc.guardian_id AND g.active_flg
    WHERE  gc.child_id = p_child_id
    AND    gc.active_flg
    AND    g.user_id = hbh.current_user_id()
  )
$$;

COMMENT ON FUNCTION hbh.can_access_child(integer) IS
  'The child access gate. A guardian reaches only children linked to them; staff need CHILD.VIEW_ALL and the same centre.';

-- =====================================================================
-- ONE-TIME CODES
--
-- THE COUNTER PROBLEM - read this before changing either function.
--
-- Postgres has no autonomous transactions. A function that increments
-- an attempt counter and then RAISES loses the increment when the
-- transaction unwinds - so a wrong code would cost the attacker
-- nothing and the code could be guessed without limit.
--
-- Therefore verify_otp NEVER raises for a wrong code. It records the
-- attempt, returns a status, and lets the caller commit. Raising is
-- reserved for conditions where nothing needed to be remembered.
-- =====================================================================

-- Cryptographically random digits. random() is not suitable here: it is
-- seeded and predictable, and this value is a credential.
CREATE OR REPLACE FUNCTION hbh.random_digits(p_len integer)
RETURNS text
LANGUAGE sql
VOLATILE
AS $$
  SELECT lpad(
    ((('x' || encode(public.gen_random_bytes(6), 'hex'))::bit(48)::bigint)
      % (10::bigint ^ p_len)::bigint)::text,
    p_len, '0')
$$;

CREATE OR REPLACE FUNCTION hbh.param(p_center_id integer, p_code text, p_default text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT coalesce(
    (SELECT param_value FROM hbh.sys_params
      WHERE param_code = p_code AND active_flg AND center_id = p_center_id),
    (SELECT param_value FROM hbh.sys_params
      WHERE param_code = p_code AND active_flg AND center_id IS NULL),
    p_default)
$$;

CREATE OR REPLACE FUNCTION hbh.request_otp(p_mobile text)
RETURNS TABLE (ok boolean, reason text, code text, expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_user    hbh.users%ROWTYPE;
  l_len     integer;
  l_ttl     integer;
  l_resend  integer;
  l_last    timestamptz;
  l_code    text;
  l_expires timestamptz;
BEGIN
  SELECT * INTO l_user
  FROM   hbh.users u
  WHERE  u.mobile = p_mobile AND u.active_flg
  ORDER  BY u.user_id
  LIMIT  1;

  IF NOT FOUND THEN
    -- The API must NOT pass this straight to the screen: it tells an
    -- outsider which numbers are registered. It decides the wording.
    RETURN QUERY SELECT false, 'NOT_REGISTERED', NULL::text, NULL::timestamptz;
    RETURN;
  END IF;

  IF l_user.status <> 'ACTIVE' THEN
    RETURN QUERY SELECT false, 'USER_LOCKED', NULL::text, NULL::timestamptz;
    RETURN;
  END IF;

  l_len    := hbh.param(l_user.center_id, 'OTP_LENGTH',         '6')::integer;
  l_ttl    := hbh.param(l_user.center_id, 'OTP_TTL_MINUTES',   '15')::integer;
  l_resend := hbh.param(l_user.center_id, 'OTP_RESEND_SECONDS','60')::integer;

  SELECT max(o.issued_at) INTO l_last
  FROM   hbh.otp_codes o
  WHERE  o.user_id = l_user.user_id AND o.purpose = 'LOGIN';

  IF l_last IS NOT NULL AND l_last > now() - make_interval(secs => l_resend) THEN
    RETURN QUERY SELECT false, 'RESEND_TOO_SOON', NULL::text, NULL::timestamptz;
    RETURN;
  END IF;

  -- A new code invalidates any code still outstanding, so two codes are
  -- never live for one account at the same time.
  UPDATE hbh.otp_codes o
     SET consumed_at = now()
   WHERE o.user_id = l_user.user_id AND o.consumed_at IS NULL;

  l_code    := hbh.random_digits(l_len);
  l_expires := now() + make_interval(mins => l_ttl);

  -- Only the hash is stored. The plaintext leaves in the return value,
  -- goes to the SMS gateway, and is never written anywhere.
  INSERT INTO hbh.otp_codes (center_id, user_id, mobile, code_hash, purpose, expires_at)
  VALUES (l_user.center_id, l_user.user_id, p_mobile,
          public.crypt(l_code, public.gen_salt('bf', 8)), 'LOGIN', l_expires);

  RETURN QUERY SELECT true, 'OK', l_code, l_expires;
END
$$;

CREATE OR REPLACE FUNCTION hbh.verify_otp(p_mobile text, p_code text)
RETURNS TABLE (ok boolean, reason text, user_id integer, attempts_left integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_user hbh.users%ROWTYPE;
  l_otp  hbh.otp_codes%ROWTYPE;
  l_max  integer;
BEGIN
  SELECT * INTO l_user
  FROM   hbh.users u
  WHERE  u.mobile = p_mobile AND u.active_flg
  ORDER  BY u.user_id
  LIMIT  1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'NO_PENDING_CODE', NULL::integer, NULL::integer;
    RETURN;
  END IF;

  IF l_user.status <> 'ACTIVE' THEN
    RETURN QUERY SELECT false, 'USER_LOCKED', NULL::integer, NULL::integer;
    RETURN;
  END IF;

  l_max := hbh.param(l_user.center_id, 'OTP_MAX_ATTEMPTS', '5')::integer;

  -- FOR UPDATE: two requests arriving together must not each see four
  -- attempts used and each allow a fifth.
  SELECT * INTO l_otp
  FROM   hbh.otp_codes o
  WHERE  o.user_id = l_user.user_id
  AND    o.consumed_at IS NULL
  ORDER  BY o.issued_at DESC
  LIMIT  1
  FOR    UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'NO_PENDING_CODE', NULL::integer, NULL::integer;
    RETURN;
  END IF;

  IF l_otp.expires_at <= now() THEN
    UPDATE hbh.otp_codes SET consumed_at = now() WHERE otp_id = l_otp.otp_id;
    RETURN QUERY SELECT false, 'EXPIRED', NULL::integer, NULL::integer;
    RETURN;
  END IF;

  IF l_otp.attempts >= l_max THEN
    UPDATE hbh.otp_codes SET consumed_at = now() WHERE otp_id = l_otp.otp_id;
    UPDATE hbh.users SET status = 'LOCKED' WHERE hbh.users.user_id = l_user.user_id;
    RETURN QUERY SELECT false, 'TOO_MANY_ATTEMPTS', NULL::integer, 0;
    RETURN;
  END IF;

  IF l_otp.code_hash <> public.crypt(p_code, l_otp.code_hash) THEN
    -- The increment must survive. This is why we return instead of
    -- raising: an exception here would roll the counter back and make
    -- the attempt free.
    UPDATE hbh.otp_codes SET attempts = l_otp.attempts + 1 WHERE otp_id = l_otp.otp_id;
    RETURN QUERY SELECT false, 'WRONG_CODE', NULL::integer, (l_max - l_otp.attempts - 1);
    RETURN;
  END IF;

  -- Single use.
  UPDATE hbh.otp_codes SET consumed_at = now() WHERE otp_id = l_otp.otp_id;
  RETURN QUERY SELECT true, 'OK', l_user.user_id, (l_max - l_otp.attempts);
END
$$;

-- =====================================================================
-- LOGIN SESSIONS
--
-- The token is high-entropy and generated by the API, so SHA-256 is
-- enough at rest - bcrypt guards low-entropy secrets, and a one-time
-- code is exactly that, which is why the two are hashed differently.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.create_auth_session(
  p_user_id    integer,
  p_token      text,
  p_client_ip  inet DEFAULT NULL,
  p_user_agent text DEFAULT NULL)
RETURNS TABLE (auth_session_id bigint, expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_user hbh.users%ROWTYPE;
  l_ttl  integer;
BEGIN
  SELECT * INTO l_user FROM hbh.users u WHERE u.user_id = p_user_id AND u.active_flg AND u.status = 'ACTIVE';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'cannot open a session for an inactive user %', p_user_id
      USING ERRCODE = 'HB011';
  END IF;

  l_ttl := hbh.param(l_user.center_id, 'SESSION_TTL_MINUTES', '480')::integer;

  RETURN QUERY
  INSERT INTO hbh.auth_sessions (center_id, user_id, token_hash, expires_at, client_ip, user_agent)
  VALUES (l_user.center_id, p_user_id,
          public.digest(p_token, 'sha256'),
          now() + make_interval(mins => l_ttl),
          p_client_ip, p_user_agent)
  RETURNING hbh.auth_sessions.auth_session_id, hbh.auth_sessions.expires_at;
END
$$;

CREATE OR REPLACE FUNCTION hbh.resolve_auth_session(p_token text)
RETURNS TABLE (ok boolean, reason text, username text, user_id integer, center_id integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_row record;
BEGIN
  SELECT s.auth_session_id, s.expires_at, s.revoked_at, u.username, u.user_id, u.center_id, u.status, u.active_flg
    INTO l_row
  FROM   hbh.auth_sessions s
  JOIN   hbh.users u ON u.user_id = s.user_id
  WHERE  s.token_hash = public.digest(p_token, 'sha256');

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'NO_SESSION', NULL::text, NULL::integer, NULL::integer;
    RETURN;
  END IF;
  IF l_row.revoked_at IS NOT NULL THEN
    RETURN QUERY SELECT false, 'REVOKED', NULL::text, NULL::integer, NULL::integer;
    RETURN;
  END IF;
  IF l_row.expires_at <= now() THEN
    RETURN QUERY SELECT false, 'EXPIRED', NULL::text, NULL::integer, NULL::integer;
    RETURN;
  END IF;
  IF NOT l_row.active_flg OR l_row.status <> 'ACTIVE' THEN
    -- Suspending an account takes effect on the next request, not at
    -- the next login. A live session is not a licence.
    RETURN QUERY SELECT false, 'USER_LOCKED', NULL::text, NULL::integer, NULL::integer;
    RETURN;
  END IF;

  UPDATE hbh.auth_sessions SET last_seen_at = now() WHERE auth_session_id = l_row.auth_session_id;
  RETURN QUERY SELECT true, 'OK', l_row.username, l_row.user_id, l_row.center_id;
END
$$;

CREATE OR REPLACE FUNCTION hbh.revoke_auth_session(p_token text, p_reason text DEFAULT 'LOGOUT')
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_n integer;
BEGIN
  UPDATE hbh.auth_sessions
     SET revoked_at = now(), revoked_reason = p_reason
   WHERE token_hash = public.digest(p_token, 'sha256')
     AND revoked_at IS NULL;
  GET DIAGNOSTICS l_n = ROW_COUNT;
  RETURN l_n > 0;
END
$$;

-- =====================================================================
-- ATTEMPT AUDIT - written outside the caller's transaction
--
-- See D-1. A LOGIN or DENY record must survive a rollback, because the
-- attempt happened whether or not the transaction that noticed it did.
-- dblink opens a second connection so the write commits on its own.
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA public;

CREATE OR REPLACE FUNCTION hbh.audit_attempt(
  p_action    text,
  p_center_id integer,
  p_actor     text,
  p_detail    text,
  p_client_ip inet DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF p_action NOT IN ('LOGIN','DENY','READ') THEN
    RAISE EXCEPTION 'audit_attempt is for attempt records only, not %', p_action
      USING ERRCODE = 'HB012';
  END IF;

  -- The handler wraps ONLY the outbound write.
  --
  -- It used to wrap the whole body, and swallowed the HB012 raised
  -- above along with everything else: a caller passing a change action
  -- got a warning in the server log and a successful return. A
  -- WHEN OTHERS that covers more than the one thing which may
  -- legitimately fail will hide a real defect sooner or later - and
  -- this one hid a defect in the very check meant to catch misuse.
  BEGIN
    PERFORM public.dblink_exec(
      -- user= is required. Without it libpq connects as the server's OS
      -- user, "postgres", a role this cluster does not have because the
      -- owner here is hbh_owner. The failure came back as 08001
      -- "could not establish connection", which reads like a network
      -- problem and is nothing of the kind.
      'dbname=' || current_database() || ' user=' || current_user,
      format(
        'INSERT INTO hbh.audit_log (center_id, table_name, action, changed_by, detail, client_ip)
         VALUES (%s, %L, %L, %L, %L, %s)',
        coalesce(p_center_id::text, 'NULL'),
        'auth', p_action, p_actor, p_detail,
        CASE WHEN p_client_ip IS NULL THEN 'NULL' ELSE quote_literal(p_client_ip::text) || '::inet' END));
  EXCEPTION WHEN OTHERS THEN
    -- An audit that cannot be written must never take the request down
    -- with it, but it must not vanish either. The message reaches the
    -- server log, where the operator sees it.
    RAISE WARNING 'audit_attempt could not write: % %', SQLSTATE, SQLERRM;
  END;
END
$$;

-- =====================================================================
-- TRIGGERS
-- =====================================================================
CREATE TRIGGER trg_children_touch           BEFORE UPDATE ON hbh.children           FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_guardians_touch          BEFORE UPDATE ON hbh.guardians          FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_guardian_children_touch  BEFORE UPDATE ON hbh.guardian_children  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_roles_touch              BEFORE UPDATE ON hbh.roles              FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_permissions_touch        BEFORE UPDATE ON hbh.permissions        FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_user_roles_touch         BEFORE UPDATE ON hbh.user_roles         FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_role_permissions_touch   BEFORE UPDATE ON hbh.role_permissions   FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_number_series_touch      BEFORE UPDATE ON hbh.number_series      FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

CREATE TRIGGER trg_children_audit          AFTER INSERT OR UPDATE OR DELETE ON hbh.children          FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('child_id');
CREATE TRIGGER trg_guardians_audit         AFTER INSERT OR UPDATE OR DELETE ON hbh.guardians         FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('guardian_id');
CREATE TRIGGER trg_guardian_children_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.guardian_children FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('child_id');
CREATE TRIGGER trg_user_roles_audit        AFTER INSERT OR UPDATE OR DELETE ON hbh.user_roles        FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('user_id');

-- =====================================================================
-- ROW LEVEL SECURITY
-- =====================================================================
ALTER TABLE hbh.number_series      ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.permissions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.roles              ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.role_permissions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.user_roles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.children           ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.guardians          ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.guardian_children  ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.otp_codes          ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.auth_sessions      ENABLE ROW LEVEL SECURITY;

-- The gate, applied.
CREATE POLICY p_children_select ON hbh.children
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.can_access_child(child_id));

-- A guardian sees their own record; staff with CHILD.VIEW_ALL see the
-- centre's guardians.
CREATE POLICY p_guardians_select ON hbh.guardians
  FOR SELECT TO hbh_app
  USING (
    center_id = hbh.current_center_id()
    AND active_flg
    AND (user_id = hbh.current_user_id() OR hbh.has_permission('CHILD.VIEW_ALL'))
  );

CREATE POLICY p_guardian_children_select ON hbh.guardian_children
  FOR SELECT TO hbh_app
  USING (active_flg AND hbh.can_access_child(child_id));

CREATE POLICY p_roles_select ON hbh.roles
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg);

CREATE POLICY p_permissions_select ON hbh.permissions
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL AND active_flg);

CREATE POLICY p_role_permissions_select ON hbh.role_permissions
  FOR SELECT TO hbh_app
  USING (active_flg AND EXISTS (
    SELECT 1 FROM hbh.roles r
    WHERE r.role_id = hbh.role_permissions.role_id
      AND r.center_id = hbh.current_center_id()));

-- A user sees their own role assignments and nobody else's.
CREATE POLICY p_user_roles_select ON hbh.user_roles
  FOR SELECT TO hbh_app
  USING (active_flg AND user_id = hbh.current_user_id());

-- number_series, otp_codes and auth_sessions get NO policy and no
-- grant. They are reachable only through the functions above.

-- =====================================================================
-- GRANTS
-- =====================================================================
GRANT SELECT ON hbh.children, hbh.guardians, hbh.guardian_children,
                hbh.roles, hbh.permissions, hbh.role_permissions, hbh.user_roles
  TO hbh_app;

REVOKE ALL ON FUNCTION hbh.request_otp(text)                              FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.verify_otp(text, text)                         FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.create_auth_session(integer, text, inet, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.resolve_auth_session(text)                     FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.revoke_auth_session(text, text)                FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.can_access_child(integer)                      FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.has_permission(text)                           FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.current_user_id()                              FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.next_number(integer, text)                     FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.audit_attempt(text, integer, text, text, inet) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.param(integer, text, text)                     FROM PUBLIC;

GRANT EXECUTE ON FUNCTION hbh.request_otp(text)                              TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.verify_otp(text, text)                         TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.create_auth_session(integer, text, inet, text) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.resolve_auth_session(text)                     TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.revoke_auth_session(text, text)                TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.can_access_child(integer)                      TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.has_permission(text)                           TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.current_user_id()                              TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.next_number(integer, text)                     TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.audit_attempt(text, integer, text, text, inet) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.param(integer, text, text)                     TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0002');
