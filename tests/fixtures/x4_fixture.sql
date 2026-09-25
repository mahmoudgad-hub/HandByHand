-- =====================================================================
-- Hand By Hand (new) - X4 fixture: THE STAFF ROOM, AND NOTHING ELSE.
--
-- WHAT THIS FIXTURE DELIBERATELY DOES NOT CREATE: the family.
--
-- No application, no child, no guardian, no portal account, no caseload,
-- no appointment, no session. Every one of those is made by the product's
-- own route while X4 walks, and that is the entire point of HBH-015:
-- every other fixture in this project hands the suite a guardian whose
-- account was inserted by the owner, so no test has ever asked whether
-- the route that makes one works.
--
-- WHAT IT DOES CREATE, and why each piece is unavoidable:
--
--   x4_reception  RECEPTION    - ENROLMENT.MANAGE (triage and convert),
--                                GUARDIAN.MANAGE (portal access),
--                                APPOINTMENT.BOOK
--   x4_admin      CENTER_ADMIN - STAFF.MANAGE, which reception does NOT
--                                hold and hbh.assign_therapist demands.
--                                Two accounts, because the caseload step
--                                belongs to a different desk than the
--                                triage - and a walk signed in as one
--                                account would never find that out.
--   x4_therapist  THERAPIST    - owns the session, writes the note.
--
--   a service that opens a session and wants a caseload · a room ·
--   the therapist's working hours · the service linked to them
--
-- The seeded dev_* accounts would have served, and they are NOT used:
-- their password is not in the repository by design (db/dev/
-- staff_accounts.sql refuses to run without DEV_STAFF_PASSWORD), so a
-- suite that needed it could not run unattended, and a suite that reset
-- it would change a password other sessions are signed in with.
--
-- THE FAMILY MOBILE IS ASSERTED ABSENT BELOW. If a previous run died
-- between its walk and its teardown, the enrolment step would meet a
-- limit or an existing account and the failure would name neither.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS x4_fx;
CREATE TEMP TABLE x4_fx (k text PRIMARY KEY, v integer);

INSERT INTO x4_fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO x4_fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

-- ---------------------------------------------------------------------
-- The three desks
-- ---------------------------------------------------------------------
INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
SELECT (SELECT v FROM x4_fx WHERE k='center'), (SELECT v FROM x4_fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile, 'ACTIVE'
FROM (VALUES
       ('x4_reception', 'موظّفة الاستقبال — الطريق', 'STAFF',     '+201500000441'),
       ('x4_admin',     'مديرة المركز — الطريق',     'STAFF',     '+201500000442'),
       ('x4_therapist', 'أخصائية التخاطب — الطريق',  'THERAPIST', '+201500000443')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM   hbh.users u JOIN hbh.roles r ON r.center_id = u.center_id
WHERE (u.username = 'x4_reception' AND r.code = 'RECEPTION')
   OR (u.username = 'x4_admin'     AND r.code = 'CENTER_ADMIN')
   OR (u.username = 'x4_therapist' AND r.code = 'THERAPIST');

INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar, title_ar)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, 'أخصائي أول'
FROM   hbh.users u WHERE u.username = 'x4_therapist';
INSERT INTO x4_fx (k, v)
SELECT 'th', t.therapist_id FROM hbh.therapists t
 JOIN hbh.users u ON u.user_id = t.user_id WHERE u.username = 'x4_therapist';

-- ---------------------------------------------------------------------
-- The catalogue this walk books against
--
-- BOTH FLAGS TRUE: creates_session_flg because the walk must reach a
-- session, and needs_caseload_flg because the caseload step is one of
-- the four that were never walked - a service that does not want a
-- caseload would let the booking through without it and the step under
-- test would prove nothing.
-- ---------------------------------------------------------------------
INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code, color_hex,
                          default_duration_min, creates_session_flg, needs_caseload_flg)
VALUES ((SELECT v FROM x4_fx WHERE k='center'), (SELECT v FROM x4_fx WHERE k='branch'),
        'X4-SPEECH', 'تخاطب — الطريق من الصفر', 'SPEECH', '#00897B', 45, true, true);
INSERT INTO x4_fx (k, v) SELECT 'svc', service_id FROM hbh.services WHERE code = 'X4-SPEECH';

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
VALUES ((SELECT v FROM x4_fx WHERE k='center'), (SELECT v FROM x4_fx WHERE k='branch'),
        'X4-R1', 'غرفة الطريق من الصفر');
INSERT INTO x4_fx (k, v) SELECT 'room', room_id FROM hbh.rooms WHERE code = 'X4-R1';

INSERT INTO hbh.therapist_services (therapist_id, service_id)
VALUES ((SELECT v FROM x4_fx WHERE k='th'), (SELECT v FROM x4_fx WHERE k='svc'));

-- Every weekday, 08:00 to 20:00. The walk books "tomorrow" and must not
-- fail because tomorrow happens to be the one day she does not work -
-- a red run whose cause is the calendar teaches nobody anything.
INSERT INTO hbh.therapist_working_hours (center_id, therapist_id, weekday, start_time, end_time)
SELECT (SELECT v FROM x4_fx WHERE k='center'), (SELECT v FROM x4_fx WHERE k='th'),
       d, TIME '08:00', TIME '20:00'
FROM   unnest(ARRAY[1,2,3,4,5,6,7]::smallint[]) AS d;

SELECT set_config('hbh.user_id', 'x4_admin', false);
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='x4_reception'), 'x4-reception-pw-123456');
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='x4_admin'),     'x4-admin-pw-123456');
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='x4_therapist'), 'x4-therapist-pw-123456');
SELECT set_config('hbh.user_id', '', false);

DO $assert$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.users WHERE username LIKE 'x4\_%';
  IF n <> 3 THEN RAISE EXCEPTION 'fixture: expected 3 staff accounts, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.users
   WHERE username LIKE 'x4\_%' AND password_hash IS NOT NULL;
  IF n <> 3 THEN RAISE EXCEPTION 'fixture: a staff password was not set (% of 3)', n; END IF;

  -- Each right is named against the desk that uses it. "Reception can do
  -- things" would stay green the day somebody narrows the role, and every
  -- refusal in the walk would then prove a permission gap instead of the
  -- step under test.
  SELECT count(DISTINCT p.code) INTO n
  FROM   hbh.users u
  JOIN   hbh.user_roles ur       ON ur.user_id = u.user_id
  JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id
  JOIN   hbh.permissions p       ON p.permission_id = rp.permission_id
  WHERE  u.username = 'x4_reception'
    AND  p.code IN ('ENROLMENT.MANAGE','GUARDIAN.MANAGE','APPOINTMENT.BOOK');
  IF n <> 3 THEN RAISE EXCEPTION 'fixture: x4_reception is missing one of its three rights (% of 3)', n; END IF;

  -- And the division the walk depends on: reception may NOT assign a
  -- therapist. If this ever becomes false, the walk still passes - but it
  -- stops proving that the caseload step needs a different desk, so the
  -- fixture says it out loud here.
  SELECT count(*) INTO n
  FROM   hbh.users u
  JOIN   hbh.user_roles ur       ON ur.user_id = u.user_id
  JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id
  JOIN   hbh.permissions p       ON p.permission_id = rp.permission_id
  WHERE  u.username = 'x4_reception' AND p.code = 'STAFF.MANAGE';
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: x4_reception now holds STAFF.MANAGE - the two-desk property is gone'; END IF;

  SELECT count(*) INTO n
  FROM   hbh.users u
  JOIN   hbh.user_roles ur       ON ur.user_id = u.user_id
  JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id
  JOIN   hbh.permissions p       ON p.permission_id = rp.permission_id
  WHERE  u.username = 'x4_admin' AND p.code = 'STAFF.MANAGE';
  IF n = 0 THEN RAISE EXCEPTION 'fixture: x4_admin does not hold STAFF.MANAGE - the caseload step would fail for the wrong reason'; END IF;

  SELECT count(DISTINCT p.code) INTO n
  FROM   hbh.users u
  JOIN   hbh.user_roles ur       ON ur.user_id = u.user_id
  JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id
  JOIN   hbh.permissions p       ON p.permission_id = rp.permission_id
  WHERE  u.username = 'x4_therapist'
    AND  p.code IN ('SESSION.START','SESSION.COMPLETE','SESSION.NOTES.EDIT','NOTE.PUBLISH');
  IF n <> 4 THEN RAISE EXCEPTION 'fixture: x4_therapist is missing one of its four rights (% of 4)', n; END IF;

  -- The catalogue the booking needs, by name rather than by count.
  IF NOT EXISTS (SELECT 1 FROM hbh.services WHERE code='X4-SPEECH' AND creates_session_flg AND needs_caseload_flg)
    THEN RAISE EXCEPTION 'fixture: X4-SPEECH is missing or does not open a session / want a caseload'; END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.therapist_services ts
                  WHERE ts.therapist_id = (SELECT v FROM x4_fx WHERE k='th')
                    AND ts.service_id  = (SELECT v FROM x4_fx WHERE k='svc') AND ts.active_flg)
    THEN RAISE EXCEPTION 'fixture: the therapist does not offer X4-SPEECH - every booking would be THERAPIST_SERVICE_MISMATCH'; END IF;
  SELECT count(*) INTO n FROM hbh.therapist_working_hours
   WHERE therapist_id = (SELECT v FROM x4_fx WHERE k='th') AND active_flg;
  IF n <> 7 THEN RAISE EXCEPTION 'fixture: expected 7 working-hour rows, found %', n; END IF;

  -- THE STATE UNDER TEST, MADE AND NOT ASSUMED: nothing of this family
  -- exists yet. The mobile is this run's own, and it must be free in all
  -- three places the walk will create rows in.
  SELECT count(*) INTO n FROM hbh.users WHERE mobile = '+201500000440' AND active_flg;
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: an account already holds the family mobile - a previous run did not clean up'; END IF;

  SELECT count(*) INTO n FROM hbh.guardians WHERE mobile = '+201500000440' AND active_flg;
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: a guardian already holds the family mobile'; END IF;

  SELECT count(*) INTO n FROM hbh.enrolment_applications
   WHERE parent_mobile = '+201500000440' AND active_flg;
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: % application(s) already exist on the family mobile - the daily limit or the pending check would answer instead of the step under test', n; END IF;

  -- The child this walk creates is numbered by the CHILD series, not by
  -- any name of ours - so it is found through the guardian link, the same
  -- way the teardown finds it.
  SELECT count(*) INTO n
  FROM   hbh.guardian_children gc
  JOIN   hbh.guardians g ON g.guardian_id = gc.guardian_id
  WHERE  g.mobile = '+201500000440';
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: % child(ren) are already linked to the family mobile', n; END IF;
END
$assert$;

\echo 'fixture x4: staff room ready - no family, by design'
