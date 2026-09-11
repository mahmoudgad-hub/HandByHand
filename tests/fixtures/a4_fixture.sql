-- =====================================================================
-- Hand By Hand (new) - API phase 4 fixture: the operations app
--
-- THREE accounts, chosen so that permission boundaries can be proven
-- rather than asserted:
--
--   a4_admin      CENTER_ADMIN - has CATALOG.MANAGE and STAFF.MANAGE
--   a4_reception  RECEPTION    - has CHILD.CREATE and CHILD.EDIT,
--                               and NOT CATALOG.MANAGE
--   a4_parent     GUARDIAN     - has neither, and signs in differently
--
-- Reception is the interesting one. A test where the only person who
-- can write is an administrator proves nothing about the gate: it could
-- be gating on "is staff" and look identical. Reception CAN create a
-- child and CANNOT create a service, so a single account demonstrates
-- that the permission is what decides, not the job title.
--
-- The two staff accounts get passwords through hbh.set_password, which
-- itself requires USER.MANAGE - so the centre administrator sets them,
-- acting as themselves. A password written straight into the column
-- would skip the hashing the function exists to perform.
--
-- Everything is named a4_ or A4- so the teardown can find it.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS a4_fx;
CREATE TEMP TABLE a4_fx (k text PRIMARY KEY, v integer);

INSERT INTO a4_fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO a4_fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
SELECT (SELECT v FROM a4_fx WHERE k='center'), (SELECT v FROM a4_fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile, 'ACTIVE'
FROM (VALUES
       ('a4_admin',     'مديرة المركز',    'STAFF',    '+201500000030'),
       ('a4_reception', 'موظفة الاستقبال', 'STAFF',    '+201500000031'),
       ('a4_parent',    'وليّ أمر',         'GUARDIAN', '+201500000032')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM   hbh.users u
JOIN   hbh.roles r ON r.center_id = u.center_id
WHERE (u.username = 'a4_admin'     AND r.code = 'CENTER_ADMIN')
   OR (u.username = 'a4_reception' AND r.code = 'RECEPTION')
   OR (u.username = 'a4_parent'    AND r.code = 'GUARDIAN');

-- A child and a guardian record, so the parent account has something to
-- be a guardian OF - hbh.current_center_id() needs the user row, and the
-- gate tests need a real family.
INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM a4_fx WHERE k='center'), (SELECT v FROM a4_fx WHERE k='branch'),
        'A4-A', 'طفل العائلة', DATE '2020-07-07', 'F');

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, u.mobile
FROM   hbh.users u WHERE u.username = 'a4_parent';

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
SELECT g.guardian_id, c.child_id, 'MOTHER', true
FROM   hbh.users u
JOIN   hbh.guardians g ON g.user_id = u.user_id
JOIN   hbh.children c  ON c.child_no = 'A4-A'
WHERE  u.username = 'a4_parent';

-- A room, because the seed creates none and the camera tests need one.
--
-- notes_ar carries a marker, not decoration: the room list is readable
-- by every user of the centre, and the suite checks that this note
-- reaches staff and does not reach a family. A note the tests could not
-- recognise on sight would make that check pass on an empty column.
INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar, notes_ar)
VALUES ((SELECT v FROM a4_fx WHERE k='center'), (SELECT v FROM a4_fx WHERE k='branch'),
        'A4-ROOM', 'غرفة الاختبار', 'a4-room-note internal');

-- A therapist, because the seed creates none and the `mask` group asserts on
-- one: that a guardian sees the NAME and not the mobile, and that the centre
-- still sees the mobile.
--
-- The suite used to assert this without creating anybody, so it passed only
-- while some other suite's therapist happened to be sitting in the shared
-- database - and both its mask checks failed the moment a4 ran on a clean
-- one, or ran before the suites whose leftovers it was reading. A suite that
-- asserts on rows it does not own is a suite whose result depends on what
-- else ran that day.
--
-- The mobile is a real-looking number on purpose: the check greps for
-- "mobile":"<digit>, so a null or an empty string would make "the number did
-- not reach the guardian" pass without the mask doing anything.
INSERT INTO hbh.therapists (center_id, branch_id, full_name_ar, mobile, title_ar)
VALUES ((SELECT v FROM a4_fx WHERE k='center'), (SELECT v FROM a4_fx WHERE k='branch'),
        'أ. سلمى عبد الله', '+201500000049', 'أخصائية تخاطب');

-- Passwords, set by the administrator acting as themselves.
SELECT set_config('hbh.user_id', 'a4_admin', false);
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='a4_admin'),     'a4-admin-pw-123456');
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='a4_reception'), 'a4-reception-pw-123456');
SELECT set_config('hbh.user_id', '', false);

-- ---------------------------------------------------------------------
-- The fixture asserts itself, by name, before any test runs
-- ---------------------------------------------------------------------
DO $assert$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.users WHERE username LIKE 'a4\_%';
  IF n <> 3 THEN RAISE EXCEPTION 'fixture: expected 3 accounts, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.users WHERE username IN ('a4_admin','a4_reception')
   AND password_hash IS NOT NULL;
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: a staff password was not set (% of 2)', n; END IF;

  -- The parent must NOT have a password: the whole point of the staff
  -- login test is that a guardian is turned away from that door.
  SELECT count(*) INTO n FROM hbh.users WHERE username = 'a4_parent' AND password_hash IS NULL;
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: the guardian has a password and should not'; END IF;

  -- The permission boundary this whole suite rests on. Asserted here so
  -- that a role change elsewhere fails LOUDLY instead of quietly turning
  -- the boundary tests below into tautologies.
  PERFORM set_config('hbh.user_id','a4_reception',false);
  IF hbh.has_permission('CATALOG.MANAGE') THEN
    RAISE EXCEPTION 'fixture: reception now holds CATALOG.MANAGE - the boundary test would prove nothing';
  END IF;
  IF NOT hbh.has_permission('CHILD.CREATE') THEN
    RAISE EXCEPTION 'fixture: reception lost CHILD.CREATE - the boundary test would pass for the wrong reason';
  END IF;

  PERFORM set_config('hbh.user_id','a4_admin',false);
  IF NOT hbh.has_permission('CATALOG.MANAGE') THEN
    RAISE EXCEPTION 'fixture: the administrator does not hold CATALOG.MANAGE';
  END IF;
  IF NOT hbh.has_permission('LIVE.VIEW') THEN
    RAISE EXCEPTION 'fixture: the administrator does not hold LIVE.VIEW - cameras need both';
  END IF;
  PERFORM set_config('hbh.user_id','',false);

  SELECT count(*) INTO n FROM hbh.rooms WHERE code = 'A4-ROOM';
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: no room for the camera test'; END IF;

  -- By name, before the tests. The mask group reads a therapist and used to
  -- read whichever one another suite had left behind.
  SELECT count(*) INTO n FROM hbh.therapists
   WHERE mobile = '+201500000049' AND active_flg;
  IF n <> 1 THEN
    RAISE EXCEPTION 'fixture: no therapist for the mask test - it would pass on somebody else''s row';
  END IF;
  PERFORM set_config('hbh.user_id','',false);
END
$assert$;

\echo 'fixture a4: ready'
