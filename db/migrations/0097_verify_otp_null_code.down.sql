-- =====================================================================
-- 0097 down - restores the 0002 body.
--
-- READ THIS BEFORE RUNNING IT. The function this restores ACCEPTS A NULL
-- CODE AS A VALID ONE: crypt(NULL, hash) is NULL, `hash <> NULL` is
-- UNKNOWN, and the wrong-code branch is skipped. Anything that can call
-- hbh.verify_otp with a NULL second argument signs in as the owner of
-- the number.
--
-- It exists because every migration in this project has a down, and
-- because a down that silently differs from the up is worse than one
-- that is dangerous and says so. It should not be run.
-- =====================================================================

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

REVOKE ALL ON FUNCTION hbh.verify_otp(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.verify_otp(text, text) TO hbh_app;

DELETE FROM hbh.schema_migrations WHERE version = '0097';
