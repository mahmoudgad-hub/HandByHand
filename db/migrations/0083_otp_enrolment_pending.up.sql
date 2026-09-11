-- =====================================================================
-- 0083 - the sign-in screen stops sending people to wait for nothing
--
-- THE API GOES FIRST. This migration adds a reason code the transport
-- layer has never seen, and an unrecognised reason there becomes a 500 -
-- the same trap 0053, 0058 and 0059 carry the same warning about.
--
-- WHAT WAS HAPPENING. Any number typed into the portal answered "code
-- sent" and moved to the code screen. A parent whose number is on no
-- child's file, and a parent who filled in the enrolment form last week
-- and has not been called back yet, both sat there waiting for an SMS
-- that was never coming - with nothing on the screen saying why or what
-- to do next. Reported by the owner, who did it himself while testing.
--
-- WHAT THIS FUNCTION NOW DISTINGUISHES, and nothing more:
--
--   OK                  a code was issued
--   ENROLMENT_PENDING   no account, but this mobile is on an enrolment
--                       application the centre has not finished deciding
--   NOT_REGISTERED      no account and no live application
--   USER_LOCKED         unchanged, and still not forwarded to the screen
--   RESEND_TOO_SOON     unchanged
--
-- WHAT IT COSTS, WRITTEN DOWN RATHER THAN ARGUED AGAIN. Forwarding these
-- lets a stranger with a phone number ask "is this person a client of a
-- children's therapy centre?" and now also "did they apply and get
-- turned away?". Both are facts about a family and a disability.
--
-- The owner weighed it once already, on 2026-09-05, and chose the parent
-- over the probe. That decision is recorded in api/internal/http/
-- auth_handlers.go and the code never carried it out - the header of
-- otpRequestOut says the distinction is made and the handler twelve
-- lines further down collapses it. A decision written in a comment and
-- reversed in the code beneath it is worse than either answer, because
-- the next person reads whichever half they reach first.
--
-- A REJECTED APPLICATION IS NOT REVEALED. REJECTED and DUPLICATE answer
-- NOT_REGISTERED like any stranger. "The centre considered you and said
-- no" is a decision about a family, it helps nobody standing at a login
-- screen, and it is not what was asked for.
--
-- AND ENROLLED WITHOUT A USER ANSWERS NOT_REGISTERED TOO. That pairing
-- means conversion half-finished, which is the centre's problem to fix
-- and not a sentence to put in front of a parent.
--
-- THE MOBILE IS NOT UNIQUE ANYWHERE IN THIS SCHEMA - not on users and
-- not on applications - so this reads the MOST RECENT application, the
-- same way the user lookup above it takes ORDER BY user_id LIMIT 1.
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

-- The lookup this adds runs on every sign-in attempt that finds no user,
-- which is every probe and every typo. Without an index that is a scan
-- of the application table each time.
CREATE INDEX IF NOT EXISTS ix_enrolment_applications_parent_mobile
  ON hbh.enrolment_applications (parent_mobile)
  WHERE active_flg;

INSERT INTO hbh.schema_migrations (version) VALUES ('0083');
