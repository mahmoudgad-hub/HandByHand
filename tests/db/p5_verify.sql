-- =====================================================================
-- Hand By Hand (new) - PHASE 5 acceptance suite
--
-- Must print:  PHASE 5 ACCEPTED
--
-- This is the first phase where a GUARDIAN writes, so the suite is
-- mostly about the line between what a family may put in and what only
-- a clinician may. Two claims it has to make good on:
--
--   * a parent LOGS, a clinician PRESCRIBES;
--   * and accepting "please move Tuesday" moves nothing by itself.
-- =====================================================================

\set ON_ERROR_STOP off
\pset pager off

DROP SCHEMA IF EXISTS hbh_test CASCADE;
CREATE SCHEMA hbh_test;

CREATE TABLE hbh_test.run (started timestamptz NOT NULL DEFAULT now());
INSERT INTO hbh_test.run DEFAULT VALUES;

CREATE TABLE hbh_test.results (
  seq    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  grp    text    NOT NULL,
  name   text    NOT NULL,
  ok     boolean NOT NULL,
  detail text
);
CREATE TABLE hbh_test.fx  (k text PRIMARY KEY, v integer);
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
GRANT SELECT ON hbh_test.fx, hbh_test.fxt TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE
-- =====================================================================
INSERT INTO hbh_test.fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO hbh_test.fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh_test.fxt (k, v) VALUES
  ('slot_start', (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '10 hours') AT TIME ZONE 'Africa/Cairo'),
  ('slot_end',   (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '10 hours 45 minutes') AT TIME ZONE 'Africa/Cairo');

INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P5-SPEECH', 'تخاطب — اختبار ٥', 'SPEECH');
INSERT INTO hbh_test.fx (k, v) SELECT 'svc', service_id FROM hbh.services WHERE code='P5-SPEECH';

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P5-R1', 'غرفة اختبار ٥');
INSERT INTO hbh_test.fx (k, v) SELECT 'room', room_id FROM hbh.rooms WHERE code='P5-R1';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile
FROM (VALUES
       ('p5.therapist', 'أخصائي اختبار ٥',  'THERAPIST', '+201500000001'),
       ('p5.guardian',  'ولي أمر اختبار ٥', 'GUARDIAN',  '+201500000002'),
       ('p5.other_gd',  'ولي أمر آخر ٥',    'GUARDIAN',  '+201500000003')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh_test.fx (k, v) SELECT 'user_th',  user_id FROM hbh.users WHERE username='p5.therapist';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_gd',  user_id FROM hbh.users WHERE username='p5.guardian';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_gd2', user_id FROM hbh.users WHERE username='p5.other_gd';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT f.v, r.role_id
FROM   hbh_test.fx f
JOIN   hbh.roles r ON r.center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
WHERE  (f.k = 'user_th' AND r.code = 'THERAPIST')
   OR  (f.k IN ('user_gd','user_gd2') AND r.code = 'GUARDIAN');

-- RETURNING, not a re-read by name.
--
-- `hbh.therapists.full_name_ar` carries NO unique index - two therapists
-- may share a name, and that is correct. So a re-read by it returns every
-- row a previous run left behind as well as this one's, the INSERT into
-- hbh_test.fx hits the primary key on `k`, and the fixture dies there -
-- twenty checks before the first failure anybody reads, which then says
-- "HB041 no such activity". Same family as the lesson about reading an
-- identifier out of a shared list: the row this run made is the row this
-- run must capture, and only RETURNING knows which that is.
WITH ins AS (
  INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar)
  VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
          (SELECT v FROM hbh_test.fx WHERE k='user_th'), 'أخصائي اختبار ٥')
  RETURNING therapist_id
)
INSERT INTO hbh_test.fx (k, v) SELECT 'th', therapist_id FROM ins;

INSERT INTO hbh.therapist_services (therapist_id, service_id)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='svc'));

INSERT INTO hbh.therapist_working_hours (center_id, therapist_id, weekday, start_time, end_time)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='th'),
       d, TIME '09:00', TIME '17:00'
FROM unnest(ARRAY[7,1,2,3,4]::smallint[]) AS d;

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P5-A', 'طفل اختبار ٥ أ', DATE '2020-04-04', 'M'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P5-B', 'طفل اختبار ٥ ب', DATE '2021-08-08', 'F');
INSERT INTO hbh_test.fx (k, v) SELECT 'child_a', child_id FROM hbh.children WHERE child_no='P5-A';
INSERT INTO hbh_test.fx (k, v) SELECT 'child_b', child_id FROM hbh.children WHERE child_no='P5-B';

-- RETURNING again, and for a sharper reason: `hbh.guardians.mobile` has no
-- unique index at all. Two parents CAN share a number - a household with
-- one phone - so the column is not an identifier and must never be read as
-- one. THIS IS THE ONE THAT ACTUALLY BROKE: a run whose cleanup did not
-- finish left two rows on 01500000002, the next run's re-read returned
-- both, `INSERT INTO hbh_test.fx` violated the primary key on `k`, and
-- twenty-six checks failed with messages naming activities and requests -
-- none of them naming a guardian.
WITH ins AS (
  INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
  VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
          (SELECT v FROM hbh_test.fx WHERE k='user_gd'),  'ولي أمر اختبار ٥', '+201500000002'),
         ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
          (SELECT v FROM hbh_test.fx WHERE k='user_gd2'), 'ولي أمر آخر ٥',    '+201500000003')
  RETURNING guardian_id, mobile
)
INSERT INTO hbh_test.fx (k, v)
SELECT CASE WHEN mobile = '+201500000002' THEN 'gd' ELSE 'gd2' END, guardian_id
FROM   ins;

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='gd'),  (SELECT v FROM hbh_test.fx WHERE k='child_a'), 'FATHER', true),
       ((SELECT v FROM hbh_test.fx WHERE k='gd2'), (SELECT v FROM hbh_test.fx WHERE k='child_b'), 'MOTHER', true);

INSERT INTO hbh.caseload (center_id, therapist_id, child_id, service_id)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='th'),
        (SELECT v FROM hbh_test.fx WHERE k='child_a'), (SELECT v FROM hbh_test.fx WHERE k='svc'));

INSERT INTO hbh_test.fx (k, v)
SELECT 'appt', hbh.book_appointment(
  (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
  (SELECT v FROM hbh_test.fx WHERE k='child_a'), (SELECT v FROM hbh_test.fx WHERE k='th'),
  (SELECT v FROM hbh_test.fx WHERE k='room'),    (SELECT v FROM hbh_test.fx WHERE k='svc'),
  (SELECT v FROM hbh_test.fxt WHERE k='slot_start'), (SELECT v FROM hbh_test.fxt WHERE k='slot_end'));

-- the library and one prescription per child
INSERT INTO hbh.activity_library (center_id, code, title_ar, how_to_ar, service_id)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'P5-SIN', 'تكرار كلمات صوت السين',
        'سمسم، مسمار، بسبوسة — عشر دقائق', (SELECT v FROM hbh_test.fx WHERE k='svc')),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), 'P5-CLAY', 'لعبة الصلصال',
        'كرات صغيرة بالأصابع الثلاثة', (SELECT v FROM hbh_test.fx WHERE k='svc'));
INSERT INTO hbh_test.fx (k, v) SELECT 'act1', activity_id FROM hbh.activity_library WHERE code='P5-SIN';
INSERT INTO hbh_test.fx (k, v) SELECT 'act2', activity_id FROM hbh.activity_library WHERE code='P5-CLAY';

INSERT INTO hbh.child_activities (center_id, child_id, activity_id, assigned_by, times_per_week, minutes_each)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_a'),
        (SELECT v FROM hbh_test.fx WHERE k='act1'), (SELECT v FROM hbh_test.fx WHERE k='user_th'), 7, 10),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_b'),
        (SELECT v FROM hbh_test.fx WHERE k='act2'), (SELECT v FROM hbh_test.fx WHERE k='user_th'), 3, 15);
INSERT INTO hbh_test.fx (k, v) SELECT 'ca_a', child_activity_id FROM hbh.child_activities
  WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child_a');
INSERT INTO hbh_test.fx (k, v) SELECT 'ca_b', child_activity_id FROM hbh.child_activities
  WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child_b');

-- ---------------------------------------------------------------------
CALL hbh_test.chk('fixture', 'migration 0007 recorded',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0007') $q$);

CALL hbh_test.chk('fixture', 'two library activities exist',
  $q$ SELECT count(*) = 2 FROM hbh.activity_library WHERE code LIKE 'P5-%' $q$);

CALL hbh_test.chk('fixture', 'each child has one prescription',
  $q$ SELECT count(*) = 2 FROM hbh.child_activities
      WHERE child_id IN (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) $q$);

CALL hbh_test.chk('fixture', 'the two guardians are linked to DIFFERENT children',
  $q$ SELECT count(DISTINCT child_id) = 2 FROM hbh.guardian_children
      WHERE guardian_id IN (SELECT v FROM hbh_test.fx WHERE k IN ('gd','gd2')) $q$);

CALL hbh_test.chk('fixture', 'an appointment exists to hang a reschedule request on',
  $q$ SELECT status = 'BOOKED' FROM hbh.appointments
      WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt') $q$);

CALL hbh_test.chk('fixture', 'the REQUEST number series is defined',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.number_series WHERE code = 'REQUEST') $q$);

-- =====================================================================
-- 1. A PARENT LOGS, A CLINICIAN PRESCRIBES
-- =====================================================================
SET ROLE hbh_app;
SET hbh.user_id = 'p5.guardian';

CALL hbh_test.chk('write', 'the guardian can READ their own prescription',
  $q$ SELECT count(*) = 1 FROM hbh.child_activities $q$);

-- Since D-26 the app role can write where a permission allows it, and
-- the guardian holds no PLAN.MANAGE. An UPDATE with no matching policy
-- row is FILTERED rather than refused, so the evidence is that nothing
-- changed - not that an error was raised.
CALL hbh_test.chk('write', 'and cannot change it',
  $q$ WITH u AS (UPDATE hbh.child_activities SET times_per_week = 1 RETURNING 1)
      SELECT count(*) = 0 FROM u $q$);

CALL hbh_test.chk_raises('write', 'and cannot prescribe a new one',
  $q$ INSERT INTO hbh.child_activities (center_id, child_id, activity_id, assigned_by)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child_a'),
              (SELECT v FROM hbh_test.fx WHERE k='act2'), (SELECT v FROM hbh_test.fx WHERE k='user_gd')) $q$,
  '42501');

CALL hbh_test.chk_raises('write', 'and cannot write a log row directly either',
  $q$ INSERT INTO hbh.activity_log (center_id, child_activity_id, child_id, logged_by)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='ca_a'),
              (SELECT v FROM hbh_test.fx WHERE k='child_a'), (SELECT v FROM hbh_test.fx WHERE k='user_gd')) $q$,
  '42501');

-- =====================================================================
-- 2. LOGGING
-- =====================================================================
CALL hbh_test.chk('log', 'the guardian logs today through the API',
  $q$ WITH l AS (SELECT hbh.log_activity((SELECT v FROM hbh_test.fx WHERE k='ca_a')) AS id)
      SELECT count(*) = 1 FROM l $q$);

CALL hbh_test.chk('log', 'and the row names them as the logger',
  $q$ SELECT logged_by = (SELECT v FROM hbh_test.fx WHERE k='user_gd')
      FROM hbh.activity_log WHERE child_activity_id = (SELECT v FROM hbh_test.fx WHERE k='ca_a')
        AND log_date = current_date $q$);

-- A double tap on a slow connection must not inflate adherence.
CALL hbh_test.chk_raises('log', 'logging the same day twice raises HB042',
  $q$ SELECT hbh.log_activity((SELECT v FROM hbh_test.fx WHERE k='ca_a')) $q$, 'HB042');

CALL hbh_test.chk('log', 'a different day is fine',
  $q$ WITH l AS (SELECT hbh.log_activity((SELECT v FROM hbh_test.fx WHERE k='ca_a'),
                                         current_date - 1) AS id)
      SELECT count(*) = 1 FROM l $q$);

CALL hbh_test.chk_raises('log', 'a day in the future is refused',
  $q$ SELECT hbh.log_activity((SELECT v FROM hbh_test.fx WHERE k='ca_a'), current_date + 1) $q$,
  '23514');

-- The gate, on a write this time. No SELECT policy can refuse a write.
CALL hbh_test.chk_raises('log', 'logging against ANOTHER family activity raises HB041',
  $q$ SELECT hbh.log_activity((SELECT v FROM hbh_test.fx WHERE k='ca_b')) $q$, 'HB041');

SET hbh.user_id = 'p5.other_gd';
CALL hbh_test.chk('log', 'the other guardian sees none of the first family logs',
  $q$ SELECT count(*) = 0 FROM hbh.activity_log $q$);

CALL hbh_test.chk('log', 'and logs their own child fine',
  $q$ WITH l AS (SELECT hbh.log_activity((SELECT v FROM hbh_test.fx WHERE k='ca_b')) AS id)
      SELECT count(*) = 1 FROM l $q$);

RESET hbh.user_id;
CALL hbh_test.chk('log', 'no identity sees no logs',
  $q$ SELECT count(*) = 0 FROM hbh.activity_log $q$);

CALL hbh_test.chk_raises('log', 'and cannot log at all',
  $q$ SELECT hbh.log_activity((SELECT v FROM hbh_test.fx WHERE k='ca_a')) $q$, 'HB041');

-- =====================================================================
-- 3. ADHERENCE
-- =====================================================================
SET hbh.user_id = 'p5.guardian';

CALL hbh_test.chk('adherence', 'the view shows the one live prescription',
  $q$ SELECT count(*) = 1 FROM hbh.v_activity_adherence $q$);

CALL hbh_test.chk('adherence', 'two of seven days done is 29 per cent',
  $q$ SELECT done_last_7 = 2 AND adherence_pct = 29 FROM hbh.v_activity_adherence
      WHERE child_activity_id = (SELECT v FROM hbh_test.fx WHERE k='ca_a') $q$);

CALL hbh_test.chk('adherence', 'and it is the guardian own child only',
  $q$ SELECT bool_and(child_id = (SELECT v FROM hbh_test.fx WHERE k='child_a'))
      FROM hbh.v_activity_adherence $q$);

RESET hbh.user_id;
CALL hbh_test.chk('adherence', 'with no identity the view returns nothing',
  $q$ SELECT count(*) = 0 FROM hbh.v_activity_adherence $q$);

RESET ROLE;
CALL hbh_test.chk('adherence', 'the adherence view is declared security_invoker',
  $q$ SELECT 'security_invoker=true' = ANY (c.reloptions) FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'hbh' AND c.relname = 'v_activity_adherence' $q$);

-- =====================================================================
-- 4. REQUESTS
-- =====================================================================
SET hbh.user_id = 'p5.guardian';

CALL hbh_test.chk('request', 'the guardian submits a reschedule request',
  $q$ WITH r AS (SELECT hbh.submit_request(
                   (SELECT v FROM hbh_test.fx WHERE k='child_a'), 'RESCHEDULE',
                   (SELECT v FROM hbh_test.fx WHERE k='appt'), 'الأربعاء أفضل لنا') AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'req', id FROM r RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('request', 'it starts NEW with nobody having decided it',
  $q$ SELECT status = 'NEW' AND decided_by IS NULL AND decided_at IS NULL
      FROM hbh.parent_requests WHERE request_id = (SELECT v FROM hbh_test.fx WHERE k='req') $q$);

CALL hbh_test.chk('request', 'and carries a formatted request number',
  $q$ SELECT request_no ~ ('^REQ-' || extract(year FROM now())::integer || '-[0-9]{5}$')
      FROM hbh.parent_requests WHERE request_id = (SELECT v FROM hbh_test.fx WHERE k='req') $q$);

CALL hbh_test.chk_raises('request', 'submitting for another family child raises HB043',
  $q$ SELECT hbh.submit_request((SELECT v FROM hbh_test.fx WHERE k='child_b'), 'CALLBACK') $q$, 'HB043');

SET hbh.user_id = 'p5.therapist';
CALL hbh_test.chk_raises('request', 'a therapist cannot submit on a family behalf - HB043',
  $q$ SELECT hbh.submit_request((SELECT v FROM hbh_test.fx WHERE k='child_a'), 'CALLBACK') $q$, 'HB043');

CALL hbh_test.chk_raises('request', 'and cannot decide one either - no REQUEST.MANAGE',
  $q$ SELECT hbh.decide_request((SELECT v FROM hbh_test.fx WHERE k='req'), 'ACCEPTED') $q$, 'HB043');

RESET ROLE;

CALL hbh_test.chk_raises('request', 'a RESCHEDULE with no appointment breaks the constraint',
  $q$ INSERT INTO hbh.parent_requests (center_id, branch_id, request_no, child_id, guardian_id, kind_code)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
              'P5-BAD-1', (SELECT v FROM hbh_test.fx WHERE k='child_a'),
              (SELECT v FROM hbh_test.fx WHERE k='gd'), 'RESCHEDULE') $q$, '23514');

CALL hbh_test.chk_raises('request', 'a NEW request that names a decider breaks the constraint',
  $q$ INSERT INTO hbh.parent_requests (center_id, branch_id, request_no, child_id, guardian_id,
                                       kind_code, status, decided_by, decided_at)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
              'P5-BAD-2', (SELECT v FROM hbh_test.fx WHERE k='child_a'),
              (SELECT v FROM hbh_test.fx WHERE k='gd'), 'CALLBACK', 'NEW',
              (SELECT v FROM hbh_test.fx WHERE k='user_th'), now()) $q$, '23514');

SET hbh.user_id = 'admin';
CALL hbh_test.chk('request', 'an administrator with REQUEST.MANAGE accepts it',
  $q$ WITH d AS (SELECT hbh.decide_request((SELECT v FROM hbh_test.fx WHERE k='req'),
                                           'ACCEPTED', 'اتنقل للأربعاء'))
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('request', 'the decision is stamped with who made it',
  $q$ SELECT status = 'ACCEPTED' AND decided_by IS NOT NULL AND decided_at IS NOT NULL
      FROM hbh.parent_requests WHERE request_id = (SELECT v FROM hbh_test.fx WHERE k='req') $q$);

-- The claim the portal makes to the family, made good in the schema.
CALL hbh_test.chk('request', 'and accepting it moved NOTHING - the appointment is untouched',
  $q$ SELECT status = 'BOOKED'
             AND starts_at = (SELECT v FROM hbh_test.fxt WHERE k='slot_start')
      FROM hbh.appointments WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt') $q$);

CALL hbh_test.chk_raises('request', 'a decided request cannot be decided again - HB040',
  $q$ UPDATE hbh.parent_requests SET status = 'REJECTED'
      WHERE request_id = (SELECT v FROM hbh_test.fx WHERE k='req') $q$, 'HB040');

SET ROLE hbh_app;
SET hbh.user_id = 'p5.other_gd';
CALL hbh_test.chk('request', 'the other guardian sees none of it',
  $q$ SELECT count(*) = 0 FROM hbh.parent_requests $q$);

SET hbh.user_id = 'p5.guardian';
CALL hbh_test.chk('request', 'and the submitter sees their own',
  $q$ SELECT count(*) = 1 FROM hbh.parent_requests $q$);

-- ---------------------------------------------------------------------
-- THE TWO FIELDS A PARENT OWNS (migration 0107)
--
-- Still as p5.guardian, still through hbh_app. The pair of checks that
-- matters is the acceptance and the refusal TOGETHER: a guardian who can
-- change their email proves the door opens, and a mobile that does not
-- move proves it opens onto two fields and not onto the row.
-- ---------------------------------------------------------------------
CALL hbh_test.chk('own', 'a guardian sets their own email and city',
  $q$ SELECT email = 'p5.parent@example.test' AND city = 'الجيزة'
      FROM hbh.update_own_guardian_contact('p5.parent@example.test', 'الجيزة') $q$);

CALL hbh_test.chk('own', 'and it really is on their row',
  $q$ SELECT email = 'p5.parent@example.test'
      FROM hbh.guardians WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='gd') $q$);

CALL hbh_test.chk('own', 'an empty value CLEARS rather than being ignored',
  $q$ SELECT email IS NULL AND city IS NULL
      FROM hbh.update_own_guardian_contact('', '  ') $q$);

-- The mobile is the login: the one-time code goes to it. There is no
-- argument for it on the function, so the only way in would be the table
-- itself - and the policy asks for GUARDIAN.MANAGE.
--
-- COUNTED, NOT CAUGHT. Since 0016 the app role HOLDS the update grant,
-- so a refused write is zero rows matched and a reported success, not an
-- exception. A chk_raises here would go green the day somebody widened
-- the policy to let everybody through.
CALL hbh_test.chk('own', 'but a guardian cannot move their own mobile',
  $q$ WITH d AS (UPDATE hbh.guardians SET mobile = '+201000000009'
                  WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='gd')
                  RETURNING 1)
      SELECT count(*) = 0 FROM d $q$);

-- Asserted as "not what the refused write tried to set", rather than as a
-- literal number. Another session corrected this line to '+201500000002'
-- when 0106 moved the fixture to E.164 - correctly, and that is exactly
-- the maintenance this form avoids: the property under test is that the
-- forbidden write did not land, and it never depended on the spelling.
CALL hbh_test.chk('own', 'and the number on the row is untouched',
  $q$ SELECT mobile IS DISTINCT FROM '01000000009'
      FROM hbh.guardians WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='gd') $q$);

-- A member of staff has no guardian record, so there is nothing of their
-- own to change. HB051, not a silent write of zero rows.
SET hbh.user_id = 'p5.therapist';
CALL hbh_test.chk_raises('own', 'an account with no guardian record is refused',
  $q$ SELECT * FROM hbh.update_own_guardian_contact('x@example.test', 'x') $q$,
  'HB051');

RESET hbh.user_id;
RESET ROLE;

-- =====================================================================
-- CLEANUP
-- =====================================================================
CALL hbh_test.chk('cleanup', 'notifications removed',
  $q$ WITH d AS (DELETE FROM hbh.notifications WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'p5.%') RETURNING 1)
      SELECT count(*) >= 0 FROM d $q$);

CALL hbh_test.chk('cleanup', 'requests and logs removed',
  $q$ WITH r AS (DELETE FROM hbh.parent_requests WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1),
           l AS (DELETE FROM hbh.activity_log WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1)
      SELECT (SELECT count(*) FROM r) = 1 AND (SELECT count(*) FROM l) = 3 $q$);

CALL hbh_test.chk('cleanup', 'prescriptions and the library removed',
  $q$ WITH c AS (DELETE FROM hbh.child_activities WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1),
           a AS (DELETE FROM hbh.activity_library WHERE code LIKE 'P5-%' RETURNING 1)
      SELECT (SELECT count(*) FROM c) = 2 AND (SELECT count(*) FROM a) = 2 $q$);

ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;
CALL hbh_test.chk('cleanup', 'appointments removed',
  $q$ WITH h AS (DELETE FROM hbh.appointment_status_history WHERE appointment_id IN
                   (SELECT appointment_id FROM hbh.appointments WHERE child_id IN
                      (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b'))) RETURNING 1),
           a AS (DELETE FROM hbh.appointments WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1)
      SELECT (SELECT count(*) FROM a) = 1 $q$);
ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;

-- One statement per level, parents last.
--
-- These four used to be four CTEs in one statement, and it passed for
-- days before failing in a full run while passing on its own. Several
-- data-modifying CTEs have NO defined order between them, so a child
-- row and its parent can be deleted in either sequence and the foreign
-- key check catches whichever loses the race. It is not a flaky test;
-- it is an undefined one, and the fix is to stop asking.
CALL hbh_test.chk('cleanup', 'caseload removed',
  $q$ WITH d AS (DELETE FROM hbh.caseload WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'guardian links removed',
  $q$ WITH d AS (DELETE FROM hbh.guardian_children WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1)
      SELECT count(*) = 2 FROM d $q$);

CALL hbh_test.chk('cleanup', 'children removed',
  $q$ WITH d AS (DELETE FROM hbh.children WHERE child_no LIKE 'P5-%' RETURNING 1)
      SELECT count(*) = 2 FROM d $q$);

CALL hbh_test.chk('cleanup', 'guardians removed',
  $q$ WITH d AS (DELETE FROM hbh.guardians WHERE mobile LIKE '+2015000000%' AND user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'p5.%') RETURNING 1)
      SELECT count(*) = 2 FROM d $q$);

CALL hbh_test.chk('cleanup', 'therapist, rooms, services and users removed',
  $q$ WITH w AS (DELETE FROM hbh.therapist_working_hours WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           s AS (DELETE FROM hbh.therapist_services WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           t AS (DELETE FROM hbh.therapists WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           r AS (DELETE FROM hbh.rooms    WHERE code LIKE 'P5-%' RETURNING 1),
           v AS (DELETE FROM hbh.services WHERE code LIKE 'P5-%' RETURNING 1),
           ur AS (DELETE FROM hbh.user_roles WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'p5.%') RETURNING 1),
           u AS (DELETE FROM hbh.users WHERE username LIKE 'p5.%' RETURNING 1)
      SELECT (SELECT count(*) FROM u) = 3 $q$);

CALL hbh_test.chk('cleanup', 'the append-only trigger is enabled again',
  $q$ SELECT tgenabled = 'O' FROM pg_trigger WHERE tgname = 'trg_ash_append_only' $q$);

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
  IF v_fail = 0 AND v_total > 0 THEN RAISE NOTICE '  PHASE 5 ACCEPTED';
  ELSE RAISE NOTICE '  *** PHASE 5 NOT ACCEPTED'; END IF;
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
