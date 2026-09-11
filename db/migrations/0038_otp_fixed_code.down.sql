-- =====================================================================
-- 0038 down - restore random login codes.
--
-- The function body below is copied from 0002 unchanged, so reverting
-- cannot quietly reintroduce an older or a newer variant of anything
-- else in it. The parameter row goes too: leaving it behind would make
-- a later re-application of this migration take effect the instant it
-- ran, with nobody having asked for a fixed code.
-- =====================================================================

-- Soft, like every other delete here (rule 3). hbh.param already tests
-- active_flg, so this takes effect on the next call with no restart and
-- the row survives to say a fixed code was once configured, and when.
UPDATE hbh.sys_params
   SET active_flg = false,
       deleted_at = now(),
       updated_at = now()
 WHERE param_code = 'OTP_FIXED_CODE' AND active_flg;

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

REVOKE ALL ON FUNCTION hbh.request_otp(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.request_otp(text) TO hbh_app;
