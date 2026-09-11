-- =====================================================================
-- Hand By Hand (new) - API phase 9 fixture teardown
--
-- Runs BEFORE the fixture as well as after it.
--
-- Everything goes by identity - the accounts this fixture names - and
-- nothing by resemblance. The database is shared with other sessions
-- and a LIKE over a mobile number once reached a neighbour's row and
-- took twenty-one checks down with it.
-- =====================================================================

\set ON_ERROR_STOP on

DELETE FROM hbh.family_message_reads r
 USING hbh.users u WHERE u.user_id = r.user_id AND u.username LIKE 'a9\_%';
DELETE FROM hbh.family_message_reads r
 USING hbh.guardians g, hbh.users u
 WHERE g.guardian_id = r.guardian_id AND u.user_id = g.user_id AND u.username LIKE 'a9\_%';

DELETE FROM hbh.family_messages m
 USING hbh.guardians g, hbh.users u
 WHERE g.guardian_id = m.guardian_id AND u.user_id = g.user_id AND u.username LIKE 'a9\_%';
DELETE FROM hbh.family_messages m
 USING hbh.users u WHERE u.user_id = m.sender_id AND u.username LIKE 'a9\_%';

-- Consents carry an append-only event trail, so the events go first and
-- the trigger is lifted for exactly that statement. Lifting it is safe
-- here and nowhere else: these rows were written by this fixture.
ALTER TABLE hbh.consent_events DISABLE TRIGGER ALL;
DELETE FROM hbh.consent_events e
 USING hbh.consents c, hbh.guardians g, hbh.users u
 WHERE c.consent_id = e.consent_id AND g.guardian_id = c.guardian_id
   AND u.user_id = g.user_id AND u.username LIKE 'a9\_%';
ALTER TABLE hbh.consent_events ENABLE TRIGGER ALL;

DELETE FROM hbh.consents c
 USING hbh.guardians g, hbh.users u
 WHERE g.guardian_id = c.guardian_id AND u.user_id = g.user_id AND u.username LIKE 'a9\_%';

DELETE FROM hbh.guardian_children gc
 USING hbh.children c WHERE c.child_id = gc.child_id AND c.child_no LIKE 'A9-%';
DELETE FROM hbh.children WHERE child_no LIKE 'A9-%';

DELETE FROM hbh.guardians g
 USING hbh.users u WHERE u.user_id = g.user_id AND u.username LIKE 'a9\_%';

DELETE FROM hbh.notifications n
 USING hbh.users u WHERE u.user_id = n.user_id AND u.username LIKE 'a9\_%';
DELETE FROM hbh.user_roles ur
 USING hbh.users u WHERE u.user_id = ur.user_id AND u.username LIKE 'a9\_%';
DELETE FROM hbh.auth_sessions s
 USING hbh.users u WHERE u.user_id = s.user_id AND u.username LIKE 'a9\_%';
DELETE FROM hbh.otp_codes o
 USING hbh.users u WHERE u.user_id = o.user_id AND u.username LIKE 'a9\_%';
DELETE FROM hbh.password_setups p
 USING hbh.users u WHERE u.user_id = p.user_id AND u.username LIKE 'a9\_%';
DELETE FROM hbh.users WHERE username LIKE 'a9\_%';

DO $gone$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.users WHERE username LIKE 'a9\_%';
  IF n <> 0 THEN RAISE EXCEPTION 'teardown left % account(s)', n; END IF;
  SELECT count(*) INTO n FROM hbh.children WHERE child_no LIKE 'A9-%';
  IF n <> 0 THEN RAISE EXCEPTION 'teardown left % child(ren)', n; END IF;
END
$gone$;
