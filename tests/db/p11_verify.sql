-- =====================================================================
-- Hand By Hand (new) - PHASE 11 acceptance suite
--
-- Must print:  PHASE 11 ACCEPTED
--
-- The last of the gaps: a course of sessions, the waiting list,
-- assessments, attachments, and the two operational things nobody
-- notices until the day they matter - the audit archive and a backup
-- somebody actually verified.
--
-- Migrations 0022 · 0023 · 0024 · 0025.
-- =====================================================================

\set ON_ERROR_STOP off
\pset pager off

DROP SCHEMA IF EXISTS hbh_test CASCADE;
CREATE SCHEMA hbh_test;

CREATE TABLE hbh_test.run (started timestamptz NOT NULL DEFAULT now());
INSERT INTO hbh_test.run DEFAULT VALUES;

CREATE TABLE hbh_test.results (
  seq integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  grp text NOT NULL, name text NOT NULL, ok boolean NOT NULL, detail text);
CREATE TABLE hbh_test.fx  (k text PRIMARY KEY, v integer);
CREATE TABLE hbh_test.fxb (k text PRIMARY KEY, v bigint);
CREATE TABLE hbh_test.fxt (k text PRIMARY KEY, v timestamptz);

CREATE PROCEDURE hbh_test.chk(p_grp text, p_name text, p_sql text)
LANGUAGE plpgsql AS $$
DECLARE v_ok boolean;
BEGIN
  BEGIN
    EXECUTE p_sql INTO v_ok;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, coalesce(v_ok, false),
            CASE WHEN coalesce(v_ok, false) THEN 'ok'
                 WHEN v_ok IS NULL THEN 'returned NULL' ELSE 'returned false' END);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, SQLSTATE || ' ' || SQLERRM);
  END;
END $$;

CREATE PROCEDURE hbh_test.chk_raises(p_grp text, p_name text, p_sql text, p_sqlstate text)
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, 'expected ' || p_sqlstate || ', statement succeeded');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, SQLSTATE = p_sqlstate,
            'expected ' || p_sqlstate || ', got ' || SQLSTATE || ' ' || SQLERRM);
  END;
END $$;

GRANT USAGE ON SCHEMA hbh_test TO hbh_app;
GRANT INSERT, SELECT ON hbh_test.results TO hbh_app;
GRANT INSERT, SELECT ON hbh_test.fx, hbh_test.fxb, hbh_test.fxt TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE
-- =====================================================================
INSERT INTO hbh_test.fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO hbh_test.fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh_test.fxt (k, v) VALUES
  ('w1_start', (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                + interval '7 days' + interval '10 hours') AT TIME ZONE 'Africa/Cairo'),
  ('w1_end',   (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                + interval '7 days' + interval '10 hours 45 minutes') AT TIME ZONE 'Africa/Cairo'),
  -- the third Monday, which a public holiday will close
  ('w3_start', (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                + interval '21 days') AT TIME ZONE 'Africa/Cairo'),
  ('w3_end',   (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                + interval '22 days') AT TIME ZONE 'Africa/Cairo'),
  -- an afternoon slot, outside one family's window
  ('pm_start', (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                + interval '8 days' + interval '15 hours') AT TIME ZONE 'Africa/Cairo'),
  ('pm_end',   (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                + interval '8 days' + interval '15 hours 45 minutes') AT TIME ZONE 'Africa/Cairo'),
  ('am_start', (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                + interval '8 days' + interval '10 hours') AT TIME ZONE 'Africa/Cairo'),
  ('am_end',   (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                + interval '8 days' + interval '10 hours 45 minutes') AT TIME ZONE 'Africa/Cairo');

INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'PB-SPEECH', 'تخاطب — اختبار ١١', 'SPEECH');
INSERT INTO hbh_test.fx (k, v) SELECT 'svc', service_id FROM hbh.services WHERE code='PB-SPEECH';

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'PB-R1', 'غرفة اختبار ١١');
INSERT INTO hbh_test.fx (k, v) SELECT 'room', room_id FROM hbh.rooms WHERE code='PB-R1';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile
FROM (VALUES
       ('pb.therapist', 'أخصائي اختبار ١١',  'THERAPIST', '+201200000001'),
       ('pb.reception', 'استقبال اختبار ١١', 'STAFF',     '+201200000002'),
       ('pb.guardian',  'ولي أمر اختبار ١١', 'GUARDIAN',  '+201200000003'),
       ('pb.owner',     'مديرة اختبار ١١',   'STAFF',     '+201200000004')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh_test.fx (k, v) SELECT 'user_th', user_id FROM hbh.users WHERE username='pb.therapist';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_rc', user_id FROM hbh.users WHERE username='pb.reception';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_gd', user_id FROM hbh.users WHERE username='pb.guardian';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_ow', user_id FROM hbh.users WHERE username='pb.owner';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT f.v, r.role_id
FROM   hbh_test.fx f
JOIN   hbh.roles r ON r.center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
WHERE  (f.k = 'user_th' AND r.code = 'THERAPIST')
   OR  (f.k = 'user_rc' AND r.code = 'RECEPTION')
   OR  (f.k = 'user_gd' AND r.code = 'GUARDIAN')
   OR  (f.k = 'user_ow' AND r.code = 'CENTER_ADMIN');

INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_th'), 'أخصائي اختبار ١١');
INSERT INTO hbh_test.fx (k, v) SELECT 'th', therapist_id FROM hbh.therapists WHERE full_name_ar='أخصائي اختبار ١١';

INSERT INTO hbh.therapist_services (therapist_id, service_id)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='svc'));

INSERT INTO hbh.therapist_working_hours (center_id, therapist_id, weekday, start_time, end_time)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='th'),
       d, TIME '09:00', TIME '17:00'
FROM unnest(ARRAY[7,1,2,3,4]::smallint[]) AS d;

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'PB-A', 'طفل اختبار ١١ أ', DATE '2020-11-11', 'M'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'PB-B', 'طفل اختبار ١١ ب', DATE '2021-01-15', 'F');
INSERT INTO hbh_test.fx (k, v) SELECT 'child',   child_id FROM hbh.children WHERE child_no='PB-A';
INSERT INTO hbh_test.fx (k, v) SELECT 'child_b', child_id FROM hbh.children WHERE child_no='PB-B';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_gd'), 'ولي أمر اختبار ١١', '+201200000003');
INSERT INTO hbh_test.fx (k, v) SELECT 'gd', guardian_id FROM hbh.guardians WHERE mobile='+201200000003';

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='gd'), (SELECT v FROM hbh_test.fx WHERE k='child'), 'FATHER', true);

INSERT INTO hbh.caseload (center_id, therapist_id, child_id, service_id)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='th'),
        (SELECT v FROM hbh_test.fx WHERE k='child'), (SELECT v FROM hbh_test.fx WHERE k='svc'));

-- The third Monday is a public holiday, so a four-week course has a
-- hole in it and the booking has to say so.
INSERT INTO hbh.schedule_blocks (center_id, scope, starts_at, ends_at, reason_code, note_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'CENTER',
        (SELECT v FROM hbh_test.fxt WHERE k='w3_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='w3_end'), 'HOLIDAY', 'عطلة رسمية — اختبار ١١');
INSERT INTO hbh_test.fx (k, v) SELECT 'blk', block_id FROM hbh.schedule_blocks
  WHERE note_ar = 'عطلة رسمية — اختبار ١١';

INSERT INTO hbh.assessment_instruments (center_id, code, name_ar, domain_code, scoring_kind,
                                        min_score, max_score, age_from_mon, age_to_mon)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'PB-LANG', 'مقياس اللغة — اختبار',
        'SPEECH', 'RAW', 0, 30, 24, 84);
INSERT INTO hbh_test.fx (k, v) SELECT 'instr', instrument_id FROM hbh.assessment_instruments WHERE code='PB-LANG';

INSERT INTO hbh.assessment_items (center_id, instrument_id, item_no, prompt_ar, max_score, sort_order)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='instr'),
        1, 'يسمّي عشرة أشياء مألوفة', 10, 10),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='instr'),
        2, 'يكوّن جملة من ثلاث كلمات', 10, 20);
INSERT INTO hbh_test.fx (k, v) SELECT 'item1', item_id FROM hbh.assessment_items
  WHERE instrument_id = (SELECT v FROM hbh_test.fx WHERE k='instr') AND item_no = 1;
INSERT INTO hbh_test.fx (k, v) SELECT 'item2', item_id FROM hbh.assessment_items
  WHERE instrument_id = (SELECT v FROM hbh_test.fx WHERE k='instr') AND item_no = 2;

-- ---------------------------------------------------------------------
CALL hbh_test.chk('fixture', 'migrations 0022 to 0025 recorded',
  $q$ SELECT count(*) = 4 FROM hbh.schema_migrations
      WHERE version IN ('0022','0023','0024','0025') $q$);

CALL hbh_test.chk('fixture', 'the third Monday is closed',
  $q$ SELECT reason = 'CENTER_CLOSED' FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room'),
        (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='w1_start') + interval '14 days',
        (SELECT v FROM hbh_test.fxt WHERE k='w1_end')   + interval '14 days') $q$);

CALL hbh_test.chk('fixture', 'the instrument has two items worth ten each',
  $q$ SELECT count(*) = 2 AND sum(max_score) = 20 FROM hbh.assessment_items
      WHERE instrument_id = (SELECT v FROM hbh_test.fx WHERE k='instr') $q$);

CALL hbh_test.chk('fixture', 'the audit archive starts empty and archiving is OFF',
  $q$ SELECT hbh.param(NULL, 'AUDIT_ARCHIVE_AFTER_DAYS', 'x') = '0' $q$);

-- =====================================================================
-- 1. A COURSE OF SESSIONS
--
-- Four weekly appointments across a public holiday. The honest outcome
-- is three bookings and one refusal with a reason - not a failure of
-- all four, and not a silent hole reception finds out about in six
-- weeks.
-- =====================================================================
SET hbh.user_id = 'pb.reception';

CALL hbh_test.chk('course', 'a four-week course reports on all four weeks',
  $q$ SELECT count(*) = 4 FROM hbh.book_recurring(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='child'),  (SELECT v FROM hbh_test.fx WHERE k='th'),
        (SELECT v FROM hbh_test.fx WHERE k='room'),   (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='w1_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='w1_end'), 4::smallint) $q$);

CALL hbh_test.chk('course', 'three of them were booked',
  $q$ SELECT count(*) = 3 FROM hbh.appointments
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child')
        AND recurrence_group_id IS NOT NULL $q$);

CALL hbh_test.chk('course', 'they share one group and are numbered 1, 2 and 4',
  $q$ SELECT count(DISTINCT recurrence_group_id) = 1
             AND array_agg(recurrence_index ORDER BY recurrence_index) = ARRAY[1,2,4]::smallint[]
      FROM hbh.appointments
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child')
        AND recurrence_group_id IS NOT NULL $q$);

CALL hbh_test.chk('course', 'and the missing week is week 3, refused as CENTER_CLOSED',
  $q$ SELECT NOT ok AND reason = 'CENTER_CLOSED' FROM hbh.book_recurring(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='child_b'), (SELECT v FROM hbh_test.fx WHERE k='th'),
        (SELECT v FROM hbh_test.fx WHERE k='room'),    (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='w1_start') + interval '14 days',
        (SELECT v FROM hbh_test.fxt WHERE k='w1_end')   + interval '14 days', 1::smallint) $q$);

INSERT INTO hbh_test.fxb (k, v)
SELECT 'group', recurrence_group_id FROM hbh.appointments
WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child') AND recurrence_group_id IS NOT NULL
LIMIT 1;

CALL hbh_test.chk_raises('course', 'cancelling a course with no stated reason is refused',
  $q$ SELECT hbh.cancel_recurrence((SELECT v FROM hbh_test.fxb WHERE k='group'), now(), '') $q$,
  'HB101');

-- Only what has not happened is withdrawn.
CALL hbh_test.chk('course', 'cancelling from week 2 onwards takes two, not three',
  $q$ SELECT hbh.cancel_recurrence((SELECT v FROM hbh_test.fxb WHERE k='group'),
        (SELECT v FROM hbh_test.fxt WHERE k='w1_start') + interval '5 days',
        'الأخصائي في تدريب') = 2 $q$);

CALL hbh_test.chk('course', 'and the first week is untouched',
  $q$ SELECT status = 'BOOKED' FROM hbh.appointments
      WHERE recurrence_group_id = (SELECT v FROM hbh_test.fxb WHERE k='group')
        AND recurrence_index = 1 $q$);

RESET hbh.user_id;
SET hbh.user_id = 'pb.guardian';
CALL hbh_test.chk_raises('course', 'a guardian cannot book a course - HB101',
  $q$ SELECT hbh.book_recurring(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='child'),  (SELECT v FROM hbh_test.fx WHERE k='th'),
        (SELECT v FROM hbh_test.fx WHERE k='room'),   (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='am_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='am_end'), 1::smallint) $q$, 'HB101');
RESET hbh.user_id;

-- =====================================================================
-- 2. THE WAITING LIST
--
-- The window is the whole point: a family that cannot come on a Tuesday
-- afternoon is not a candidate for a Tuesday afternoon, however long
-- they have waited.
-- =====================================================================
SET hbh.user_id = 'pb.reception';

CALL hbh_test.chk('wait', 'a morning-only family joins the list',
  $q$ WITH w AS (SELECT hbh.add_to_waiting_list(
                   (SELECT v FROM hbh_test.fx WHERE k='child'),
                   (SELECT v FROM hbh_test.fx WHERE k='svc'),
                   NULL, 5::smallint, current_date, NULL,
                   '{1,2,3,4,7}'::smallint[], TIME '09:00', TIME '12:00') AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'wait_am', id FROM w RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('wait', 'and an all-day family with a lower priority number joins too',
  $q$ WITH w AS (SELECT hbh.add_to_waiting_list(
                   (SELECT v FROM hbh_test.fx WHERE k='child_b'),
                   (SELECT v FROM hbh_test.fx WHERE k='svc'),
                   NULL, 2::smallint, current_date, NULL,
                   '{1,2,3,4,7}'::smallint[], TIME '09:00', TIME '17:00') AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'wait_all', id FROM w RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk_raises('wait', 'a second live entry for the same child and service is refused',
  $q$ SELECT hbh.add_to_waiting_list((SELECT v FROM hbh_test.fx WHERE k='child'),
        (SELECT v FROM hbh_test.fx WHERE k='svc')) $q$, '23505');

-- A morning slot suits both; the priority decides the order.
CALL hbh_test.chk('wait', 'a morning slot has two candidates, priority first',
  $q$ SELECT count(*) = 2
             AND (array_agg(wait_id ORDER BY priority))[1] = (SELECT v FROM hbh_test.fx WHERE k='wait_all')
      FROM hbh.waiting_candidates(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='am_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='am_end')) $q$);

-- The one that matters. An afternoon slot suits only the family that
-- can come in the afternoon.
CALL hbh_test.chk('wait', 'an afternoon slot has only ONE - the window is respected',
  $q$ SELECT count(*) = 1
             AND (array_agg(wait_id))[1] = (SELECT v FROM hbh_test.fx WHERE k='wait_all')
      FROM hbh.waiting_candidates(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='pm_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='pm_end')) $q$);

CALL hbh_test.chk('wait', 'a Friday slot has none at all - nobody listed a weekend',
  $q$ SELECT count(*) = 0 FROM hbh.waiting_candidates(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='am_start') + interval '4 days',
        (SELECT v FROM hbh_test.fxt WHERE k='am_end')   + interval '4 days') $q$);

CALL hbh_test.chk('wait', 'a slot is offered and the hold has an expiry',
  $q$ SELECT hbh.offer_slot((SELECT v FROM hbh_test.fx WHERE k='wait_am'),
        (SELECT appointment_id FROM hbh.appointments
         WHERE recurrence_group_id = (SELECT v FROM hbh_test.fxb WHERE k='group')
           AND recurrence_index = 1)) > now() $q$);

CALL hbh_test.chk('wait', 'the entry is OFFERED and names the appointment',
  $q$ SELECT status = 'OFFERED' AND offered_appointment_id IS NOT NULL
             AND offer_expires_at IS NOT NULL
      FROM hbh.waiting_list WHERE wait_id = (SELECT v FROM hbh_test.fx WHERE k='wait_am') $q$);

CALL hbh_test.chk('wait', 'an offered entry is no longer a candidate for other slots',
  $q$ SELECT count(*) = 1 FROM hbh.waiting_candidates(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='am_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='am_end')) $q$);

CALL hbh_test.chk('wait', 'accepting it books the entry',
  $q$ SELECT hbh.accept_offer((SELECT v FROM hbh_test.fx WHERE k='wait_am')) $q$);

CALL hbh_test.chk_raises('wait', 'accepting twice is refused - HB102',
  $q$ SELECT hbh.accept_offer((SELECT v FROM hbh_test.fx WHERE k='wait_am')) $q$, 'HB102');

CALL hbh_test.chk_raises('wait', 'WAITING straight to BOOKED is refused by the machine',
  $q$ UPDATE hbh.waiting_list SET status = 'BOOKED'
      WHERE wait_id = (SELECT v FROM hbh_test.fx WHERE k='wait_all') $q$, 'HB100');

-- An offer nobody answers must not block the slot for ever.
CALL hbh_test.chk('wait', 'an offer is made on the second entry and back-dated past its hold',
  $q$ WITH o AS (SELECT hbh.offer_slot((SELECT v FROM hbh_test.fx WHERE k='wait_all'),
                   (SELECT appointment_id FROM hbh.appointments
                    WHERE recurrence_group_id = (SELECT v FROM hbh_test.fxb WHERE k='group')
                      AND recurrence_index = 1)))
      SELECT count(*) = 1 FROM o $q$);

CALL hbh_test.chk('wait', 'its expiry is moved into the past',
  $q$ WITH u AS (UPDATE hbh.waiting_list SET offer_expires_at = now() - interval '1 minute'
                  WHERE wait_id = (SELECT v FROM hbh_test.fx WHERE k='wait_all') RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

CALL hbh_test.chk_raises('wait', 'the lapsed offer cannot be accepted - HB102',
  $q$ SELECT hbh.accept_offer((SELECT v FROM hbh_test.fx WHERE k='wait_all')) $q$, 'HB102');

CALL hbh_test.chk('wait', 'release_expired_offers puts it back in the queue',
  $q$ SELECT hbh.release_expired_offers() >= 1 $q$);

CALL hbh_test.chk('wait', 'and it is WAITING again, keeping its place',
  $q$ SELECT status = 'WAITING' AND offered_appointment_id IS NULL
      FROM hbh.waiting_list WHERE wait_id = (SELECT v FROM hbh_test.fx WHERE k='wait_all') $q$);

RESET hbh.user_id;

SET ROLE hbh_app;
SET hbh.user_id = 'pb.guardian';
CALL hbh_test.chk('wait', 'a family sees their own place and nobody else place',
  $q$ SELECT count(*) = 1 AND bool_and(child_id = (SELECT v FROM hbh_test.fx WHERE k='child'))
      FROM hbh.waiting_list $q$);
RESET hbh.user_id;
RESET ROLE;

-- =====================================================================
-- 3. ASSESSMENTS
-- =====================================================================
SET hbh.user_id = 'pb.reception';
CALL hbh_test.chk_raises('assess', 'reception cannot record an assessment - HB111',
  $q$ SELECT hbh.record_assessment((SELECT v FROM hbh_test.fx WHERE k='child'),
        (SELECT v FROM hbh_test.fx WHERE k='instr'), (SELECT v FROM hbh_test.fx WHERE k='th')) $q$,
  'HB111');

SET hbh.user_id = 'pb.therapist';
CALL hbh_test.chk('assess', 'the therapist records one',
  $q$ WITH a AS (SELECT hbh.record_assessment((SELECT v FROM hbh_test.fx WHERE k='child'),
                   (SELECT v FROM hbh_test.fx WHERE k='instr'),
                   (SELECT v FROM hbh_test.fx WHERE k='th'), current_date, NULL,
                   'تقييم مبدئي') AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'asmt', id FROM a RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('assess', 'and the child age in months was computed, not typed',
  $q$ SELECT age_at_months > 40 AND status = 'DRAFT' FROM hbh.assessments
      WHERE assessment_id = (SELECT v FROM hbh_test.fx WHERE k='asmt') $q$);

CALL hbh_test.chk_raises('assess', 'a score above the item maximum is refused - HB113',
  $q$ INSERT INTO hbh.assessment_item_scores (center_id, assessment_id, item_id, score)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
              (SELECT v FROM hbh_test.fx WHERE k='asmt'),
              (SELECT v FROM hbh_test.fx WHERE k='item1'), 11) $q$, 'HB113');

CALL hbh_test.chk('assess', 'two item scores are recorded',
  $q$ WITH s AS (INSERT INTO hbh.assessment_item_scores (center_id, assessment_id, item_id, score)
                 VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
                         (SELECT v FROM hbh_test.fx WHERE k='asmt'),
                         (SELECT v FROM hbh_test.fx WHERE k='item1'), 7),
                        ((SELECT v FROM hbh_test.fx WHERE k='center'),
                         (SELECT v FROM hbh_test.fx WHERE k='asmt'),
                         (SELECT v FROM hbh_test.fx WHERE k='item2'), 4)
                 RETURNING 1)
      SELECT count(*) = 2 FROM s $q$);

-- Same rule as an invoice total: derived, not typed.
CALL hbh_test.chk('assess', 'the raw score followed the items by itself',
  $q$ SELECT raw_score = 11 FROM hbh.assessments
      WHERE assessment_id = (SELECT v FROM hbh_test.fx WHERE k='asmt') $q$);

CALL hbh_test.chk_raises('assess', 'a DRAFT cannot be published - HB110',
  $q$ SELECT hbh.publish_assessment((SELECT v FROM hbh_test.fx WHERE k='asmt')) $q$, 'HB110');

CALL hbh_test.chk('assess', 'it is completed',
  $q$ WITH u AS (UPDATE hbh.assessments SET status = 'COMPLETED',
                     recommendation_ar = 'جلستان أسبوعيًا'
                  WHERE assessment_id = (SELECT v FROM hbh_test.fx WHERE k='asmt') RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

SET hbh.user_id = 'pb.reception';
CALL hbh_test.chk_raises('assess', 'reception cannot publish it either - HB111',
  $q$ SELECT hbh.publish_assessment((SELECT v FROM hbh_test.fx WHERE k='asmt')) $q$, 'HB111');

SET hbh.user_id = 'pb.therapist';
CALL hbh_test.chk('assess', 'the therapist publishes it',
  $q$ WITH p AS (SELECT hbh.publish_assessment((SELECT v FROM hbh_test.fx WHERE k='asmt')))
      SELECT count(*) = 1 FROM p $q$);

CALL hbh_test.chk('assess', 'and it is stamped with who published it',
  $q$ SELECT status = 'PUBLISHED' AND published_by IS NOT NULL AND published_at IS NOT NULL
      FROM hbh.assessments WHERE assessment_id = (SELECT v FROM hbh_test.fx WHERE k='asmt') $q$);

CALL hbh_test.chk('assess', 'the family was notified',
  $q$ SELECT count(*) = 1 FROM hbh.notifications
      WHERE kind_code = 'ASSESSMENT_PUBLISHED'
        AND link_id = (SELECT v FROM hbh_test.fx WHERE k='asmt') $q$);

-- Frozen. A family reading a result in March finds it in September.
CALL hbh_test.chk_raises('assess', 'a published assessment cannot be edited - HB112',
  $q$ UPDATE hbh.assessments SET summary_ar = 'تعديل بعد النشر'
      WHERE assessment_id = (SELECT v FROM hbh_test.fx WHERE k='asmt') $q$, 'HB112');

CALL hbh_test.chk_raises('assess', 'and neither can its item scores',
  $q$ UPDATE hbh.assessment_item_scores SET score = 1
      WHERE assessment_id = (SELECT v FROM hbh_test.fx WHERE k='asmt') $q$, 'HB112');

RESET hbh.user_id;
SET ROLE hbh_app;

SET hbh.user_id = 'pb.guardian';
CALL hbh_test.chk('assess', 'the family sees the published assessment',
  $q$ SELECT count(*) = 1 FROM hbh.assessments $q$);

-- The item scores are working detail. A family gets the summary and the
-- recommendation, not the prompts a clinician ticked.
CALL hbh_test.chk('assess', 'and none of the individual item scores',
  $q$ SELECT count(*) = 0 FROM hbh.assessment_item_scores $q$);

RESET hbh.user_id;
RESET ROLE;

-- =====================================================================
-- 4. ATTACHMENTS
-- =====================================================================
SET hbh.user_id = 'pb.therapist';

CALL hbh_test.chk_raises('file', 'video is refused outright - HB122',
  $q$ SELECT hbh.attach_file('CHILD', (SELECT v FROM hbh_test.fx WHERE k='child'),
        (SELECT v FROM hbh_test.fx WHERE k='child'), 'session.mp4', 'video/mp4',
        '\x00010203'::bytea) $q$, 'HB122');

-- And the constraint refuses it even if the function is bypassed. The
-- permanent rule is structural, not a sentence in a document.
CALL hbh_test.chk_raises('file', 'and the constraint refuses it by direct INSERT too',
  $q$ INSERT INTO hbh.attachments (center_id, owner_kind, owner_id, file_name, mime_type,
                                   size_bytes, sha256, storage_kind, content)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'CHILD', 1, 'x.mp4', 'video/mp4',
              4, public.digest('abcd', 'sha256'), 'DB', '\x00010203'::bytea) $q$, '23514');

CALL hbh_test.chk('file', 'a report is attached',
  $q$ WITH a AS (SELECT hbh.attach_file('CHILD', (SELECT v FROM hbh_test.fx WHERE k='child'),
                   (SELECT v FROM hbh_test.fx WHERE k='child'), 'school-report.pdf',
                   'application/pdf', convert_to('تقرير المدرسة للطفل', 'UTF8'),
                   'تقرير من المدرسة') AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'att', id FROM a RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('file', 'it is born INTERNAL with no approver',
  $q$ SELECT visibility = 'INTERNAL' AND approved_by IS NULL FROM hbh.attachments
      WHERE attachment_id = (SELECT v FROM hbh_test.fx WHERE k='att') $q$);

CALL hbh_test.chk('file', 'its digest and size were computed, not supplied',
  $q$ SELECT size_bytes = length(content) AND sha256 = public.digest(content, 'sha256')
      FROM hbh.attachments WHERE attachment_id = (SELECT v FROM hbh_test.fx WHERE k='att') $q$);

-- The headline. trg_audit would have copied the whole file into
-- audit_log, twice for an update.
CALL hbh_test.chk('file', 'the audit log recorded the upload WITHOUT the bytes',
  $q$ SELECT count(*) = 1 FROM hbh.audit_log
      WHERE table_name = 'attachments'
        AND row_pk = (SELECT v FROM hbh_test.fx WHERE k='att')::text
        AND new_data ? 'file_name'
        AND NOT (new_data ? 'content') $q$);

CALL hbh_test.chk('file', 'and the index view carries no content column at all',
  $q$ SELECT count(*) = 0 FROM information_schema.columns
      WHERE table_schema = 'hbh' AND table_name = 'v_attachment_index'
        AND column_name = 'content' $q$);

CALL hbh_test.chk_raises('file', 'the bytes cannot be replaced afterwards - HB120',
  $q$ UPDATE hbh.attachments SET content = '\xdeadbeef'::bytea,
             sha256 = public.digest('\xdeadbeef'::bytea, 'sha256')
      WHERE attachment_id = (SELECT v FROM hbh_test.fx WHERE k='att') $q$, 'HB120');

RESET hbh.user_id;
SET ROLE hbh_app;

SET hbh.user_id = 'pb.guardian';
CALL hbh_test.chk('file', 'the family cannot see it while it is internal',
  $q$ SELECT count(*) = 0 FROM hbh.attachments $q$);

RESET hbh.user_id;
RESET ROLE;

SET hbh.user_id = 'pb.therapist';
CALL hbh_test.chk('file', 'the therapist publishes it',
  $q$ WITH p AS (SELECT hbh.publish_attachment((SELECT v FROM hbh_test.fx WHERE k='att')))
      SELECT count(*) = 1 FROM p $q$);

CALL hbh_test.chk('file', 'and all three facts now agree',
  $q$ SELECT visibility = 'PARENT' AND approved_by IS NOT NULL AND approved_at IS NOT NULL
      FROM hbh.attachments WHERE attachment_id = (SELECT v FROM hbh_test.fx WHERE k='att') $q$);

RESET hbh.user_id;
SET ROLE hbh_app;
SET hbh.user_id = 'pb.guardian';
CALL hbh_test.chk('file', 'and NOW the family sees it',
  $q$ SELECT count(*) = 1 FROM hbh.attachments $q$);
RESET hbh.user_id;
RESET ROLE;

-- =====================================================================
-- 4b. A CHILD'S PHOTOGRAPH
--
-- Migrations 0074 and 0076. A portrait is an attachment like any other
-- file about a child - same digest, same soft delete, same approval
-- gate, same audit trigger that strips the bytes - with two things
-- added: it says what it is FOR, and it cannot exist without a recorded
-- PHOTO_USE consent.
--
-- THESE EXIST BECAUSE 0074 SHIPPED BROKEN AND LOOKED FINE. It asked for
-- consent_type = 'PHOTO'; the schema calls it 'PHOTO_USE'. The refusal
-- check passed - it always would have, because the gate was shut for
-- everybody - and only recording the consent and expecting the upload
-- to go through showed it. A refusal check with no acceptance check
-- after it does not prove a gate opens, only that it is closed.
--
-- The fixture is asserted by name first: a receptionist who did not
-- actually hold these two grants would produce a permission refusal
-- that reads exactly like a missing consent.
-- =====================================================================
CALL hbh_test.chk('photo', 'the receptionist holds both grants this section needs',
  $q$ SELECT count(DISTINCT p.code) = 2
      FROM   hbh.user_roles ur
      JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id AND rp.active_flg
      JOIN   hbh.permissions p       ON p.permission_id = rp.permission_id
      WHERE  ur.user_id = (SELECT v FROM hbh_test.fx WHERE k='user_rc')
        AND  ur.active_flg
        AND  p.code IN ('ATTACHMENT.UPLOAD', 'GUARDIAN.MANAGE') $q$);

-- The starting state is MADE, not assumed.
--
-- "No consent is on record yet" reads like a safe assumption on a fresh
-- database and is not one: p9 records PHOTO_USE consents of its own,
-- child ids are reused after a hard delete, and a suite that left rows
-- behind hands the next run a child that already has one. Any of those
-- turns the refusal check below into a check that silently tests
-- nothing - it would report "statement succeeded" and look like the
-- gate had failed, when the gate was never armed.
--
-- Scoped to this fixture's own child, so it cannot reach a neighbour's
-- consent. Written as an UPDATE rather than hbh.withdraw_consent
-- because that function raises when there is nothing to withdraw, and
-- "nothing to withdraw" is the ordinary case here.
UPDATE hbh.consents SET granted_flg = false, withdrawn_at = now()
 WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child')
   AND consent_type = 'PHOTO_USE' AND granted_flg;

CALL hbh_test.chk('photo', 'and no PHOTO_USE consent is on record for this child',
  $q$ SELECT count(*) = 0 FROM hbh.consents
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child')
        AND consent_type = 'PHOTO_USE' AND granted_flg AND active_flg $q$);

SET hbh.user_id = 'pb.reception';

CALL hbh_test.chk_raises('photo', 'a portrait with no recorded consent is refused - HB123',
  $q$ SELECT hbh.set_child_photo((SELECT v FROM hbh_test.fx WHERE k='child'),
        'portrait.jpg', 'image/jpeg', '\xffd8ffe000'::bytea) $q$, 'HB123');

-- The gate reads PURPOSE, not mime type, and this is the check that
-- keeps it that way. A scanned school report is image/jpeg. A gate
-- written as "an image on a child needs consent" would refuse it, and a
-- guard that produces false refusals in daily reception work is one
-- somebody eventually deletes rather than argues with.
CALL hbh_test.chk('photo', 'a scanned image that is NOT a portrait is untouched by the gate',
  $q$ WITH a AS (SELECT hbh.attach_file('CHILD', (SELECT v FROM hbh_test.fx WHERE k='child'),
                   (SELECT v FROM hbh_test.fx WHERE k='child'), 'school-scan.jpg',
                   'image/jpeg', convert_to('مسح ضوئي', 'UTF8'), NULL) AS id)
      SELECT count(*) = 1 FROM a $q$);

CALL hbh_test.chk_raises('photo', 'and a portrait must be an image - HB124',
  $q$ SELECT hbh.set_child_photo((SELECT v FROM hbh_test.fx WHERE k='child'),
        'x.pdf', 'application/pdf', '\x2525'::bytea) $q$, 'HB124');

CALL hbh_test.chk('photo', 'the guardian records a PHOTO_USE consent',
  $q$ WITH c AS (SELECT hbh.grant_consent((SELECT v FROM hbh_test.fx WHERE k='gd'),
                   'PHOTO_USE', (SELECT v FROM hbh_test.fx WHERE k='child')) AS id)
      SELECT count(*) = 1 FROM c $q$);

-- THE HALF THAT WAS MISSING.
CALL hbh_test.chk('photo', 'and NOW the portrait is accepted',
  $q$ WITH p AS (SELECT hbh.set_child_photo((SELECT v FROM hbh_test.fx WHERE k='child'),
                   'portrait.jpg', 'image/jpeg', '\xffd8ffe011'::bytea) AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'photo', id FROM p RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('photo', 'it is marked as the portrait and born INTERNAL',
  $q$ SELECT purpose = 'PROFILE_PHOTO' AND visibility = 'INTERNAL'
      FROM hbh.attachments WHERE attachment_id = (SELECT v FROM hbh_test.fx WHERE k='photo') $q$);

-- Replace, not refuse. Without the archive inside set_child_photo the
-- unique index would reject the second upload, and a receptionist would
-- be told the picture is a duplicate when what she meant was "use this
-- one now".
CALL hbh_test.chk('photo', 'a second portrait replaces the first',
  $q$ WITH p AS (SELECT hbh.set_child_photo((SELECT v FROM hbh_test.fx WHERE k='child'),
                   'portrait-2.jpg', 'image/jpeg', '\xffd8ffe022'::bytea) AS id)
      SELECT count(*) = 1 FROM p $q$);

CALL hbh_test.chk('photo', 'one portrait is active and the old one is archived, not deleted',
  $q$ SELECT count(*) FILTER (WHERE active_flg) = 1
         AND count(*) FILTER (WHERE NOT active_flg AND deleted_at IS NOT NULL) = 1
      FROM hbh.attachments
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child')
        AND purpose = 'PROFILE_PHOTO' $q$);

RESET hbh.user_id;
RESET ROLE;

-- And the index refuses a second live portrait even when the function
-- is bypassed. The rule is structural, not a step inside one door.
CALL hbh_test.chk_raises('photo', 'a second ACTIVE portrait is refused by the index',
  $q$ UPDATE hbh.attachments SET active_flg = true, deleted_at = NULL
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child')
        AND purpose = 'PROFILE_PHOTO' AND NOT active_flg $q$, '23505');

-- =====================================================================
-- 5. THE AUDIT TRAIL IS MOVED, NEVER DELETED
-- =====================================================================
CALL hbh_test.chk('archive', 'with the parameter at zero, archiving does nothing',
  $q$ SELECT hbh.archive_audit() = 0 $q$);

INSERT INTO hbh.audit_log (center_id, table_name, row_pk, action, changed_by, changed_at, detail)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'pb_probe', '1', 'READ',
        'pb-test', now() - interval '400 days', 'PB_ARCHIVE_PROBE');

CALL hbh_test.chk('archive', 'an old audit row exists in the hot table',
  $q$ SELECT count(*) = 1 FROM hbh.audit_log WHERE detail = 'PB_ARCHIVE_PROBE' $q$);

CALL hbh_test.chk('archive', 'archiving past 365 days moves it',
  $q$ SELECT hbh.archive_audit(365) >= 1 $q$);

CALL hbh_test.chk('archive', 'it is no longer in the hot table',
  $q$ SELECT count(*) = 0 FROM hbh.audit_log WHERE detail = 'PB_ARCHIVE_PROBE' $q$);

-- Moved, not shredded. This is the whole difference.
CALL hbh_test.chk('archive', 'and it IS in the archive, unchanged',
  $q$ SELECT count(*) = 1 FROM hbh.audit_log_archive WHERE detail = 'PB_ARCHIVE_PROBE' $q$);

CALL hbh_test.chk('archive', 'the trail view finds it without anybody knowing where it lives',
  $q$ SELECT archived FROM hbh.v_audit_trail WHERE detail = 'PB_ARCHIVE_PROBE' $q$);

-- The check that makes the disable/enable bounded rather than a hole.
CALL hbh_test.chk('archive', 'the audit log append-only trigger is enabled again',
  $q$ SELECT tgenabled = 'O' FROM pg_trigger WHERE tgname = 'trg_audit_log_append_only' $q$);

CALL hbh_test.chk_raises('archive', 'and the hot log still refuses a delete',
  $q$ DELETE FROM hbh.audit_log WHERE audit_id = (SELECT min(audit_id) FROM hbh.audit_log) $q$,
  'HB001');

CALL hbh_test.chk_raises('archive', 'the archive refuses one too',
  $q$ DELETE FROM hbh.audit_log_archive WHERE detail = 'PB_ARCHIVE_PROBE' $q$, 'HB001');

CALL hbh_test.chk_raises('archive', 'and refuses to be rewritten',
  $q$ UPDATE hbh.audit_log_archive SET changed_by = 'somebody else'
      WHERE detail = 'PB_ARCHIVE_PROBE' $q$, 'HB001');

SET ROLE hbh_app;
SET hbh.user_id = 'admin';
CALL hbh_test.chk_raises('archive', 'the app role cannot read the archive at all',
  $q$ SELECT count(*) FROM hbh.audit_log_archive $q$, '42501');
RESET hbh.user_id;
RESET ROLE;

-- =====================================================================
-- 6. A BACKUP NOBODY VERIFIED IS NOT A BACKUP
-- =====================================================================
CALL hbh_test.chk_raises('backup', 'a run cannot claim success without verification',
  $q$ INSERT INTO hbh.backup_runs (kind, file_name, verified_flg, ok_flg)
      VALUES ('TEST', 'pb-unverified.dump', false, true) $q$, '23514');

CALL hbh_test.chk('backup', 'a verified run is recorded',
  $q$ WITH b AS (SELECT hbh.record_backup('TEST', 'pb-test.dump', 1024,
                   repeat('a', 64), true, 40, 500, true, NULL) AS id),
           i AS (INSERT INTO hbh_test.fxb (k, v) SELECT 'backup', id FROM b RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('backup', 'and it says what it verified',
  $q$ SELECT verified_flg AND ok_flg AND verified_tables = 40 AND verified_rows = 500
      FROM hbh.backup_runs WHERE backup_id = (SELECT v FROM hbh_test.fxb WHERE k='backup') $q$);

CALL hbh_test.chk('backup', 'the health view no longer reports it stale',
  $q$ SELECT NOT is_stale AND last_verified_at IS NOT NULL FROM hbh.v_backup_health $q$);

-- The CTE below is REFERENCED. Written as a bare WITH whose result
-- nothing reads, the planner never runs it, the failure is recorded
-- nowhere and the next check then finds one TEST row instead of two.
-- Third time this shape has cost a round trip in this project.
CALL hbh_test.chk('backup', 'a failed run is recorded',
  $q$ WITH b AS (SELECT hbh.record_backup('TEST', 'pb-fail.dump', 10, repeat('b', 64),
                   false, NULL, NULL, false, 'pg_restore failed') AS id)
      SELECT count(*) = 1 FROM b $q$);

CALL hbh_test.chk('backup', 'it is counted as a failure and not as a backup',
  $q$ SELECT failures_this_week >= 1 AND NOT is_stale FROM hbh.v_backup_health $q$);

CALL hbh_test.chk('backup', 'the run table is not readable by the app role',
  $q$ SELECT count(*) = 0 FROM information_schema.role_table_grants
      WHERE grantee = 'hbh_app' AND table_name = 'backup_runs' $q$);

-- =====================================================================
-- 7. BACKUP HEALTH REACHES THE OWNER SCREEN - AND NOTHING ELSE DOES
--
-- hbh.backup_runs has no policy and no GRANT, and it keeps neither.
-- What the owner's dashboard gets is hbh.backup_health(): the answer,
-- behind OPS.VIEW, without the dump's file name, digest or restore
-- error text. Migration 0029.
-- =====================================================================
SET ROLE hbh_app;

SET hbh.user_id = 'pb.owner';
CALL hbh_test.chk('ops', 'the owner reads backup health',
  $q$ SELECT count(*) = 1 FROM hbh.backup_health() $q$);

CALL hbh_test.chk('ops', 'and it answers the question the screen asks',
  $q$ SELECT NOT never_verified AND NOT is_stale AND hours_since_verified >= 0
      FROM hbh.backup_health() $q$);

-- The three columns that would turn an operational reassurance into a
-- description of the server.
CALL hbh_test.chk('ops', 'it returns no file name, digest or restore error text',
  $q$ SELECT count(*) = 0 FROM information_schema.parameters
      WHERE specific_schema = 'hbh'
        AND specific_name LIKE 'backup_health%'
        AND parameter_name IN ('file_name','sha256_hex','detail') $q$);

SET hbh.user_id = 'pb.reception';
CALL hbh_test.chk_raises('ops', 'reception has no OPS.VIEW and is refused - HB130',
  $q$ SELECT count(*) FROM hbh.backup_health() $q$, 'HB130');

SET hbh.user_id = 'pb.therapist';
CALL hbh_test.chk_raises('ops', 'nor does the therapist - HB130',
  $q$ SELECT count(*) FROM hbh.backup_health() $q$, 'HB130');

-- Fails closed. No identity is not "show me the public answer".
RESET hbh.user_id;
CALL hbh_test.chk_raises('ops', 'and with no identity at all - HB130',
  $q$ SELECT count(*) FROM hbh.backup_health() $q$, 'HB130');

SET hbh.user_id = 'pb.owner';
CALL hbh_test.chk_raises('ops', 'even the owner cannot read the runs table itself',
  $q$ SELECT count(*) FROM hbh.backup_runs $q$, '42501');

RESET hbh.user_id;
RESET ROLE;

-- =====================================================================
-- CLEANUP
-- =====================================================================
CALL hbh_test.chk('cleanup', 'backup runs removed',
  $q$ WITH d AS (DELETE FROM hbh.backup_runs WHERE kind = 'TEST' RETURNING 1)
      SELECT count(*) = 2 FROM d $q$);

ALTER TABLE hbh.audit_log_archive DISABLE TRIGGER trg_arch_append_only;
CALL hbh_test.chk('cleanup', 'the probe row removed from the archive',
  $q$ WITH d AS (DELETE FROM hbh.audit_log_archive WHERE detail = 'PB_ARCHIVE_PROBE' RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);
ALTER TABLE hbh.audit_log_archive ENABLE TRIGGER trg_arch_append_only;

-- Four now, not one: the school report, the scanned image, and the two
-- portraits. At least four, then none left - a reused child id can
-- carry files from an earlier life, and the property worth asserting is
-- that nothing of this child's remains, not that the arithmetic of one
-- run came out even.
CALL hbh_test.chk('cleanup', 'attachments removed',
  $q$ WITH d AS (DELETE FROM hbh.attachments WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child','child_b')) RETURNING 1)
      SELECT count(*) >= 4 FROM d $q$);

CALL hbh_test.chk('cleanup', 'and no attachment is left on either child',
  $q$ SELECT count(*) = 0 FROM hbh.attachments WHERE child_id IN
        (SELECT v FROM hbh_test.fx WHERE k IN ('child','child_b')) $q$);

-- A recorded consent cannot simply be deleted, and that is the schema
-- being right: hbh.consent_events is append-only, and hbh.consents has
-- a foreign key from it - so a suite that records one cannot clean up
-- after itself, and the fixture child and guardian become undeletable
-- with it. Four cleanup checks failed this way before the trigger was
-- taken into account.
--
-- The pattern is p7's, including the last check: anything that turns a
-- protection off verifies it back on, or it has quietly left the audit
-- trail writable and said nothing.
--
-- One statement per level, parents last. Several data-modifying CTEs in
-- one statement have no ordering between them - it works until the plan
-- changes, and then the failure is not a bug but undefined behaviour.
--
-- Keyed by the fixture's child, never by consent_type: PHOTO_USE rows
-- belong to other families on a shared database, and a pattern is not a
-- namespace.
-- At least one, then nothing left. An exact count here would be wrong
-- for the same reason the precondition above had to be made rather than
-- assumed: this child's id may carry a consent from an earlier life,
-- and the property that matters is that NONE remains - not that this
-- run removed exactly as many as it made.
ALTER TABLE hbh.consent_events DISABLE TRIGGER trg_cev_append_only;
CALL hbh_test.chk('cleanup', 'the photograph consent events removed',
  $q$ WITH d AS (DELETE FROM hbh.consent_events
                  WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child') RETURNING 1)
      SELECT count(*) >= 1 FROM d $q$);
ALTER TABLE hbh.consent_events ENABLE TRIGGER trg_cev_append_only;

CALL hbh_test.chk('cleanup', 'the photograph consent removed',
  $q$ WITH d AS (DELETE FROM hbh.consents
                  WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child') RETURNING 1)
      SELECT count(*) >= 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'and no consent of any kind is left on this child',
  $q$ SELECT count(*) = 0 FROM hbh.consents
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child') $q$);

CALL hbh_test.chk('cleanup', 'and the append-only trigger is enabled again',
  $q$ SELECT tgenabled = 'O' FROM pg_trigger
      WHERE tgname = 'trg_cev_append_only' $q$);

-- Two triggers stand in the way of this teardown, and both are doing
-- their job: the score guard refuses to touch a published assessment,
-- and the total-recalc trigger would then try to UPDATE that same
-- published assessment and be refused by the header guard. Turning them
-- off for the teardown is right; loosening the freeze so the test could
-- clean up would be the tail wagging the dog.
ALTER TABLE hbh.assessment_item_scores DISABLE TRIGGER trg_ascore_guard;
ALTER TABLE hbh.assessments            DISABLE TRIGGER trg_asmt_guard;

CALL hbh_test.chk('cleanup', 'assessment scores removed',
  $q$ WITH d AS (DELETE FROM hbh.assessment_item_scores WHERE assessment_id =
                   (SELECT v FROM hbh_test.fx WHERE k='asmt') RETURNING 1)
      SELECT count(*) = 2 FROM d $q$);

CALL hbh_test.chk('cleanup', 'assessments removed',
  $q$ WITH d AS (DELETE FROM hbh.assessments WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child','child_b')) RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

ALTER TABLE hbh.assessments            ENABLE TRIGGER trg_asmt_guard;
ALTER TABLE hbh.assessment_item_scores ENABLE TRIGGER trg_ascore_guard;

-- Items only after the scores that reference them, and the instrument
-- only after its items.
CALL hbh_test.chk('cleanup', 'instrument items removed',
  $q$ WITH i AS (DELETE FROM hbh.assessment_items WHERE instrument_id =
                   (SELECT v FROM hbh_test.fx WHERE k='instr') RETURNING 1)
      SELECT count(*) = 2 FROM i $q$);

CALL hbh_test.chk('cleanup', 'the instrument itself removed',
  $q$ WITH d AS (DELETE FROM hbh.assessment_instruments WHERE code = 'PB-LANG' RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'waiting entries and notifications removed',
  $q$ WITH w AS (DELETE FROM hbh.waiting_list WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child','child_b')) RETURNING 1),
           n AS (DELETE FROM hbh.notifications WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'pb.%') RETURNING 1)
      SELECT (SELECT count(*) FROM w) = 2 $q$);

ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;
CALL hbh_test.chk('cleanup', 'appointment history removed',
  $q$ WITH d AS (DELETE FROM hbh.appointment_status_history WHERE appointment_id IN
                   (SELECT appointment_id FROM hbh.appointments WHERE child_id IN
                      (SELECT v FROM hbh_test.fx WHERE k IN ('child','child_b'))) RETURNING 1)
      SELECT count(*) >= 3 FROM d $q$);
ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;

CALL hbh_test.chk('cleanup', 'appointments removed',
  $q$ WITH d AS (DELETE FROM hbh.appointments WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child','child_b')) RETURNING 1)
      SELECT count(*) = 3 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the holiday block removed',
  $q$ WITH d AS (DELETE FROM hbh.schedule_blocks WHERE block_id =
                   (SELECT v FROM hbh_test.fx WHERE k='blk') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'caseload removed',
  $q$ WITH d AS (DELETE FROM hbh.caseload WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child','child_b')) RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'guardian links removed',
  $q$ WITH d AS (DELETE FROM hbh.guardian_children WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child','child_b')) RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'children removed',
  $q$ WITH d AS (DELETE FROM hbh.children WHERE child_no LIKE 'PB-%' RETURNING 1)
      SELECT count(*) = 2 FROM d $q$);

CALL hbh_test.chk('cleanup', 'guardians removed',
  $q$ WITH d AS (DELETE FROM hbh.guardians WHERE mobile LIKE '+2012000000%' AND user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'pb.%') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the rest removed',
  $q$ WITH w AS (DELETE FROM hbh.therapist_working_hours WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           ts AS (DELETE FROM hbh.therapist_services WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           t AS (DELETE FROM hbh.therapists WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           rm AS (DELETE FROM hbh.rooms    WHERE code LIKE 'PB-%' RETURNING 1),
           sv AS (DELETE FROM hbh.services WHERE code LIKE 'PB-%' RETURNING 1),
           ur AS (DELETE FROM hbh.user_roles WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'pb.%') RETURNING 1),
           u AS (DELETE FROM hbh.users WHERE username LIKE 'pb.%' RETURNING 1)
      SELECT (SELECT count(*) FROM u) = 4 $q$);

-- Every trigger this suite turned off is on again. A teardown that
-- leaves a guarantee disabled is worse than one that leaves rows.
CALL hbh_test.chk('cleanup', 'every trigger this suite disabled is enabled again',
  $q$ SELECT count(*) = 5 FROM pg_trigger
      WHERE tgname IN ('trg_arch_append_only','trg_ash_append_only',
                       'trg_audit_log_append_only','trg_ascore_guard','trg_asmt_guard')
        AND tgenabled = 'O' $q$);

-- =====================================================================
-- VERDICT
-- =====================================================================
\echo ''
SELECT grp AS "المجموعة", count(*) AS "اختبارات",
       count(*) FILTER (WHERE NOT ok) AS "فشل"
FROM hbh_test.results GROUP BY grp ORDER BY min(seq);

\echo ''
SELECT seq, grp, name, detail FROM hbh_test.results WHERE NOT ok ORDER BY seq;

DO $verdict$
DECLARE v_total integer; v_fail integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE NOT ok) INTO v_total, v_fail FROM hbh_test.results;
  RAISE NOTICE '';
  RAISE NOTICE '--------------------------------------------------';
  RAISE NOTICE '  % checks, % failed', v_total, v_fail;
  IF v_fail = 0 AND v_total > 0 THEN RAISE NOTICE '  PHASE 11 ACCEPTED';
  ELSE RAISE NOTICE '  *** PHASE 11 NOT ACCEPTED'; END IF;
  RAISE NOTICE '--------------------------------------------------';
END
$verdict$;

DO $exit$
BEGIN
  IF (SELECT count(*) FROM hbh_test.results WHERE NOT ok) > 0
     OR (SELECT count(*) FROM hbh_test.results) = 0 THEN
    RAISE EXCEPTION 'acceptance suite failed';
  END IF;
END
$exit$;
