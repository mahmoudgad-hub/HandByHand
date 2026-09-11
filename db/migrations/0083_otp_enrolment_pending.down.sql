-- =====================================================================
-- 0083 down - the sign-in screen goes back to saying nothing
--
-- THIS RESTORES THE OLD FUNCTION EXACTLY, including the behaviour the
-- owner asked to have changed. That is what a down file is for: it
-- returns the state that was there, not the state somebody preferred.
-- A "corrected" revert is a revert that lies about what it undoes.
--
-- REVERT THE API FIRST, or the other way round from the up: with this
-- applied and a service that still expects ENROLMENT_PENDING, the
-- portal shows nothing where it used to show the pending message. The
-- schema is the one that waits here.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION hbh.request_otp(p_mobile text)
RETURNS TABLE(ok boolean, reason text, code text, expires_at timestamptz)
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

  RETURN QUERY SELECT true, 'OK', l_code, l_expires;
END
$fn$;

DROP INDEX IF EXISTS hbh.ix_enrolment_applications_parent_mobile;

DELETE FROM hbh.schema_migrations WHERE version = '0083';
