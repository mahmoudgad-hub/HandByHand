-- =====================================================================
-- 0095 down - request_otp stops reporting the centre.
--
-- The old four-column shape is restored verbatim from 0083. The DROP is
-- required rather than tidy: a return type cannot be replaced in place.
--
-- WHAT BREAKS IF THIS IS RUN WITHOUT PUTTING THE OLD API BACK. The login
-- handler scans five columns; against this function it will scan four
-- and fail, and every OTP request becomes a 500. That is the direction
-- CLAUDE.md calls "the schema waits": this down migration must run
-- AFTER the service is rolled back, not before.
-- =====================================================================

DROP FUNCTION IF EXISTS hbh.request_otp(text);

CREATE FUNCTION hbh.request_otp(p_mobile text)
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
  l_appl    text;
BEGIN
  SELECT * INTO l_user
  FROM   hbh.users u
  WHERE  u.mobile = p_mobile AND u.active_flg
  ORDER  BY u.user_id
  LIMIT  1;

  IF NOT FOUND THEN
    -- No account. Before answering "we do not know you", ask whether
    -- they are already waiting on us.
    SELECT a.status INTO l_appl
    FROM   hbh.enrolment_applications a
    WHERE  a.parent_mobile = p_mobile AND a.active_flg
    ORDER  BY a.application_id DESC
    LIMIT  1;

    IF l_appl IN ('NEW', 'CONTACTED', 'ASSESSMENT_BOOKED') THEN
      RETURN QUERY SELECT false, 'ENROLMENT_PENDING', NULL::text, NULL::timestamptz;
      RETURN;
    END IF;

    RETURN QUERY SELECT false, 'NOT_REGISTERED', NULL::text, NULL::timestamptz;
    RETURN;
  END IF;

  IF l_user.status <> 'ACTIVE' THEN
    -- Still withheld. "This number exists but is locked" is a sharper
    -- fact than "this number exists", nobody asked for it, and a locked
    -- family is one the centre is already talking to.
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

  -- The default is the empty string, which is what makes absence mean
  -- random rather than meaning something nobody wrote down.
  l_fixed := hbh.param(l_user.center_id, 'OTP_FIXED_CODE', '');

  IF l_fixed ~ ('^[0-9]{' || l_len || '}$') THEN
    l_code := l_fixed;
  ELSE
    l_code := hbh.random_digits(l_len);
  END IF;

  l_expires := now() + make_interval(mins => l_ttl);

  -- Only the hash is stored. The plaintext leaves in the return value,
  -- goes to the SMS gateway, and is never written anywhere.
  INSERT INTO hbh.otp_codes (center_id, user_id, mobile, code_hash, purpose, expires_at)
  VALUES (l_user.center_id, l_user.user_id, p_mobile,
          public.crypt(l_code, public.gen_salt('bf', 8)), 'LOGIN', l_expires);

  RETURN QUERY SELECT true, 'OK', l_code, l_expires;
END
$fn$;

REVOKE ALL ON FUNCTION hbh.request_otp(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.request_otp(text) TO hbh_app;

DELETE FROM hbh.schema_migrations WHERE version = '0095';
