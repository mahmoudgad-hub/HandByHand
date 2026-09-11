-- =====================================================================
-- Hand By Hand (new) - API phase 5 fixture: a centre that can take a booking
--
-- WHAT THIS FIXTURE DELIBERATELY DOES NOT CREATE: an appointment.
--
-- The suite books one through the API, because booking IS the thing
-- under test. A fixture that pre-booked would leave the suite reading a
-- row it did not create through the path it claims to be testing - and
-- the phase-3 suite learned that lesson the other way round, by ending
-- its fixture with a real validate_slot call to prove the centre could
-- accept a booking at all before any rule was tested.
--
-- So this creates only the PRECONDITIONS: a service, a room, a
-- therapist who offers that service and works that day, a child on
-- their caseload, and accounts to act as.
--
-- Four accounts, and the two therapists matter:
--   a5_admin      CENTER_ADMIN - books, issues, publishes, decides
--   a5_therapist  THERAPIST    - starts and closes the session, writes
--                                the note. A different person from the
--                                administrator on purpose: closing a
--                                session and running the centre are
--                                separate rights.
--   a5_colleague  THERAPIST    - holds SESSION.NOTES.EDIT and owns none
--                                of these sessions. Without a second
--                                therapist, "you may not write notes"
--                                and "this is somebody else's session"
--                                are indistinguishable to any test, and
--                                the suite would pass on whichever the
--                                code happened to return.
--   a5_parent     GUARDIAN     - submits the request reception decides
--
-- Everything is named a5_ or A5- so the teardown can find it.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS a5_fx;
CREATE TEMP TABLE a5_fx (k text PRIMARY KEY, v integer);
DROP TABLE IF EXISTS a5_fxt;
CREATE TEMP TABLE a5_fxt (k text PRIMARY KEY, v timestamptz);

INSERT INTO a5_fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO a5_fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

-- Next Monday, 10:00 and 11:00 Cairo. date_trunc('week') lands on a
-- Monday, so +7 days is never Friday or Saturday - Egypt's weekend,
-- which validate_slot refuses. Two slots so the suite can book one and
-- still have a free one to check against.
INSERT INTO a5_fxt (k, v) VALUES
  ('slot1_start', (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                   + interval '7 days' + interval '10 hours') AT TIME ZONE 'Africa/Cairo'),
  ('slot1_end',   (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                   + interval '7 days' + interval '10 hours 45 minutes') AT TIME ZONE 'Africa/Cairo'),
  ('slot2_start', (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                   + interval '7 days' + interval '13 hours') AT TIME ZONE 'Africa/Cairo'),
  ('slot2_end',   (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                   + interval '7 days' + interval '13 hours 45 minutes') AT TIME ZONE 'Africa/Cairo');

INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code, color_hex)
VALUES ((SELECT v FROM a5_fx WHERE k='center'), (SELECT v FROM a5_fx WHERE k='branch'),
        'A5-SPEECH', 'تخاطب — الدفعة الخامسة', 'SPEECH', '#2E6F8E');
INSERT INTO a5_fx (k, v) SELECT 'svc', service_id FROM hbh.services WHERE code='A5-SPEECH';

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
VALUES ((SELECT v FROM a5_fx WHERE k='center'), (SELECT v FROM a5_fx WHERE k='branch'),
        'A5-R1', 'غرفة الدفعة الخامسة');
INSERT INTO a5_fx (k, v) SELECT 'room', room_id FROM hbh.rooms WHERE code='A5-R1';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
SELECT (SELECT v FROM a5_fx WHERE k='center'), (SELECT v FROM a5_fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile, 'ACTIVE'
FROM (VALUES
       ('a5_admin',     'مديرة المركز — خمسة', 'STAFF',     '+201500000050'),
       ('a5_therapist', 'أخصائية التخاطب',      'THERAPIST', '+201500000051'),
       ('a5_colleague', 'أخصائية زميلة',       'THERAPIST', '+201500000053'),
       ('a5_parent',    'وليّ الأمر',            'GUARDIAN',  '+201500000052')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM   hbh.users u
JOIN   hbh.roles r ON r.center_id = u.center_id
WHERE (u.username = 'a5_admin'     AND r.code = 'CENTER_ADMIN')
   OR (u.username = 'a5_therapist' AND r.code = 'THERAPIST')
   OR (u.username = 'a5_colleague' AND r.code = 'THERAPIST')
   OR (u.username = 'a5_parent'    AND r.code = 'GUARDIAN');

INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar, title_ar)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, 'أخصائي أول'
FROM   hbh.users u WHERE u.username = 'a5_therapist';
INSERT INTO a5_fx (k, v) SELECT 'th', t.therapist_id FROM hbh.therapists t
 JOIN hbh.users u ON u.user_id = t.user_id WHERE u.username = 'a5_therapist';

-- The colleague. A therapist WITH SESSION.NOTES.EDIT who owns none of
-- this fixture's sessions - which is the only way to tell the two halves
-- of a refusal apart. Without a second therapist, "you may not write
-- notes" and "this is somebody else's session" cannot be distinguished
-- by any test, and the suite would pass whichever one the code returned.
INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar, title_ar)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, 'أخصائي'
FROM   hbh.users u WHERE u.username = 'a5_colleague';

INSERT INTO hbh.therapist_services (therapist_id, service_id)
VALUES ((SELECT v FROM a5_fx WHERE k='th'), (SELECT v FROM a5_fx WHERE k='svc'));

INSERT INTO hbh.therapist_working_hours (center_id, therapist_id, weekday, start_time, end_time)
SELECT (SELECT v FROM a5_fx WHERE k='center'), (SELECT v FROM a5_fx WHERE k='th'),
       d, TIME '09:00', TIME '17:00'
FROM   unnest(ARRAY[7,1,2,3,4]::smallint[]) AS d;

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM a5_fx WHERE k='center'), (SELECT v FROM a5_fx WHERE k='branch'),
        'A5-A', 'طفل الدفعة الخامسة', DATE '2020-06-06', 'M');
INSERT INTO a5_fx (k, v) SELECT 'child', child_id FROM hbh.children WHERE child_no='A5-A';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, u.mobile
FROM   hbh.users u WHERE u.username = 'a5_parent';

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
SELECT g.guardian_id, c.child_id, 'FATHER', true
FROM   hbh.users u
JOIN   hbh.guardians g ON g.user_id = u.user_id
JOIN   hbh.children c  ON c.child_no = 'A5-A'
WHERE  u.username = 'a5_parent';

-- start_session refuses a child who is not on the therapist's caseload
-- (HB023), so this is a precondition and not decoration.
INSERT INTO hbh.caseload (center_id, therapist_id, child_id, service_id, is_primary_flg)
VALUES ((SELECT v FROM a5_fx WHERE k='center'), (SELECT v FROM a5_fx WHERE k='th'),
        (SELECT v FROM a5_fx WHERE k='child'), (SELECT v FROM a5_fx WHERE k='svc'), true);

-- A plan and a goal, so a report has something to be about.
INSERT INTO hbh.treatment_plans (center_id, branch_id, child_id, service_id, therapist_id, title_ar, status)
VALUES ((SELECT v FROM a5_fx WHERE k='center'), (SELECT v FROM a5_fx WHERE k='branch'),
        (SELECT v FROM a5_fx WHERE k='child'), (SELECT v FROM a5_fx WHERE k='svc'),
        (SELECT v FROM a5_fx WHERE k='th'), 'خطة الدفعة الخامسة', 'ACTIVE');
INSERT INTO a5_fx (k, v) SELECT 'plan', plan_id FROM hbh.treatment_plans
 WHERE title_ar = 'خطة الدفعة الخامسة';

INSERT INTO hbh.plan_goals (center_id, plan_id, title_ar, baseline_pct, target_pct, sort_order)
VALUES ((SELECT v FROM a5_fx WHERE k='center'), (SELECT v FROM a5_fx WHERE k='plan'),
        'هدف الدفعة الخامسة', 20, 80, 10);

-- A DRAFT report and a DRAFT invoice, for the publish and issue paths.
-- Both start in the state a family cannot see, so the suite can watch
-- them cross the line.
INSERT INTO hbh.progress_reports (center_id, branch_id, child_id, plan_id, report_no,
                                  title_ar, period_start, period_end, summary_ar, status)
VALUES ((SELECT v FROM a5_fx WHERE k='center'), (SELECT v FROM a5_fx WHERE k='branch'),
        (SELECT v FROM a5_fx WHERE k='child'), (SELECT v FROM a5_fx WHERE k='plan'),
        'A5-RPT', 'تقرير الدفعة الخامسة', current_date - 60, current_date - 1,
        'ملخّص التقرير.', 'DRAFT');
INSERT INTO a5_fx (k, v) SELECT 'report', report_id FROM hbh.progress_reports WHERE report_no='A5-RPT';

INSERT INTO hbh.invoices (center_id, branch_id, invoice_no, child_id, guardian_id,
                          currency_code, tax_rate, due_date)
SELECT c.center_id, (SELECT v FROM a5_fx WHERE k='branch'), 'A5-INV',
       (SELECT v FROM a5_fx WHERE k='child'),
       (SELECT g.guardian_id FROM hbh.guardians g JOIN hbh.users u ON u.user_id = g.user_id
         WHERE u.username = 'a5_parent'),
       c.currency_code, hbh.param(c.center_id, 'DEFAULT_TAX_RATE', '0')::numeric,
       current_date + 14
FROM   hbh.centers c WHERE c.code = 'HBH';
INSERT INTO a5_fx (k, v) SELECT 'invoice', invoice_id FROM hbh.invoices WHERE invoice_no='A5-INV';

INSERT INTO hbh.invoice_lines (center_id, invoice_id, description_ar, qty, unit_amt, line_amt, sort_order)
VALUES ((SELECT v FROM a5_fx WHERE k='center'), (SELECT v FROM a5_fx WHERE k='invoice'),
        'جلسات تخاطب', 1, 1000.00, 1000.00, 10);

INSERT INTO hbh.service_packages (center_id, service_id, code, name_ar, sessions_cnt, price_amt, validity_days)
VALUES ((SELECT v FROM a5_fx WHERE k='center'), (SELECT v FROM a5_fx WHERE k='svc'),
        'A5-PKG', 'باقة الدفعة الخامسة', 4, 2000.00, 90);

-- Staff passwords, set by the administrator acting as themselves.
SELECT set_config('hbh.user_id', 'a5_admin', false);
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='a5_admin'),     'a5-admin-pw-123456');
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='a5_therapist'), 'a5-therapist-pw-123456');
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='a5_colleague'), 'a5-colleague-pw-123456');
SELECT set_config('hbh.user_id', '', false);

-- ---------------------------------------------------------------------
-- The fixture asserts itself, by name, before any test runs
--
-- The last assertion is a real validate_slot call. Every booking test
-- below is meaningless if the centre cannot accept a booking at all,
-- and finding that out from the first refused test looks like a broken
-- rule rather than a broken fixture.
-- ---------------------------------------------------------------------
DO $assert$
DECLARE n integer; l_ok boolean; l_reason text;
BEGIN
  SELECT count(*) INTO n FROM hbh.users WHERE username LIKE 'a5\_%';
  IF n <> 4 THEN RAISE EXCEPTION 'fixture: expected 4 accounts, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.users
   WHERE username IN ('a5_admin','a5_therapist','a5_colleague') AND password_hash IS NOT NULL;
  IF n <> 3 THEN RAISE EXCEPTION 'fixture: a staff password was not set (% of 3)', n; END IF;

  -- The colleague must actually HOLD the right, or the HB035 check below
  -- proves nothing: it would pass on a plain permission refusal.
  SELECT count(*) INTO n
  FROM   hbh.users u
  JOIN   hbh.user_roles ur ON ur.user_id = u.user_id
  JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id
  JOIN   hbh.permissions p ON p.permission_id = rp.permission_id
  WHERE  u.username = 'a5_colleague' AND p.code = 'SESSION.NOTES.EDIT';
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: a5_colleague does not hold SESSION.NOTES.EDIT - the ownership check would be indistinguishable from a permission refusal'; END IF;

  SELECT count(*) INTO n FROM hbh.caseload cl
   JOIN hbh.children c ON c.child_id = cl.child_id WHERE c.child_no = 'A5-A';
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: no caseload - start_session would refuse with HB023'; END IF;

  SELECT count(*) INTO n FROM hbh.appointments a
   JOIN hbh.children c ON c.child_id = a.child_id WHERE c.child_no = 'A5-A';
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: an appointment already exists - the suite must create it'; END IF;

  SELECT count(*) INTO n FROM hbh.progress_reports WHERE report_no='A5-RPT' AND status='DRAFT';
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: the report is not a draft'; END IF;

  SELECT count(*) INTO n FROM hbh.invoices WHERE invoice_no='A5-INV' AND status='DRAFT';
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: the invoice is not a draft'; END IF;

  -- Can this centre accept the booking the suite is about to make?
  SELECT ok, reason INTO l_ok, l_reason
  FROM   hbh.validate_slot(
           (SELECT v FROM a5_fx WHERE k='center'), (SELECT v FROM a5_fx WHERE k='child'),
           (SELECT v FROM a5_fx WHERE k='th'),     (SELECT v FROM a5_fx WHERE k='room'),
           (SELECT v FROM a5_fx WHERE k='svc'),
           (SELECT v FROM a5_fxt WHERE k='slot1_start'), (SELECT v FROM a5_fxt WHERE k='slot1_end'));
  IF NOT l_ok THEN
    RAISE EXCEPTION 'fixture: the centre cannot accept the test slot (%) - every booking test would fail on the fixture, not the code', l_reason;
  END IF;
END
$assert$;

\echo 'fixture a5: ready'
