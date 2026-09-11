-- =====================================================================
-- 0038 - a fixed login code for test environments
--
-- WHAT THIS IS FOR
-- A staging instance has no SMS gateway, so a tester cannot receive a
-- code. OTP_ECHO already returns it in the response body, but a code
-- that changes every request cannot be written into a test script or
-- handed to somebody trying the portal on a phone.
--
-- WHAT IT COSTS
-- Where this parameter is set, the one-time code is not one-time and
-- not secret: anybody who knows a mobile number signs in as its owner.
-- It removes the whole of the OTP control, not part of it.
--
-- WHY IT IS A PARAMETER AND NOT A BUILD FLAG
-- Rule 2 of this project: the rule lives in PL/pgSQL. A flag in Go
-- would put the same decision in the layer that is supposed to carry
-- answers rather than make them, and the database would have no idea
-- its authentication had been weakened.
--
-- THE SAFEGUARDS, AND THEIR LIMIT
--   * The row is NOT in db/seed. A database that has never been told
--     otherwise generates random codes: absent means random, and the
--     default argument to hbh.param says so at the call site.
--   * The value must be exactly OTP_LENGTH digits or it is ignored,
--     so a half-finished edit falls back to random rather than to a
--     code nobody can guess but nobody can type either.
--   * hbh.otp_codes still stores only the hash, still expires, still
--     counts attempts, and a new request still invalidates the old
--     code. This changes what the code IS, not how it is handled.
--
-- The limit is real and worth stating plainly: nothing here can tell a
-- production database from a staging one. If this row is ever inserted
-- in production, logins stop being protected and no test will say so.
-- Retiring the row restores random codes immediately, with no restart,
-- and leaves the evidence that a fixed code was once configured:
--
--   UPDATE hbh.sys_params SET active_flg = false, deleted_at = now()
--    WHERE param_code = 'OTP_FIXED_CODE';
-- =====================================================================

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
$$;

REVOKE ALL ON FUNCTION hbh.request_otp(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.request_otp(text) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0038');
