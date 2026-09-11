-- =====================================================================
-- Hand By Hand (new) - migration 0097: a NULL code stops being a
-- password.
--
-- WHAT WAS WRONG, exactly, and it is worth reading slowly.
--
--   IF l_otp.code_hash <> public.crypt(p_code, l_otp.code_hash) THEN
--       ... record the attempt, return WRONG_CODE ...
--   END IF;
--   -- fall through: the code was right
--
-- public.crypt(NULL, hash) is NULL. `hash <> NULL` is not false, it is
-- UNKNOWN. `IF UNKNOWN THEN` does not execute, so the wrong-code branch
-- is SKIPPED - and control falls through to the lines that consume the
-- code and return success. Demonstrated on this database:
--
--   SELECT ok, reason, user_id FROM hbh.verify_otp('015...', NULL);
--   --  t | OK | 935
--
-- A NULL code authenticated as the account holder. Every other control
-- on this path held - the code was hashed, it had not expired, the
-- attempt ceiling was intact - and none of them was reached.
--
-- WAS IT REACHABLE. Not through the HTTP API today:
-- handleVerifyOTP refuses an empty code and refuses anything that is not
-- all digits, so p_code is always a non-empty string of digits by the
-- time the database sees it. That is why it has never been exploited,
-- and it is ALSO why it survived - the defect is invisible from the one
-- direction anybody looks.
--
-- WHY IT IS FIXED ANYWAY, rather than written down as theoretical. The
-- protection lives in the transport layer, and the whole of rule 4 of
-- this project is that a check in the handler is the weaker copy of the
-- rule: a second client, a scheduled job, an operator at psql, a JSON
-- binding that starts allowing null, or a future handler that trusts the
-- database to say no - any one of them turns this from a curiosity into
-- a way to sign in as any parent whose number is known. The function
-- that owns the decision has to make it.
--
-- THE FIX IS TWO LINES AND BOTH ARE DELIBERATE:
--
--   1. A NULL or blank code is refused up front, as WRONG_CODE, WITH
--      THE ATTEMPT COUNTED. Not as a validation error and not silently:
--      an attacker who can send NULL can send it five times, and it
--      should cost the same as five wrong guesses.
--   2. The comparison becomes IS DISTINCT FROM, which is false-or-true
--      and never unknown. Belt and braces: if a future edit removes the
--      guard, the comparison itself no longer fails open.
--
-- The function still RETURNS rather than RAISES for a wrong code. That
-- is not style - Postgres has no autonomous transactions, so an
-- exception would roll back the attempt counter it had just incremented
-- and make guessing free. See THE COUNTER PROBLEM in migration 0002.
--
-- Nothing else in the function changes.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0097') THEN
    RAISE EXCEPTION 'migration 0097 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0096') THEN
    RAISE EXCEPTION 'migration 0096 must be applied first';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION hbh.verify_otp(p_mobile text, p_code text)
RETURNS TABLE (ok boolean, reason text, user_id integer, attempts_left integer)
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

  -- ADDED BY 0097. A NULL or blank code is a wrong code, and it COSTS AN
  -- ATTEMPT like any other. Refusing it as a validation error instead
  -- would leave an unlimited supply of free guesses to whoever found
  -- this door - and there is nothing to validate here anyway: the shape
  -- of a code is OTP_LENGTH, a parameter that can change while one is
  -- outstanding, which is why the handler checks only that it is digits.
  IF p_code IS NULL OR btrim(p_code) = '' THEN
    UPDATE hbh.otp_codes SET attempts = l_otp.attempts + 1 WHERE otp_id = l_otp.otp_id;
    RETURN QUERY SELECT false, 'WRONG_CODE', NULL::integer, (l_max - l_otp.attempts - 1);
    RETURN;
  END IF;

  -- IS DISTINCT FROM, not <>. The three-valued comparison is what made a
  -- NULL code fall through to success: `hash <> NULL` is UNKNOWN, and an
  -- IF on UNKNOWN does not execute. This form is false or true and never
  -- unknown, so the guard above is defence in depth rather than the only
  -- thing standing between a stranger and an account.
  IF l_otp.code_hash IS DISTINCT FROM public.crypt(p_code, l_otp.code_hash) THEN
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
$fn$;

REVOKE ALL ON FUNCTION hbh.verify_otp(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.verify_otp(text, text) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0097');
