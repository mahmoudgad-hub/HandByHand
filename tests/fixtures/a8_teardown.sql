-- =====================================================================
-- Hand By Hand (new) - API phase 8 fixture teardown
--
-- Runs BEFORE the fixture as well as after it.
--
-- THE PARAMETER ROW IS WHY THIS FILE NEEDS CARE. The suite writes a
-- centre override and then resets it, and a reset is a SOFT delete -
-- the row stays, deactivated. So the row this suite creates outlives
-- the run by design, and this teardown is what returns the shared
-- database to the state it was found in.
--
-- It removes the override for ONE named code in ONE centre. Not by
-- prefix and not by "recently touched": this database is shared, other
-- centre overrides exist for other reasons, and two of them were left
-- deactivated by hand during development. A cleanup that reached those
-- would change what another session is running on, quietly.
-- =====================================================================

\set ON_ERROR_STOP on

-- DATE_DISPLAY_FORMAT is the parameter this suite moves, chosen because
-- nothing computes with it: it decides how a date is drawn and no rule
-- reads it. Moving MAX_ATTACHMENT_MB or an OTP window would change what
-- another suite is being refused for, in the same database, mid-run.
DELETE FROM hbh.sys_params
 WHERE center_id = (SELECT center_id FROM hbh.centers WHERE code = 'HBH')
   AND param_code = 'DATE_DISPLAY_FORMAT';

DELETE FROM hbh.guardians g
 USING hbh.users u WHERE u.user_id = g.user_id AND u.username LIKE 'a8\_%';

DELETE FROM hbh.user_roles ur
 USING hbh.users u WHERE u.user_id = ur.user_id AND u.username LIKE 'a8\_%';
DELETE FROM hbh.auth_sessions s
 USING hbh.users u WHERE u.user_id = s.user_id AND u.username LIKE 'a8\_%';
DELETE FROM hbh.otp_codes o
 USING hbh.users u WHERE u.user_id = o.user_id AND u.username LIKE 'a8\_%';
DELETE FROM hbh.password_setups p
 USING hbh.users u WHERE u.user_id = p.user_id AND u.username LIKE 'a8\_%';
DELETE FROM hbh.notifications n
 USING hbh.users u WHERE u.user_id = n.user_id AND u.username LIKE 'a8\_%';
DELETE FROM hbh.users WHERE username LIKE 'a8\_%';

DO $gone$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.users WHERE username LIKE 'a8\_%';
  IF n <> 0 THEN RAISE EXCEPTION 'teardown left % account(s)', n; END IF;

  SELECT count(*) INTO n FROM hbh.sys_params
   WHERE center_id IS NOT NULL AND param_code = 'DATE_DISPLAY_FORMAT';
  IF n <> 0 THEN RAISE EXCEPTION 'teardown left % parameter override(s)', n; END IF;
END
$gone$;
