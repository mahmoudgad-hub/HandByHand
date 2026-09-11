-- =====================================================================
-- Hand By Hand (new) - API phase 10 fixture teardown
--
-- Runs BEFORE the fixture as well as after it.
--
-- Everything goes by identity. This database is shared, and a LIKE over
-- a mobile number once reached a neighbour's fixture and took twenty-one
-- checks down with it.
-- =====================================================================

\set ON_ERROR_STOP on

-- Attachments first: the photo checks write them, and they hold keys to
-- both the child and the uploader.
DELETE FROM hbh.attachments a
 USING hbh.children c WHERE c.child_id = a.child_id AND c.child_no LIKE 'A10-%';
DELETE FROM hbh.attachments a
 USING hbh.users u WHERE u.user_id = a.uploaded_by AND u.username LIKE 'a10\_%';

ALTER TABLE hbh.consent_events DISABLE TRIGGER ALL;
DELETE FROM hbh.consent_events e
 USING hbh.consents c, hbh.guardians g, hbh.users u
 WHERE c.consent_id = e.consent_id AND g.guardian_id = c.guardian_id
   AND u.user_id = g.user_id AND u.username LIKE 'a10\_%';
ALTER TABLE hbh.consent_events ENABLE TRIGGER ALL;

DELETE FROM hbh.consents c
 USING hbh.guardians g, hbh.users u
 WHERE g.guardian_id = c.guardian_id AND u.user_id = g.user_id AND u.username LIKE 'a10\_%';

DELETE FROM hbh.staff_documents d
 USING hbh.users u WHERE u.user_id = d.user_id AND u.username LIKE 'a10\_%';
DELETE FROM hbh.staff_profiles p
 USING hbh.users u WHERE u.user_id = p.user_id AND u.username LIKE 'a10\_%';

DELETE FROM hbh.guardian_children gc
 USING hbh.children c WHERE c.child_id = gc.child_id AND c.child_no LIKE 'A10-%';
DELETE FROM hbh.children WHERE child_no LIKE 'A10-%';

DELETE FROM hbh.guardians g
 USING hbh.users u WHERE u.user_id = g.user_id AND u.username LIKE 'a10\_%';

DELETE FROM hbh.notifications n
 USING hbh.users u WHERE u.user_id = n.user_id AND u.username LIKE 'a10\_%';
DELETE FROM hbh.user_roles ur
 USING hbh.users u WHERE u.user_id = ur.user_id AND u.username LIKE 'a10\_%';
DELETE FROM hbh.auth_sessions s
 USING hbh.users u WHERE u.user_id = s.user_id AND u.username LIKE 'a10\_%';
DELETE FROM hbh.otp_codes o
 USING hbh.users u WHERE u.user_id = o.user_id AND u.username LIKE 'a10\_%';
DELETE FROM hbh.password_setups p
 USING hbh.users u WHERE u.user_id = p.user_id AND u.username LIKE 'a10\_%';
DELETE FROM hbh.password_setups p
 USING hbh.users u WHERE u.user_id = p.issued_by AND u.username LIKE 'a10\_%';
DELETE FROM hbh.users WHERE username LIKE 'a10\_%';

DO $gone$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.users WHERE username LIKE 'a10\_%';
  IF n <> 0 THEN RAISE EXCEPTION 'teardown left % account(s)', n; END IF;
  SELECT count(*) INTO n FROM hbh.children WHERE child_no LIKE 'A10-%';
  IF n <> 0 THEN RAISE EXCEPTION 'teardown left % child(ren)', n; END IF;
END
$gone$;
