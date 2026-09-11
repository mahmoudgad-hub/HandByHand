-- =====================================================================
-- 0112 down - back to Egyptian national numbers
--
-- ORDER IS THE POINT OF THIS FILE, and it is the reverse of the up.
-- CLAUDE.md: a down that drops the table before the functions that read
-- it fails, and the whole migration is one transaction, so NOTHING is
-- dropped - the rebuild then silently reuses the old definitions and the
-- correction you just wrote looks like it does not work.
--
-- So: triggers, then constraints, then the functions that call
-- canonical_mobile, then the un-backfill, and only then the table
-- canonical_mobile reads.
--
-- WHAT THIS CANNOT UNDO. A guardian whose number is not Egyptian has no
-- national form in this database to go back to. Their row keeps its
-- E.164 value - ck_guardians_mobile is '^[0-9+]{6,20}$' and still
-- accepts it - and they become unreachable by SMS again, which is the
-- state this migration was written to end. The report at the bottom
-- names them rather than leaving it to be found.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TRIGGER IF EXISTS trg_guardians_mobile_canon  ON hbh.guardians;
DROP TRIGGER IF EXISTS trg_users_mobile_canon      ON hbh.users;
DROP TRIGGER IF EXISTS trg_therapists_mobile_canon ON hbh.therapists;
DROP TRIGGER IF EXISTS trg_enr_mobile_canon        ON hbh.enrolment_applications;

ALTER TABLE hbh.guardians              DROP CONSTRAINT IF EXISTS ck_guardians_mobile_e164;
ALTER TABLE hbh.users                  DROP CONSTRAINT IF EXISTS ck_users_mobile_e164;
ALTER TABLE hbh.therapists             DROP CONSTRAINT IF EXISTS ck_therapists_mobile_e164;
ALTER TABLE hbh.enrolment_applications DROP CONSTRAINT IF EXISTS ck_enr_mobile_e164;

-- ---------------------------------------------------------------------
-- request_otp goes back to five output columns, so it is dropped and
-- recreated rather than replaced: CREATE OR REPLACE cannot change the
-- shape of a returned record.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS hbh.request_otp(text);

CREATE FUNCTION hbh.request_otp(p_mobile text)
RETURNS TABLE(ok boolean, reason text, code text,
              expires_at timestamptz, center_id integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_user    hbh.users%ROWTYPE;
  l_len     integer;
  l_ttl     integer;
  l_resend  integer;
  l_last    timestamptz;
  l_code    text;
  l_fixed   text;
  l_expires timestamptz;
  l_appl    text;
BEGIN
  SELECT * INTO l_user
  FROM   hbh.users u
  WHERE  u.mobile = p_mobile AND u.active_flg
  ORDER  BY u.user_id
  LIMIT  1;

  IF NOT FOUND THEN
    SELECT a.status INTO l_appl
    FROM   hbh.enrolment_applications a
    WHERE  a.parent_mobile = p_mobile AND a.active_flg
    ORDER  BY a.application_id DESC
    LIMIT  1;

    IF l_appl IN ('NEW', 'CONTACTED', 'ASSESSMENT_BOOKED') THEN
      RETURN QUERY SELECT false, 'ENROLMENT_PENDING', NULL::text,
                          NULL::timestamptz, NULL::integer;
      RETURN;
    END IF;

    RETURN QUERY SELECT false, 'NOT_REGISTERED', NULL::text,
                        NULL::timestamptz, NULL::integer;
    RETURN;
  END IF;

  IF l_user.status <> 'ACTIVE' THEN
    RETURN QUERY SELECT false, 'USER_LOCKED', NULL::text,
                        NULL::timestamptz, NULL::integer;
    RETURN;
  END IF;

  l_len    := hbh.param(l_user.center_id, 'OTP_LENGTH',         '6')::integer;
  l_ttl    := hbh.param(l_user.center_id, 'OTP_TTL_MINUTES',   '15')::integer;
  l_resend := hbh.param(l_user.center_id, 'OTP_RESEND_SECONDS','60')::integer;

  SELECT max(o.issued_at) INTO l_last
  FROM   hbh.otp_codes o
  WHERE  o.user_id = l_user.user_id AND o.purpose = 'LOGIN';

  IF l_last IS NOT NULL AND l_last > now() - make_interval(secs => l_resend) THEN
    RETURN QUERY SELECT false, 'RESEND_TOO_SOON', NULL::text,
                        NULL::timestamptz, NULL::integer;
    RETURN;
  END IF;

  UPDATE hbh.otp_codes o
     SET consumed_at = now()
   WHERE o.user_id = l_user.user_id AND o.consumed_at IS NULL;

  l_fixed := hbh.param(l_user.center_id, 'OTP_FIXED_CODE', '');

  IF l_fixed ~ ('^[0-9]{' || l_len || '}$') THEN
    l_code := l_fixed;
  ELSE
    l_code := hbh.random_digits(l_len);
  END IF;

  l_expires := now() + make_interval(mins => l_ttl);

  INSERT INTO hbh.otp_codes (center_id, user_id, mobile, code_hash, purpose, expires_at)
  VALUES (l_user.center_id, l_user.user_id, p_mobile,
          public.crypt(l_code, public.gen_salt('bf', 8)), 'LOGIN', l_expires);

  RETURN QUERY SELECT true, 'OK', l_code, l_expires, l_user.center_id;
END
$fn$;

REVOKE ALL ON FUNCTION hbh.request_otp(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.request_otp(text) TO hbh_app;

CREATE OR REPLACE FUNCTION hbh.verify_otp(p_mobile text, p_code text)
RETURNS TABLE(ok boolean, reason text, user_id integer, attempts_left integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
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

  IF p_code IS NULL OR btrim(p_code) = ''
     OR l_otp.code_hash IS DISTINCT FROM public.crypt(p_code, l_otp.code_hash) THEN
    UPDATE hbh.otp_codes SET attempts = attempts + 1 WHERE otp_id = l_otp.otp_id;
    RETURN QUERY SELECT false, 'WRONG_CODE', NULL::integer,
                        greatest(l_max - (l_otp.attempts + 1), 0);
    RETURN;
  END IF;

  UPDATE hbh.otp_codes SET consumed_at = now() WHERE otp_id = l_otp.otp_id;
  RETURN QUERY SELECT true, 'OK', l_user.user_id, NULL::integer;
END
$fn$;

REVOKE ALL ON FUNCTION hbh.verify_otp(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.verify_otp(text, text) TO hbh_app;

-- ---------------------------------------------------------------------
-- The un-backfill. '+20' back to '0', and only that: the string is
-- rebuilt here rather than by calling canonical_mobile because the
-- function is about to cease to exist, and a down that depends on what
-- it is dismantling is the shape that leaves a database half-way.
-- ---------------------------------------------------------------------
UPDATE hbh.guardians              SET mobile        = '0' || substr(mobile, 4)        WHERE mobile        ~ '^\+201[0-9]{9}$';
UPDATE hbh.users                  SET mobile        = '0' || substr(mobile, 4)        WHERE mobile        ~ '^\+201[0-9]{9}$';
UPDATE hbh.therapists             SET mobile        = '0' || substr(mobile, 4)        WHERE mobile        ~ '^\+201[0-9]{9}$';
UPDATE hbh.enrolment_applications SET parent_mobile = '0' || substr(parent_mobile, 4) WHERE parent_mobile ~ '^\+201[0-9]{9}$';
UPDATE hbh.otp_codes              SET mobile        = '0' || substr(mobile, 4)        WHERE mobile        ~ '^\+201[0-9]{9}$';
UPDATE hbh.sms_outbox             SET destination   = '0' || substr(destination, 4)   WHERE destination   ~ '^\+201[0-9]{9}$';

UPDATE hbh.sys_params
   SET param_value    = '^01[0-9]{9}$',
       description_ar = 'نمط رقم الجوّال المقبول — مصر',
       updated_at     = now(),
       updated_by     = hbh.current_app_user()
 WHERE param_code = 'MOBILE_PATTERN';

DROP FUNCTION IF EXISTS hbh.trg_canonical_mobile();
DROP FUNCTION IF EXISTS hbh.canonical_mobile(text, text);

DROP TABLE IF EXISTS hbh.country_dial_codes;

DO $report$
DECLARE
  n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.guardians WHERE mobile ~ '^\+';
  IF n > 0 THEN
    RAISE WARNING '0112 down: % guardian(s) hold a non-Egyptian number and keep it. They cannot be reached by SMS on this schema version.', n;
  END IF;
END
$report$;

DELETE FROM hbh.schema_migrations WHERE version = '0112';
