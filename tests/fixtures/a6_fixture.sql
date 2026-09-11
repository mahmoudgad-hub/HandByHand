-- =====================================================================
-- Hand By Hand (new) - API phase 6 fixture: intake, the survey, the log
--
-- WHAT THIS FIXTURE DELIBERATELY DOES NOT CREATE: an enrolment
-- application.
--
-- Submitting one is the thing under test, and it is the only write in
-- this service made with no identity at all - so the suite submits it
-- over HTTP with no token. A pre-inserted row would let every queue and
-- conversion test pass while the anonymous path was broken, which is
-- precisely the half that faces the open internet.
--
-- Three accounts, and RECEPTION is the one that matters:
--   a6_admin      CENTER_ADMIN - ENROLMENT.MANAGE, NPS.MANAGE, OPS.VIEW
--   a6_reception  RECEPTION    - ENROLMENT.MANAGE and NOTHING else of
--                                the three. It is how the suite proves
--                                the operations screen is closed to a
--                                role that can work the intake queue.
--   a6_parent     GUARDIAN     - answers the survey, and is the family
--                                a second application must ATTACH to
--                                rather than duplicate.
--
-- ONE SURVEY, of trigger kind PERIOD.
--
-- The schema already seeds PARENT_SESSION, which is an ACTION survey
-- fired by a completed session - so it is never due for a family that
-- has had none, and it cannot make this suite pass by accident. A
-- PERIOD survey with period_days = 1 and no prior response is due
-- immediately and for a deterministic reason.
--
-- Everything is named a6_ or A6- or carries a mobile in the
-- 015000000 6x range, so the teardown can find it.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS a6_fx;
CREATE TEMP TABLE a6_fx (k text PRIMARY KEY, v integer);

INSERT INTO a6_fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO a6_fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code, color_hex)
VALUES ((SELECT v FROM a6_fx WHERE k='center'), (SELECT v FROM a6_fx WHERE k='branch'),
        'A6-OT', 'علاج وظيفي — الدفعة السادسة', 'OT', '#7A5A9E');
INSERT INTO a6_fx (k, v) SELECT 'svc', service_id FROM hbh.services WHERE code='A6-OT';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
SELECT (SELECT v FROM a6_fx WHERE k='center'), (SELECT v FROM a6_fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile, 'ACTIVE'
FROM (VALUES
       ('a6_admin',     'مديرة المركز — ستة', 'STAFF',    '+201500000060'),
       ('a6_reception', 'الاستقبال — ستة',    'STAFF',    '+201500000061'),
       ('a6_parent',    'وليّ الأمر — ستة',    'GUARDIAN', '+201500000062')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM   hbh.users u
JOIN   hbh.roles r ON r.center_id = u.center_id
WHERE (u.username = 'a6_admin'     AND r.code = 'CENTER_ADMIN')
   OR (u.username = 'a6_reception' AND r.code = 'RECEPTION')
   OR (u.username = 'a6_parent'    AND r.code = 'GUARDIAN');

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM a6_fx WHERE k='center'), (SELECT v FROM a6_fx WHERE k='branch'),
        'A6-A', 'طفل الدفعة السادسة', DATE '2019-04-04', 'F');

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, u.mobile
FROM   hbh.users u WHERE u.username = 'a6_parent';

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
SELECT g.guardian_id, c.child_id, 'MOTHER', true
FROM   hbh.users u
JOIN   hbh.guardians g ON g.user_id = u.user_id
JOIN   hbh.children c  ON c.child_no = 'A6-A'
WHERE  u.username = 'a6_parent';

-- The survey. period_days = 1 with no prior response means due now;
-- cooldown_days = 30 means that once the suite answers it, asking again
-- must return nothing - which is the check that proves the cooldown is
-- real rather than a column.
INSERT INTO hbh.nps_surveys (center_id, code, name_ar, question_ar, followup_question_ar,
                             audience, trigger_kind, period_days, cooldown_days, active_flg)
VALUES ((SELECT v FROM a6_fx WHERE k='center'), 'A6-PERIOD', 'استبيان الدفعة السادسة',
        'ما مدى رضاك عن خدمة المركز؟', 'ما الذي يجعل تقييمك أفضل؟',
        'GUARDIAN', 'PERIOD', 1, 30, true);

SELECT set_config('hbh.user_id', 'a6_admin', false);
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='a6_admin'),     'a6-admin-pw-123456');
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='a6_reception'), 'a6-reception-pw-123456');
SELECT set_config('hbh.user_id', '', false);

-- ---------------------------------------------------------------------
-- The fixture asserts itself, by name, before any test runs
--
-- The last two assertions are the ones worth having. A forgotten
-- permission and an application left over from a previous run both
-- surface fifty checks later as a puzzling refusal from correct code.
-- ---------------------------------------------------------------------
DO $assert$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.users WHERE username LIKE 'a6\_%';
  IF n <> 3 THEN RAISE EXCEPTION 'fixture: expected 3 accounts, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.users
   WHERE username IN ('a6_admin','a6_reception') AND password_hash IS NOT NULL;
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: a staff password was not set (% of 2)', n; END IF;

  -- The whole point of the reception account: it works the queue and it
  -- must NOT reach the operations screen. If the role ever gains
  -- OPS.VIEW the suite would still pass while proving nothing, so the
  -- assumption is asserted here rather than assumed there.
  SELECT count(*) INTO n
  FROM   hbh.roles r
  JOIN   hbh.role_permissions rp ON rp.role_id = r.role_id
  JOIN   hbh.permissions p ON p.permission_id = rp.permission_id
  WHERE  r.code = 'RECEPTION' AND p.code = 'ENROLMENT.MANAGE';
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: RECEPTION cannot work the intake queue'; END IF;

  SELECT count(*) INTO n
  FROM   hbh.roles r
  JOIN   hbh.role_permissions rp ON rp.role_id = r.role_id
  JOIN   hbh.permissions p ON p.permission_id = rp.permission_id
  WHERE  r.code = 'RECEPTION' AND p.code IN ('OPS.VIEW','NPS.MANAGE');
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: RECEPTION now holds OPS.VIEW or NPS.MANAGE - the negative checks below prove nothing'; END IF;

  SELECT count(*) INTO n FROM hbh.enrolment_applications
   WHERE parent_mobile IN ('+201500000062','+201500000063','+201500000064');
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: an application already exists - the suite must submit it'; END IF;

  SELECT count(*) INTO n FROM hbh.nps_surveys WHERE code = 'A6-PERIOD' AND active_flg;
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: the period survey is missing'; END IF;
END
$assert$;

\echo 'fixture a6: ready'
