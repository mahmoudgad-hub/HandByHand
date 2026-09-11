-- =====================================================================
-- Hand By Hand (new) - API phase 3 fixture
--
-- A centre with a running session, a camera on the room, a home
-- programme, a request, a package and an issued invoice.
--
-- THREE guardians, and the third is the interesting one:
--
--   a3_parent_a  -> child A, can_view_live_flg = TRUE
--   a3_parent_c  -> child A, can_view_live_flg = FALSE
--   a3_parent_b  -> child B
--
-- A and C are guardians of the SAME child. The only difference between
-- them is one flag, so a test that A can watch and C cannot proves the
-- flag is the gate - not the family link, and not the child.
--
-- The session is left IN_PROGRESS deliberately. hbh.can_view_live
-- requires a session that is running right now, and a fixture that
-- closed it would make every live check pass for the wrong reason.
--
-- The media gateway is NOT configured here. A fresh install refuses to
-- stream, and the suite tests that refusal first; only then does it
-- configure a gateway and test the rest. The teardown puts it back.
--
-- Run as hbh_owner. The functions still read hbh.current_user_id(), so
-- the acting identity is set at session level before each group of
-- calls that needs one, and cleared at the end.
--
-- Everything is named a3_ or A3- so the teardown can find it.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS a3_fx;
CREATE TEMP TABLE a3_fx (k text PRIMARY KEY, v integer);
DROP TABLE IF EXISTS a3_fxt;
CREATE TEMP TABLE a3_fxt (k text PRIMARY KEY, v timestamptz);

INSERT INTO a3_fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO a3_fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO a3_fxt (k, v) VALUES
  ('slot_start', (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '10 hours') AT TIME ZONE 'Africa/Cairo'),
  ('slot_end',   (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '10 hours 45 minutes') AT TIME ZONE 'Africa/Cairo');

-- ---------------------------------------------------------------------
-- Service, room, camera
-- ---------------------------------------------------------------------
INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code, color_hex)
VALUES ((SELECT v FROM a3_fx WHERE k='center'), (SELECT v FROM a3_fx WHERE k='branch'),
        'A3-SPEECH', 'تخاطب — اختبار الدفعة الثالثة', 'SPEECH', '#3B7A9E');
INSERT INTO a3_fx (k, v) SELECT 'svc', service_id FROM hbh.services WHERE code='A3-SPEECH';

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
VALUES ((SELECT v FROM a3_fx WHERE k='center'), (SELECT v FROM a3_fx WHERE k='branch'),
        'A3-R1', 'غرفة البث');
INSERT INTO a3_fx (k, v) SELECT 'room', room_id FROM hbh.rooms WHERE code='A3-R1';

-- gateway_path is a PATH, never an address: the CHECK on the column is
-- what stops somebody pasting an rtsp:// URL in here on a busy
-- afternoon. It must never reach a browser, and the suite asserts that.
INSERT INTO hbh.cameras (center_id, branch_id, room_id, code, name_ar, gateway_path, status)
VALUES ((SELECT v FROM a3_fx WHERE k='center'), (SELECT v FROM a3_fx WHERE k='branch'),
        (SELECT v FROM a3_fx WHERE k='room'), 'A3-CAM1', 'كاميرا غرفة البث',
        'a3-secret-room-path', 'ONLINE');
INSERT INTO a3_fx (k, v) SELECT 'cam', camera_id FROM hbh.cameras WHERE code='A3-CAM1';

-- ---------------------------------------------------------------------
-- People
-- ---------------------------------------------------------------------
INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
SELECT (SELECT v FROM a3_fx WHERE k='center'), (SELECT v FROM a3_fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile, 'ACTIVE'
FROM (VALUES
       ('a3_therapist', 'أخصائية الدفعة الثالثة', 'THERAPIST', '+201500000020'),
       ('a3_admin',     'مديرة المركز',           'STAFF',     '+201500000021'),
       ('a3_parent_a',  'وليّ الأمر الأول',        'GUARDIAN',  '+201500000022'),
       ('a3_parent_b',  'وليّ الأمر الثاني',       'GUARDIAN',  '+201500000023'),
       ('a3_parent_c',  'وليّ الأمر الثالث',       'GUARDIAN',  '+201500000024')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM   hbh.users u
JOIN   hbh.roles r ON r.center_id = u.center_id
WHERE (u.username = 'a3_therapist' AND r.code = 'THERAPIST')
   OR (u.username = 'a3_admin'     AND r.code = 'CENTER_ADMIN')
   OR (u.username IN ('a3_parent_a','a3_parent_b','a3_parent_c') AND r.code = 'GUARDIAN');

INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar, title_ar)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, 'أخصائي أول'
FROM   hbh.users u WHERE u.username = 'a3_therapist';
INSERT INTO a3_fx (k, v) SELECT 'th', t.therapist_id FROM hbh.therapists t
 JOIN hbh.users u ON u.user_id = t.user_id WHERE u.username = 'a3_therapist';

INSERT INTO hbh.therapist_services (therapist_id, service_id)
VALUES ((SELECT v FROM a3_fx WHERE k='th'), (SELECT v FROM a3_fx WHERE k='svc'));

INSERT INTO hbh.therapist_working_hours (center_id, therapist_id, weekday, start_time, end_time)
SELECT (SELECT v FROM a3_fx WHERE k='center'), (SELECT v FROM a3_fx WHERE k='th'),
       d, TIME '09:00', TIME '17:00'
FROM   unnest(ARRAY[7,1,2,3,4]::smallint[]) AS d;

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM a3_fx WHERE k='center'), (SELECT v FROM a3_fx WHERE k='branch'),
        'A3-A', 'طفل العائلة الأولى', DATE '2020-05-05', 'M'),
       ((SELECT v FROM a3_fx WHERE k='center'), (SELECT v FROM a3_fx WHERE k='branch'),
        'A3-B', 'طفل العائلة الثانية', DATE '2019-09-09', 'F');
INSERT INTO a3_fx (k, v) SELECT 'child_a', child_id FROM hbh.children WHERE child_no='A3-A';
INSERT INTO a3_fx (k, v) SELECT 'child_b', child_id FROM hbh.children WHERE child_no='A3-B';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, u.mobile
FROM   hbh.users u WHERE u.username IN ('a3_parent_a','a3_parent_b','a3_parent_c');

-- A and C on the same child. The links are created with the flag at its
-- default of FALSE for all three, because since migration 0015
-- can_view_live_flg may not be written directly - a trigger raises
-- HB081 unless a LIVE_VIEW consent is on record.
--
-- That is the right rule and it is why this fixture no longer sets the
-- column: watching a child in therapy now requires somebody to have
-- said yes, recorded, with a date. Setting a boolean was never the same
-- thing as having permission.
INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
SELECT g.guardian_id, c.child_id, v.rel, v.primary_flg
FROM  (VALUES
        ('a3_parent_a', 'A3-A', 'FATHER', true),
        ('a3_parent_c', 'A3-A', 'MOTHER', false),
        ('a3_parent_b', 'A3-B', 'FATHER', true)
      ) AS v(username, child_no, rel, primary_flg)
JOIN   hbh.users u     ON u.username = v.username
JOIN   hbh.guardians g ON g.user_id = u.user_id
JOIN   hbh.children c  ON c.child_no = v.child_no;

-- The consent, for parent A only. grant_consent needs the guardian
-- themselves or GUARDIAN.MANAGE, so the seeded administrator records
-- it - which is how it happens in the centre too.
--
-- Parent C is left WITHOUT consent, and that is the whole live-view
-- test: two guardians of the same child, on the same running session,
-- differing in exactly one recorded fact.
SELECT set_config('hbh.user_id', 'admin', false);

SELECT hbh.grant_consent(
  (SELECT g.guardian_id FROM hbh.guardians g
    JOIN hbh.users u ON u.user_id = g.user_id WHERE u.username = 'a3_parent_a'),
  'LIVE_VIEW',
  (SELECT child_id FROM hbh.children WHERE child_no = 'A3-A'));

SELECT set_config('hbh.user_id', '', false);

INSERT INTO hbh.caseload (center_id, therapist_id, child_id, service_id, is_primary_flg)
VALUES ((SELECT v FROM a3_fx WHERE k='center'), (SELECT v FROM a3_fx WHERE k='th'),
        (SELECT v FROM a3_fx WHERE k='child_a'), (SELECT v FROM a3_fx WHERE k='svc'), true);

-- ---------------------------------------------------------------------
-- A session that is running RIGHT NOW
--
-- Left IN_PROGRESS. can_view_live requires it, and a closed session
-- would make every live check pass for the wrong reason.
-- ---------------------------------------------------------------------
INSERT INTO a3_fx (k, v)
SELECT 'appt', hbh.book_appointment(
  (SELECT v FROM a3_fx WHERE k='center'), (SELECT v FROM a3_fx WHERE k='branch'),
  (SELECT v FROM a3_fx WHERE k='child_a'), (SELECT v FROM a3_fx WHERE k='th'),
  (SELECT v FROM a3_fx WHERE k='room'),    (SELECT v FROM a3_fx WHERE k='svc'),
  (SELECT v FROM a3_fxt WHERE k='slot_start'), (SELECT v FROM a3_fxt WHERE k='slot_end'));

UPDATE hbh.appointments SET status = 'CONFIRMED'  WHERE appointment_id = (SELECT v FROM a3_fx WHERE k='appt');
UPDATE hbh.appointments SET status = 'CHECKED_IN' WHERE appointment_id = (SELECT v FROM a3_fx WHERE k='appt');

-- Started BY the therapist who owns the appointment. Migration 0087 gave
-- hbh.start_session the authorization it never had - SESSION.START, and
-- whose appointment this is - so a call with no identity now fails closed
-- with HB028, which is the correct answer and not a fixture problem.
SELECT set_config('hbh.user_id', 'a3_therapist', false);

INSERT INTO a3_fx (k, v)
SELECT 'sess', hbh.start_session((SELECT v FROM a3_fx WHERE k='appt'));

SELECT set_config('hbh.user_id', '', false);

-- ---------------------------------------------------------------------
-- The home programme
-- ---------------------------------------------------------------------
INSERT INTO hbh.activity_library (center_id, code, title_ar, how_to_ar, service_id)
VALUES ((SELECT v FROM a3_fx WHERE k='center'), 'A3-ACT1', 'تمرين نطق السين',
        'خمس دقائق يوميًا أمام المرآة، عشر كلمات في كل مرة.',
        (SELECT v FROM a3_fx WHERE k='svc'));
INSERT INTO a3_fx (k, v) SELECT 'act', activity_id FROM hbh.activity_library WHERE code='A3-ACT1';

INSERT INTO hbh.child_activities (center_id, child_id, activity_id, assigned_by,
                                  times_per_week, minutes_each, instructions_ar, start_date)
SELECT (SELECT v FROM a3_fx WHERE k='center'), (SELECT v FROM a3_fx WHERE k='child_a'),
       (SELECT v FROM a3_fx WHERE k='act'), u.user_id, 5, 5,
       'ابدأي بالكلمات القصيرة ثم زيدي الطول تدريجيًا.', current_date - 14
FROM   hbh.users u WHERE u.username = 'a3_therapist';
INSERT INTO a3_fx (k, v) SELECT 'ca', child_activity_id FROM hbh.child_activities
 WHERE child_id = (SELECT v FROM a3_fx WHERE k='child_a');

-- From here the family is the acting identity: log_activity and
-- submit_request both check that the caller is a guardian of the child.
SELECT set_config('hbh.user_id', 'a3_parent_a', false);

-- Two days already reported, so the suite can log a THIRD and still have
-- a day it can prove is refused as a duplicate.
SELECT hbh.log_activity((SELECT v FROM a3_fx WHERE k='ca'), current_date - 2, true, 'تمّ التمرين كاملًا.');
SELECT hbh.log_activity((SELECT v FROM a3_fx WHERE k='ca'), current_date - 1, false, 'كان الطفل متعبًا.');

INSERT INTO a3_fx (k, v)
SELECT 'req', hbh.submit_request(
  (SELECT v FROM a3_fx WHERE k='child_a'), 'CALLBACK', NULL,
  'أرجو تحديد موعد مكالمة مع الأخصائية.', NULL);

-- ---------------------------------------------------------------------
-- Billing
--
-- Selling a package and issuing an invoice both need BILLING.MANAGE,
-- which only CENTER_ADMIN holds - so the centre administrator acts here.
-- ---------------------------------------------------------------------
SELECT set_config('hbh.user_id', 'a3_admin', false);

INSERT INTO hbh.service_packages (center_id, service_id, code, name_ar, sessions_cnt, price_amt, validity_days)
VALUES ((SELECT v FROM a3_fx WHERE k='center'), (SELECT v FROM a3_fx WHERE k='svc'),
        'A3-PKG8', 'باقة تخاطب — ٨ جلسات', 8, 4000.00, 120);
INSERT INTO a3_fx (k, v) SELECT 'pkg', package_id FROM hbh.service_packages WHERE code='A3-PKG8';

INSERT INTO a3_fx (k, v)
SELECT 'child_pkg', hbh.sell_package((SELECT v FROM a3_fx WHERE k='child_a'),
                                     (SELECT v FROM a3_fx WHERE k='pkg'));

-- One invoice that gets issued, and one that stays a DRAFT. A guardian
-- without BILLING.VIEW must see the first and not the second.
INSERT INTO hbh.invoices (center_id, branch_id, invoice_no, child_id, guardian_id,
                          currency_code, tax_rate, due_date)
SELECT c.center_id, (SELECT v FROM a3_fx WHERE k='branch'),
       hbh.next_number(c.center_id, 'INVOICE'),
       (SELECT v FROM a3_fx WHERE k='child_a'),
       (SELECT g.guardian_id FROM hbh.guardians g JOIN hbh.users u ON u.user_id = g.user_id
         WHERE u.username = 'a3_parent_a'),
       c.currency_code,
       hbh.param(c.center_id, 'DEFAULT_TAX_RATE', '0')::numeric,
       current_date + 14
FROM   hbh.centers c WHERE c.code = 'HBH';
INSERT INTO a3_fx (k, v) SELECT 'inv', max(invoice_id) FROM hbh.invoices
 WHERE child_id = (SELECT v FROM a3_fx WHERE k='child_a');

INSERT INTO hbh.invoice_lines (center_id, invoice_id, description_ar, qty, unit_amt, line_amt, sort_order)
VALUES ((SELECT v FROM a3_fx WHERE k='center'), (SELECT v FROM a3_fx WHERE k='inv'),
        'باقة تخاطب — ٨ جلسات', 1, 4000.00, 4000.00, 10);

SELECT hbh.issue_invoice((SELECT v FROM a3_fx WHERE k='inv'));

INSERT INTO hbh.payments (center_id, invoice_id, amount, method_code)
VALUES ((SELECT v FROM a3_fx WHERE k='center'), (SELECT v FROM a3_fx WHERE k='inv'), 1500.00, 'CASH');

INSERT INTO hbh.invoices (center_id, branch_id, invoice_no, child_id, guardian_id, currency_code)
SELECT c.center_id, (SELECT v FROM a3_fx WHERE k='branch'),
       hbh.next_number(c.center_id, 'INVOICE'),
       (SELECT v FROM a3_fx WHERE k='child_a'),
       (SELECT g.guardian_id FROM hbh.guardians g JOIN hbh.users u ON u.user_id = g.user_id
         WHERE u.username = 'a3_parent_a'),
       c.currency_code
FROM   hbh.centers c WHERE c.code = 'HBH';
INSERT INTO a3_fx (k, v) SELECT 'inv_draft', max(invoice_id) FROM hbh.invoices
 WHERE child_id = (SELECT v FROM a3_fx WHERE k='child_a')
 AND   invoice_id <> (SELECT v FROM a3_fx WHERE k='inv');

SELECT set_config('hbh.user_id', '', false);

-- ---------------------------------------------------------------------
-- The fixture asserts itself, by name, before any test runs
-- ---------------------------------------------------------------------
DO $assert$
DECLARE n integer; t text;
BEGIN
  SELECT count(*) INTO n FROM hbh.children WHERE child_no LIKE 'A3-%';
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: expected 2 children, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.therapy_sessions s
   JOIN hbh.children c ON c.child_id = s.child_id
   WHERE c.child_no = 'A3-A' AND s.status = 'IN_PROGRESS';
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: the session is not running - every live check would pass for the wrong reason'; END IF;

  SELECT count(*) INTO n FROM hbh.cameras WHERE code = 'A3-CAM1' AND active_flg;
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: no camera on the room'; END IF;

  -- The two guardians of ONE child that differ only in the flag. This is
  -- the whole live-view test, so it is asserted before it is used.
  SELECT count(*) INTO n
  FROM   hbh.guardian_children gc
  JOIN   hbh.guardians g ON g.guardian_id = gc.guardian_id
  JOIN   hbh.users u     ON u.user_id = g.user_id
  JOIN   hbh.children c  ON c.child_id = gc.child_id AND c.child_no = 'A3-A'
  WHERE (u.username = 'a3_parent_a' AND gc.can_view_live_flg)
     OR (u.username = 'a3_parent_c' AND NOT gc.can_view_live_flg);
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: the two guardians of child A do not differ in can_view_live_flg (found %)', n; END IF;

  SELECT count(*) INTO n FROM hbh.activity_log al
   JOIN hbh.children c ON c.child_id = al.child_id WHERE c.child_no = 'A3-A';
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: expected 2 logged days, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.parent_requests pr
   JOIN hbh.children c ON c.child_id = pr.child_id WHERE c.child_no = 'A3-A';
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: expected 1 request, found %', n; END IF;

  SELECT status INTO t FROM hbh.invoices
   WHERE invoice_id = (SELECT max(invoice_id) FROM hbh.invoices i
                        JOIN hbh.children c ON c.child_id = i.child_id
                        WHERE c.child_no = 'A3-A' AND i.status <> 'DRAFT');
  IF t IS NULL OR t = 'DRAFT' THEN RAISE EXCEPTION 'fixture: no issued invoice'; END IF;

  SELECT count(*) INTO n FROM hbh.invoices i
   JOIN hbh.children c ON c.child_id = i.child_id
   WHERE c.child_no = 'A3-A' AND i.status = 'DRAFT';
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: expected exactly 1 draft invoice, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.child_packages cp
   JOIN hbh.children c ON c.child_id = cp.child_id WHERE c.child_no = 'A3-A';
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: expected 1 package, found %', n; END IF;

  -- And the gateway must still be refusing, because the suite tests that
  -- refusal before it configures anything.
  IF hbh.param(NULL, 'MEDIA_GATEWAY_BASE_URL', '') <> '' THEN
    RAISE EXCEPTION 'fixture: the media gateway is already configured - the fail-closed test would pass vacuously';
  END IF;
END
$assert$;

\echo 'fixture a3: ready'
