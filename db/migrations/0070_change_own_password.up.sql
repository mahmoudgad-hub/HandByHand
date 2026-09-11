-- =====================================================================
-- 0070 - changing your own password
--
-- The other half of 0068. That one gets a password onto an account that
-- has none, from a code an administrator hands over. This one is for
-- somebody who already has one and wants a different one - which is the
-- ordinary case, and until now had no path at all.
--
-- IT ACTS ON hbh.current_user_id() AND TAKES NO USER ID. There is no
-- argument naming whose password to change, so there is no version of
-- this call that changes somebody else's. An administrator who needs to
-- reset another person issues a setup code; they do not get a shortcut
-- through here.
--
-- THE CURRENT PASSWORD IS REQUIRED, and checked with the same function
-- the sign-in screen uses. A session is not proof of identity for this:
-- an unlocked terminal is somebody else's session, and a password change
-- with no confirmation is how a borrowed screen becomes a taken account.
--
-- SO A WRONG CURRENT PASSWORD COUNTS TOWARD THE LOCK, exactly as it does
-- at sign-in, because it is the same credential being guessed. Somebody
-- who mistypes their old password three times will find themselves
-- locked out for LOGIN_LOCK_MINUTES - which is the correct outcome and
-- worth the screen saying so plainly.
--
-- AND IT RETURNS A STATUS RATHER THAN RAISING. hbh.verify_password
-- increments the attempt counter; an exception after it would roll that
-- increment back and make the counter decorative. Same rule as D-1,
-- same rule as redeem_password_setup, same rule as verify_otp.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION hbh.change_own_password(
  p_current text,
  p_new     text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_user  hbh.users%ROWTYPE;
  l_check record;
  l_min   integer;
BEGIN
  SELECT * INTO l_user FROM hbh.users
  WHERE user_id = hbh.current_user_id() AND active_flg;
  IF NOT FOUND THEN
    RETURN 'NO_IDENTITY';
  END IF;

  IF l_user.user_type NOT IN ('STAFF', 'THERAPIST') THEN
    -- A family signs in with a one-time code and has no password to
    -- change. Its own answer, because "wrong password" would send
    -- somebody looking for one they never had.
    RETURN 'NOT_PASSWORD_USER';
  END IF;

  -- The same check as the sign-in screen, including the counter and the
  -- lock. Deliberately not a bare crypt() comparison here: that would be
  -- a second definition of "is this the right password" and the one
  -- without the lock is the weaker of the two.
  SELECT * INTO l_check
  FROM hbh.verify_password(l_user.username, p_current);

  IF NOT l_check.ok THEN
    -- Passed through rather than flattened. TEMPORARILY_LOCKED and a
    -- wrong password send a person to two different places: wait, or
    -- try again.
    RETURN l_check.reason;
  END IF;

  l_min := hbh.param(l_user.center_id, 'MIN_PASSWORD_LENGTH', '10')::integer;
  IF length(coalesce(p_new, '')) < l_min THEN
    RETURN 'TOO_SHORT';
  END IF;

  IF p_new = p_current THEN
    -- Not an error the database has to care about, but a screen that
    -- accepted it would report success for a change that changed
    -- nothing, and somebody would believe their password had rotated.
    RETURN 'UNCHANGED';
  END IF;

  PERFORM hbh.set_password(l_user.user_id, p_new);
  RETURN 'OK';
END;
$fn$;

REVOKE ALL ON FUNCTION hbh.change_own_password(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.change_own_password(text, text) TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0070');
