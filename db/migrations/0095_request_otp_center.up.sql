-- =====================================================================
-- Hand By Hand (new) - migration 0095: request_otp says which centre.
--
-- THE BUG THIS FIXES, AND IT IS A GOOD ONE.
--
-- 0094 gave the login handler a delivery path, and the handler needed a
-- centre for the hbh.sms_outbox row. It asked the obvious way:
--
--   SELECT u.center_id FROM hbh.users u WHERE u.mobile = $1 ...
--
-- and got ZERO ROWS, every time, silently. The reason is the rule this
-- project was built on: RLS FAILS CLOSED. A login code is issued BEFORE
-- there is a session, so the connection carries no identity, so
-- hbh.current_center_id() is NULL, so the policy on hbh.users matches
-- nothing. Exactly as designed - and the symptom was a login that
-- worked, a code that was echoed, a 202 returned, and no outbox row and
-- no error anywhere. The delivery path was doing nothing and reporting
-- success, which is the shape of defect this whole schema is arranged to
-- prevent.
--
-- WHY THE FIX IS HERE AND NOT A SECOND LOOKUP FUNCTION. request_otp is
-- SECURITY DEFINER and has ALREADY found the user - it is holding the
-- row. Adding a SECURITY DEFINER "which centre owns this number"
-- function would (a) do the same lookup twice and (b) create a primitive
-- that answers "is this number registered" to anything that can call it,
-- which is the question the whole of otpRequestOut's header is about.
-- Returning what the function already knows adds no new capability.
--
-- THE SCHEMA MAY GO FIRST HERE, unlike 0053, 0058, 0059 and 0083. This
-- ADDS a column to a return type and the caller names its columns
-- explicitly, so a service built against the old shape keeps working
-- against the new one. Dropping or renaming would be the other case.
--
-- The body is otherwise IDENTICAL to 0083's. Nothing about lifetime,
-- resend, attempt handling, the fixed-code affordance or the
-- ENROLMENT_PENDING answer changes.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0095') THEN
    RAISE EXCEPTION 'migration 0095 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0094') THEN
    RAISE EXCEPTION 'migration 0094 must be applied first';
  END IF;
END
$guard$;

-- A changed return type cannot be CREATE OR REPLACE'd.
DROP FUNCTION IF EXISTS hbh.request_otp(text);

CREATE FUNCTION hbh.request_otp(p_mobile text)
RETURNS TABLE(ok boolean, reason text, code text, expires_at timestamptz,
              center_id integer)
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
      RETURN QUERY SELECT false, 'ENROLMENT_PENDING', NULL::text,
                          NULL::timestamptz, NULL::integer;
      RETURN;
    END IF;

    RETURN QUERY SELECT false, 'NOT_REGISTERED', NULL::text,
                        NULL::timestamptz, NULL::integer;
    RETURN;
  END IF;

  IF l_user.status <> 'ACTIVE' THEN
    -- Still withheld, and the CENTRE IS WITHHELD TOO. Returning it for a
    -- locked account would let a caller distinguish "locked" from
    -- "unknown" by whether a number came back, which is the fact the
    -- handler is deliberately collapsing.
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

  RETURN QUERY SELECT true, 'OK', l_code, l_expires, l_user.center_id;
END
$fn$;

REVOKE ALL ON FUNCTION hbh.request_otp(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.request_otp(text) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0095');
