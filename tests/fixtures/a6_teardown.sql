-- =====================================================================
-- Hand By Hand (new) - API phase 6 fixture teardown
--
-- Runs BEFORE the fixture as well as after it.
--
-- Two things here are not obvious:
--
--   1. The CHILDREN AND GUARDIANS THIS SUITE DID NOT CREATE.
--      hbh.convert_enrolment makes a child and, when the mobile is new,
--      a guardian - so the rows to remove are named by the application
--      that produced them, not by any A6- code. They are found through
--      converted_child_id and converted_guardian_id before the
--      applications themselves go.
--
--   2. hbh.request_log is APPEND-ONLY and is NOT emptied.
--      Every request this suite makes writes a row, and so does every
--      request any other suite makes. Deleting by time would race the
--      other sessions working on this database; deleting all of it would
--      throw away the thing the operations screen reads. The suite scopes
--      its counts to its own run instead - which is the same rule the
--      audit log has had since phase 1.
-- =====================================================================

\set ON_ERROR_STOP on

-- The survey answers first: they hold a key to the user and to the
-- survey, and removing either before them fails on the constraint.
DELETE FROM hbh.nps_responses r
 USING hbh.users u WHERE u.user_id = r.user_id AND u.username LIKE 'a6\_%';

DELETE FROM hbh.nps_responses r
 USING hbh.nps_surveys s WHERE s.survey_id = r.survey_id AND s.code LIKE 'A6-%';

DELETE FROM hbh.nps_surveys WHERE code LIKE 'A6-%';

DELETE FROM hbh.notifications n
 USING hbh.users u WHERE u.user_id = n.user_id AND u.username LIKE 'a6\_%';

-- The families that conversion created.
--
-- THE IDS ARE COPIED OUT FIRST, and that ordering is the whole trick.
-- hbh.enrolment_applications keeps a foreign key to the child it became,
-- so the child cannot go while the application is still there - and the
-- application is the only thing that knows which child it was. Reading
-- the pair into a temp table breaks the circle: applications first,
-- then the rows they named.
DROP TABLE IF EXISTS a6_converted;
CREATE TEMP TABLE a6_converted AS
SELECT converted_child_id AS child_id, converted_guardian_id AS guardian_id
FROM   hbh.enrolment_applications
WHERE  parent_mobile IN ('+201500000062','+201500000063','+201500000064');

DELETE FROM hbh.enrolment_applications
 WHERE parent_mobile IN ('+201500000062','+201500000063','+201500000064');

DELETE FROM hbh.guardian_children gc
 USING a6_converted c WHERE gc.child_id = c.child_id;

DELETE FROM hbh.children ch
 USING a6_converted c WHERE ch.child_id = c.child_id;

-- The guardian only when nothing else points at it: the reuse test
-- deliberately attaches a second child to the guardian the fixture made,
-- and that one goes with the fixture's own accounts below.
DELETE FROM hbh.guardians g
 USING a6_converted c
 WHERE g.guardian_id = c.guardian_id
   AND g.user_id IS NULL
   AND NOT EXISTS (SELECT 1 FROM hbh.guardian_children x WHERE x.guardian_id = g.guardian_id);

DELETE FROM hbh.guardian_children gc
 USING hbh.children c WHERE c.child_id = gc.child_id AND c.child_no LIKE 'A6-%';

DELETE FROM hbh.children WHERE child_no LIKE 'A6-%';

DELETE FROM hbh.guardians g
 USING hbh.users u WHERE u.user_id = g.user_id AND u.username LIKE 'a6\_%';

DELETE FROM hbh.services WHERE code LIKE 'A6-%';

DELETE FROM hbh.user_roles ur
 USING hbh.users u WHERE u.user_id = ur.user_id AND u.username LIKE 'a6\_%';
DELETE FROM hbh.auth_sessions s
 USING hbh.users u WHERE u.user_id = s.user_id AND u.username LIKE 'a6\_%';
DELETE FROM hbh.otp_codes o
 USING hbh.users u WHERE u.user_id = o.user_id AND u.username LIKE 'a6\_%';
DELETE FROM hbh.users WHERE username LIKE 'a6\_%';

-- Cleanup is a recorded check, not a hope. A leftover application would
-- make the next run's per-mobile limit fire early and read as a broken
-- endpoint.
DO $gone$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.enrolment_applications
   WHERE parent_mobile IN ('+201500000062','+201500000063','+201500000064');
  IF n <> 0 THEN RAISE EXCEPTION 'teardown left % enrolment application(s)', n; END IF;

  SELECT count(*) INTO n FROM hbh.users WHERE username LIKE 'a6\_%';
  IF n <> 0 THEN RAISE EXCEPTION 'teardown left % account(s)', n; END IF;

  SELECT count(*) INTO n FROM hbh.nps_surveys WHERE code LIKE 'A6-%';
  IF n <> 0 THEN RAISE EXCEPTION 'teardown left % survey(s)', n; END IF;
END
$gone$;
