-- =====================================================================
-- Hand By Hand (new) - migration 0011: staff sign-in, and the periodic
-- work that had nothing running it.
--
-- Two gaps, both found by asking what was missing rather than by a
-- failing test.
--
-- 1. NOBODY ON THE STAFF COULD SIGN IN.
--    hbh.users had no password column at all. The only way in was the
--    one-time code, which is right for a family - a parent should not
--    be made to keep a password for a portal they open twice a month -
--    and wrong for a receptionist who signs in every morning and whose
--    phone is not the centre's to depend on.
--
--    So: passwords for STAFF and THERAPIST, one-time codes for
--    GUARDIAN, and the schema refuses to mix them.
--
-- 2. expire_packages WAS WRITTEN AND NOTHING CALLED IT.
--    A correct, tested function that never runs. Packages stayed ACTIVE
--    past their expiry until somebody happened to try to use one, and
--    the ledger entry explaining the forfeited sessions was never
--    written.
--
--    The fix is not only a scheduler. It is a RECORD of every run, so
--    "the maintenance is not running" is a question the database can
--    answer instead of a thing nobody notices for a month.
--
-- Error classes added here:
--   HB071  this user type does not sign in with a password
--   HB072  the password is shorter than the centre requires
--   HB073  not permitted to set this password
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0011') THEN
    RAISE EXCEPTION 'migration 0011 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0010') THEN
    RAISE EXCEPTION 'migration 0010 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- STAFF PASSWORDS
-- =====================================================================
ALTER TABLE hbh.users
  ADD COLUMN password_hash    text,
  ADD COLUMN password_set_at  timestamptz,
  ADD COLUMN failed_login_cnt smallint    NOT NULL DEFAULT 0,
  ADD COLUMN locked_until     timestamptz;

-- A guardian signs in with a one-time code and never holds a password.
-- Stated as a constraint so the two mechanisms cannot quietly overlap
-- on one account.
ALTER TABLE hbh.users
  ADD CONSTRAINT ck_users_password CHECK (
    password_hash IS NULL OR user_type IN ('STAFF','THERAPIST'));

ALTER TABLE hbh.users
  ADD CONSTRAINT ck_users_password_stamp CHECK (
    (password_hash IS NULL) = (password_set_at IS NULL));

CREATE INDEX ix_users_locked ON hbh.users (locked_until) WHERE locked_until IS NOT NULL;

-- ---------------------------------------------------------------------
-- Setting one
--
-- The plaintext arrives, is hashed, and is never stored, logged or
-- returned. bcrypt because a password is a low-entropy secret - the
-- same reason the one-time code uses it and the session token does not.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.set_password(p_user_id integer, p_password text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_user hbh.users%ROWTYPE;
  l_min  integer;
BEGIN
  SELECT * INTO l_user FROM hbh.users WHERE user_id = p_user_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such user %', p_user_id USING ERRCODE = 'HB073';
  END IF;

  -- Your own, or somebody holding USER.MANAGE. Nothing else.
  IF hbh.current_user_id() IS DISTINCT FROM p_user_id
     AND NOT hbh.has_permission('USER.MANAGE') THEN
    RAISE EXCEPTION 'not permitted to set the password of user %', p_user_id
      USING ERRCODE = 'HB073';
  END IF;

  IF l_user.user_type NOT IN ('STAFF','THERAPIST') THEN
    RAISE EXCEPTION 'user % signs in with a one-time code, not a password', p_user_id
      USING ERRCODE = 'HB071';
  END IF;

  l_min := hbh.param(l_user.center_id, 'MIN_PASSWORD_LENGTH', '10')::integer;
  IF length(coalesce(p_password, '')) < l_min THEN
    RAISE EXCEPTION 'the password must be at least % characters', l_min
      USING ERRCODE = 'HB072';
  END IF;

  UPDATE hbh.users
     SET password_hash    = public.crypt(p_password, public.gen_salt('bf', 10)),
         password_set_at  = now(),
         failed_login_cnt = 0,
         locked_until     = NULL
   WHERE user_id = p_user_id;
END
$$;

-- ---------------------------------------------------------------------
-- Checking one
--
-- Returns a status and NEVER raises for a wrong password.
--
-- This is the same rule as verify_otp and for the same reason: Postgres
-- has no autonomous transactions, so a function that increments the
-- failure counter and then raises loses the increment when the
-- transaction unwinds - and a password could be guessed without limit.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.verify_password(p_username text, p_password text)
RETURNS TABLE (ok boolean, reason text, user_id integer, attempts_left integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_user hbh.users%ROWTYPE;
  l_max  integer;
  l_lock integer;
BEGIN
  SELECT * INTO l_user FROM hbh.users u
  WHERE lower(u.username) = lower(p_username) AND u.active_flg
  FOR UPDATE;

  -- The same answer for "no such account" and "wrong password", so the
  -- endpoint cannot be used to enumerate who works here.
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'BAD_CREDENTIALS', NULL::integer, NULL::integer; RETURN;
  END IF;

  IF l_user.user_type NOT IN ('STAFF','THERAPIST') OR l_user.password_hash IS NULL THEN
    RETURN QUERY SELECT false, 'NOT_PASSWORD_USER', NULL::integer, NULL::integer; RETURN;
  END IF;

  IF l_user.status <> 'ACTIVE' THEN
    RETURN QUERY SELECT false, 'USER_LOCKED', NULL::integer, NULL::integer; RETURN;
  END IF;

  IF l_user.locked_until IS NOT NULL AND l_user.locked_until > now() THEN
    RETURN QUERY SELECT false, 'TEMPORARILY_LOCKED', NULL::integer, 0; RETURN;
  END IF;

  l_max  := hbh.param(l_user.center_id, 'LOGIN_MAX_ATTEMPTS', '5')::integer;
  l_lock := hbh.param(l_user.center_id, 'LOGIN_LOCK_MINUTES', '15')::integer;

  IF l_user.password_hash <> public.crypt(p_password, l_user.password_hash) THEN
    -- The increment must survive, so this returns rather than raising.
    UPDATE hbh.users
       SET failed_login_cnt = l_user.failed_login_cnt + 1,
           locked_until = CASE WHEN l_user.failed_login_cnt + 1 >= l_max
                               THEN now() + make_interval(mins => l_lock) END
     WHERE hbh.users.user_id = l_user.user_id;

    RETURN QUERY SELECT false,
      CASE WHEN l_user.failed_login_cnt + 1 >= l_max THEN 'TEMPORARILY_LOCKED'
           ELSE 'BAD_CREDENTIALS' END,
      NULL::integer,
      greatest(l_max - l_user.failed_login_cnt - 1, 0);
    RETURN;
  END IF;

  -- A good sign-in clears the count. Five wrong tries spread over a
  -- month must not lock somebody out on an ordinary Tuesday.
  UPDATE hbh.users SET failed_login_cnt = 0, locked_until = NULL
   WHERE hbh.users.user_id = l_user.user_id;

  RETURN QUERY SELECT true, 'OK', l_user.user_id, l_max;
END
$$;

REVOKE ALL ON FUNCTION hbh.set_password(integer, text)     FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.verify_password(text, text)     FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.set_password(integer, text)  TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.verify_password(text, text)  TO hbh_app;

-- =====================================================================
-- PERIODIC WORK, AND A RECORD THAT IT HAPPENED
--
-- The record is the point. A scheduler that stops is invisible; a table
-- with a last-run time is not, and v_maintenance_health turns "is the
-- maintenance running" into one query.
-- =====================================================================
CREATE TABLE hbh.maintenance_runs (
  run_id           bigint      GENERATED ALWAYS AS IDENTITY,
  started_at       timestamptz NOT NULL DEFAULT now(),
  finished_at      timestamptz,
  packages_expired integer     NOT NULL DEFAULT 0,
  streams_closed   integer     NOT NULL DEFAULT 0,
  detail           text,
  run_by           text        NOT NULL DEFAULT hbh.current_app_user(),
  CONSTRAINT pk_maintenance_runs PRIMARY KEY (run_id),
  CONSTRAINT ck_maint_window CHECK (finished_at IS NULL OR finished_at >= started_at)
);

CREATE INDEX ix_maint_started ON hbh.maintenance_runs (started_at DESC);

ALTER TABLE hbh.maintenance_runs ENABLE ROW LEVEL SECURITY;
-- No policy and no grant: operational metadata, not application data.

CREATE OR REPLACE FUNCTION hbh.run_maintenance()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_run      bigint;
  l_expired  integer := 0;
  l_streams  integer := 0;
  l_detail   text    := '';
BEGIN
  INSERT INTO hbh.maintenance_runs DEFAULT VALUES RETURNING run_id INTO l_run;

  -- Each task in its own handler. One failing task must not stop the
  -- others, and must not vanish either - the reason is recorded on the
  -- run, where somebody reading the table will see it.
  BEGIN
    l_expired := hbh.expire_packages();
  EXCEPTION WHEN OTHERS THEN
    l_detail := l_detail || 'expire_packages: ' || SQLSTATE || ' ' || SQLERRM || '; ';
  END;

  BEGIN
    -- A stream token outliving its session is a window into a room the
    -- child has left. close_session on its own does not revoke them.
    UPDATE hbh.stream_tokens t
       SET revoked_at = now()
     WHERE t.revoked_at IS NULL
       AND t.expires_at > now()
       AND EXISTS (SELECT 1 FROM hbh.therapy_sessions s
                   WHERE s.session_id = t.session_id AND s.status <> 'IN_PROGRESS');
    GET DIAGNOSTICS l_streams = ROW_COUNT;

    UPDATE hbh.stream_views v
       SET ended_at = now()
     WHERE v.ended_at IS NULL
       AND EXISTS (SELECT 1 FROM hbh.therapy_sessions s
                   WHERE s.session_id = v.session_id AND s.status <> 'IN_PROGRESS');
  EXCEPTION WHEN OTHERS THEN
    l_detail := l_detail || 'stream cleanup: ' || SQLSTATE || ' ' || SQLERRM || '; ';
  END;

  UPDATE hbh.maintenance_runs
     SET finished_at      = now(),
         packages_expired = l_expired,
         streams_closed   = l_streams,
         detail           = nullif(l_detail, '')
   WHERE run_id = l_run;

  RETURN l_run;
END
$$;

REVOKE ALL ON FUNCTION hbh.run_maintenance() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.run_maintenance() TO hbh_app;

-- One query answers "is the maintenance running".
CREATE VIEW hbh.v_maintenance_health
WITH (security_invoker = true)
AS
SELECT (SELECT max(finished_at) FROM hbh.maintenance_runs)              AS last_success_at,
       (SELECT count(*) FROM hbh.maintenance_runs
        WHERE finished_at IS NULL AND started_at < now() - interval '1 hour') AS stuck_runs,
       (SELECT count(*) FROM hbh.maintenance_runs
        WHERE detail IS NOT NULL AND started_at > now() - interval '1 day')   AS runs_with_errors_today,
       CASE
         WHEN (SELECT max(finished_at) FROM hbh.maintenance_runs) IS NULL THEN true
         WHEN (SELECT max(finished_at) FROM hbh.maintenance_runs)
              < now() - make_interval(mins => hbh.param(NULL, 'MAINTENANCE_MAX_AGE_MIN', '120')::integer)
           THEN true
         ELSE false
       END AS is_stale;

COMMENT ON VIEW hbh.v_maintenance_health IS
  'Whether the periodic work is actually running. is_stale is true on a database where it never has.';

-- =====================================================================
-- PARAMETERS
-- =====================================================================
INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar) VALUES
  (NULL, 'MIN_PASSWORD_LENGTH',      '10',  'NUMBER', 'أقل طول لكلمة مرور موظّف'),
  (NULL, 'LOGIN_MAX_ATTEMPTS',       '5',   'NUMBER', 'محاولات الدخول قبل القفل المؤقّت'),
  (NULL, 'LOGIN_LOCK_MINUTES',       '15',  'NUMBER', 'مدة القفل المؤقّت بالدقائق'),
  (NULL, 'MAINTENANCE_MAX_AGE_MIN',  '120', 'NUMBER', 'بعدها تُعتبر المهام الدورية متوقّفة')
ON CONFLICT (center_id, param_code) DO NOTHING;

INSERT INTO hbh.convention_exemptions (table_name, rule_code, reason) VALUES
  ('maintenance_runs', 'AUDIT_COLUMNS',
   'An operational log. started_at, finished_at and run_by are its attribution, and a row is written once and completed once.'),
  ('maintenance_runs', 'SOFT_DELETE',
   'A run happened or it did not. A deactivated run would make the staleness view lie about the last successful one.');

INSERT INTO hbh.schema_migrations (version) VALUES ('0011');
