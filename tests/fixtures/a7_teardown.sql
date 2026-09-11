-- =====================================================================
-- Hand By Hand (new) - API phase 7 fixture teardown
--
-- Runs BEFORE the fixture as well as after it.
--
-- The profile tables go first: they hold keys to the therapist. And the
-- therapists row itself holds published_by and consent_by pointing at
-- USERS, so those columns are cleared before the accounts go - the
-- rows they name are this fixture's own, so clearing them changes
-- nothing that belongs to anybody else.
-- =====================================================================

\set ON_ERROR_STOP on

DELETE FROM hbh.therapist_certificates c
 USING hbh.therapists t, hbh.users u
 WHERE t.therapist_id = c.therapist_id AND u.user_id = t.user_id AND u.username LIKE 'a7\_%';

DELETE FROM hbh.therapist_qualifications q
 USING hbh.therapists t, hbh.users u
 WHERE t.therapist_id = q.therapist_id AND u.user_id = t.user_id AND u.username LIKE 'a7\_%';

DELETE FROM hbh.therapist_languages l
 USING hbh.therapists t, hbh.users u
 WHERE t.therapist_id = l.therapist_id AND u.user_id = t.user_id AND u.username LIKE 'a7\_%';

-- Down from PUBLISHED first: the status trigger refuses an illegal
-- move, and PUBLISHED -> DRAFT is legal while PUBLISHED -> nothing is
-- not. The columns cannot simply be nulled under a CHECK that ties them
-- to the status.
UPDATE hbh.therapists t
   SET profile_status = 'DRAFT', published_at = NULL, published_by = NULL
  FROM hbh.users u
 WHERE u.user_id = t.user_id AND u.username LIKE 'a7\_%' AND t.profile_status = 'PUBLISHED';

UPDATE hbh.therapists t
   SET consent_at = NULL, consent_by = NULL, consent_text_version = NULL
  FROM hbh.users u
 WHERE u.user_id = t.user_id AND u.username LIKE 'a7\_%';

DELETE FROM hbh.therapist_services ts
 USING hbh.therapists t, hbh.users u
 WHERE t.therapist_id = ts.therapist_id AND u.user_id = t.user_id AND u.username LIKE 'a7\_%';

DELETE FROM hbh.caseload cl
 USING hbh.children c WHERE c.child_id = cl.child_id AND c.child_no LIKE 'A7-%';

DELETE FROM hbh.therapists t
 USING hbh.users u WHERE u.user_id = t.user_id AND u.username LIKE 'a7\_%';

DELETE FROM hbh.guardian_children gc
 USING hbh.children c WHERE c.child_id = gc.child_id AND c.child_no LIKE 'A7-%';

DELETE FROM hbh.children WHERE child_no LIKE 'A7-%';

DELETE FROM hbh.guardians g
 USING hbh.users u WHERE u.user_id = g.user_id AND u.username LIKE 'a7\_%';

DELETE FROM hbh.notifications n
 USING hbh.users u WHERE u.user_id = n.user_id AND u.username LIKE 'a7\_%';

DELETE FROM hbh.user_roles ur
 USING hbh.users u WHERE u.user_id = ur.user_id AND u.username LIKE 'a7\_%';
DELETE FROM hbh.auth_sessions s
 USING hbh.users u WHERE u.user_id = s.user_id AND u.username LIKE 'a7\_%';
DELETE FROM hbh.otp_codes o
 USING hbh.users u WHERE u.user_id = o.user_id AND u.username LIKE 'a7\_%';
DELETE FROM hbh.users WHERE username LIKE 'a7\_%';

DO $gone$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.users WHERE username LIKE 'a7\_%';
  IF n <> 0 THEN RAISE EXCEPTION 'teardown left % account(s)', n; END IF;
  SELECT count(*) INTO n FROM hbh.children WHERE child_no LIKE 'A7-%';
  IF n <> 0 THEN RAISE EXCEPTION 'teardown left % child(ren)', n; END IF;
END
$gone$;
