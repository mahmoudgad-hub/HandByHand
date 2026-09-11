-- =====================================================================
-- Hand By Hand (new) - PHASE 8 acceptance suite
--
-- Must print:  PHASE 8 ACCEPTED
--
-- Three gaps, found by asking what was missing rather than by a failing
-- test - which is why each one gets a test here that would have failed
-- before the work:
--
--   1. a therapist on leave, a public holiday and a room being painted
--      were all bookable;
--   2. expire_packages was written and nothing called it;
--   3. nobody on the staff could sign in at all.
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

CREATE PROCEDURE hbh_test.chk_reason(p_grp text, p_name text, p_sql text, p_reason text)
LANGUAGE plpgsql AS $$
DECLARE v_got text;
BEGIN
  BEGIN
    EXECUTE p_sql INTO v_got;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, v_got IS NOT DISTINCT FROM p_reason,
            'expected ' || p_reason || ', got ' || coalesce(v_got, 'NULL'));
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, SQLSTATE || ' ' || SQLERRM);
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
                  + interval '7 days' + interval '10 hours 45 minutes') AT TIME ZONE 'Africa/Cairo'),
  -- the same Monday, a different hour, so a block can be aimed at one
  -- slot without covering the other
  ('slot2_start',(date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '13 hours') AT TIME ZONE 'Africa/Cairo'),
  ('slot2_end',  (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days' + interval '13 hours 45 minutes') AT TIME ZONE 'Africa/Cairo'),
  ('day_start',  (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '7 days') AT TIME ZONE 'Africa/Cairo'),
  ('day_end',    (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo')
                  + interval '8 days') AT TIME ZONE 'Africa/Cairo');

INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P8-SPEECH', 'تخاطب — اختبار ٨', 'SPEECH');
INSERT INTO hbh_test.fx (k, v) SELECT 'svc', service_id FROM hbh.services WHERE code='P8-SPEECH';

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'), 'P8-R1', 'غرفة ٨ أ'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'), 'P8-R2', 'غرفة ٨ ب');
INSERT INTO hbh_test.fx (k, v) SELECT 'room1', room_id FROM hbh.rooms WHERE code='P8-R1';
INSERT INTO hbh_test.fx (k, v) SELECT 'room2', room_id FROM hbh.rooms WHERE code='P8-R2';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile
FROM (VALUES
       ('p8.therapist', 'أخصائي اختبار ٨',  'THERAPIST', '+201800000001'),
       ('p8.reception', 'استقبال اختبار ٨', 'STAFF',     '+201800000002'),
       ('p8.guardian',  'ولي أمر اختبار ٨', 'GUARDIAN',  '+201800000003')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh_test.fx (k, v) SELECT 'user_th', user_id FROM hbh.users WHERE username='p8.therapist';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_rc', user_id FROM hbh.users WHERE username='p8.reception';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_gd', user_id FROM hbh.users WHERE username='p8.guardian';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT f.v, r.role_id
FROM   hbh_test.fx f
JOIN   hbh.roles r ON r.center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
WHERE  (f.k = 'user_th' AND r.code = 'THERAPIST')
   OR  (f.k = 'user_rc' AND r.code = 'RECEPTION')
   OR  (f.k = 'user_gd' AND r.code = 'GUARDIAN');

INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_th'), 'أخصائي اختبار ٨');
INSERT INTO hbh_test.fx (k, v) SELECT 'th', therapist_id FROM hbh.therapists WHERE full_name_ar='أخصائي اختبار ٨';

INSERT INTO hbh.therapist_services (therapist_id, service_id)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='svc'));

INSERT INTO hbh.therapist_working_hours (center_id, therapist_id, weekday, start_time, end_time)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='th'),
       d, TIME '09:00', TIME '17:00'
FROM unnest(ARRAY[7,1,2,3,4]::smallint[]) AS d;

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P8-A', 'طفل اختبار ٨', DATE '2020-07-07', 'M');
INSERT INTO hbh_test.fx (k, v) SELECT 'child', child_id FROM hbh.children WHERE child_no='P8-A';

INSERT INTO hbh.service_packages (center_id, service_id, code, name_ar, sessions_cnt, price_amt, validity_days)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
        'P8-PKG', 'باقة اختبار ٨', 4, 2000.00, 30);
INSERT INTO hbh_test.fx (k, v) SELECT 'pkg', package_id FROM hbh.service_packages WHERE code='P8-PKG';

-- ---------------------------------------------------------------------
CALL hbh_test.chk('fixture', 'migrations 0010 and 0011 recorded',
  $q$ SELECT count(*) = 2 FROM hbh.schema_migrations WHERE version IN ('0010','0011') $q$);

CALL hbh_test.chk('fixture', 'the therapist works Monday nine to five',
  $q$ SELECT count(*) = 1 FROM hbh.therapist_working_hours
      WHERE therapist_id = (SELECT v FROM hbh_test.fx WHERE k='th') AND weekday = 1 $q$);

-- The fixture assertion that matters: the slot is bookable BEFORE any
-- block exists, so a later refusal can only be the block.
CALL hbh_test.chk_reason('fixture', 'and the slot is bookable to begin with',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room1'),
        (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) $q$, 'OK');

-- =====================================================================
-- 1. A THERAPIST ON LEAVE
--
-- The gap in one line: before this, a person travelling next week could
-- be booked all week and the system agreed.
-- =====================================================================
INSERT INTO hbh_test.fx (k, v)
SELECT 'blk_th', block_id FROM (
  SELECT 1) z, LATERAL (SELECT 0 AS block_id) y WHERE false;

WITH b AS (
  INSERT INTO hbh.schedule_blocks (center_id, scope, therapist_id, starts_at, ends_at, reason_code, note_ar)
  VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'THERAPIST',
          (SELECT v FROM hbh_test.fx WHERE k='th'),
          (SELECT v FROM hbh_test.fxt WHERE k='day_start'),
          (SELECT v FROM hbh_test.fxt WHERE k='day_end'), 'LEAVE', 'إجازة اعتيادية')
  RETURNING block_id)
INSERT INTO hbh_test.fx (k, v) SELECT 'blk_th', block_id FROM b;

CALL hbh_test.chk_reason('leave', 'the same slot is now THERAPIST_ON_LEAVE',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room1'),
        (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) $q$, 'THERAPIST_ON_LEAVE');

-- The reason is distinct on purpose. "Unavailable" sends a receptionist
-- to the phone; "she is away" tells her to rebook the therapist.
CALL hbh_test.chk('leave', 'and the reason is not the generic one',
  $q$ SELECT reason <> 'THERAPIST_UNAVAILABLE' FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room1'),
        (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) $q$);

CALL hbh_test.chk_raises('leave', 'and book_appointment refuses it with HB021',
  $q$ SELECT hbh.book_appointment(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='child'), (SELECT v FROM hbh_test.fx WHERE k='th'),
        (SELECT v FROM hbh_test.fx WHERE k='room1'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) $q$, 'HB021');

-- The therapist's own file is untouched: they are ACTIVE, and away for
-- a week. That distinction is the whole reason the table exists.
CALL hbh_test.chk('leave', 'the therapist file still says ACTIVE',
  $q$ SELECT status = 'ACTIVE' FROM hbh.therapists
      WHERE therapist_id = (SELECT v FROM hbh_test.fx WHERE k='th') $q$);

CALL hbh_test.chk('leave', 'withdrawing the block makes the slot bookable again',
  $q$ WITH u AS (UPDATE hbh.schedule_blocks SET active_flg = false
                  WHERE block_id = (SELECT v FROM hbh_test.fx WHERE k='blk_th') RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

CALL hbh_test.chk_reason('leave', 'and it is OK once more',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room1'),
        (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) $q$, 'OK');

-- =====================================================================
-- 2. A CLOSED CENTRE AND A BLOCKED ROOM
-- =====================================================================
WITH b AS (
  INSERT INTO hbh.schedule_blocks (center_id, scope, starts_at, ends_at, reason_code, note_ar)
  VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'CENTER',
          (SELECT v FROM hbh_test.fxt WHERE k='day_start'),
          (SELECT v FROM hbh_test.fxt WHERE k='day_end'), 'HOLIDAY', 'عطلة رسمية')
  RETURNING block_id)
INSERT INTO hbh_test.fx (k, v) SELECT 'blk_center', block_id FROM b;

CALL hbh_test.chk_reason('closed', 'a public holiday closes the centre',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room1'),
        (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) $q$, 'CENTER_CLOSED');

-- And it closes every room, not just one.
CALL hbh_test.chk_reason('closed', 'including the other room',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room2'),
        (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot2_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot2_end')) $q$, 'CENTER_CLOSED');

UPDATE hbh.schedule_blocks SET active_flg = false
 WHERE block_id = (SELECT v FROM hbh_test.fx WHERE k='blk_center');

WITH b AS (
  INSERT INTO hbh.schedule_blocks (center_id, scope, room_id, starts_at, ends_at, reason_code, note_ar)
  VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'ROOM',
          (SELECT v FROM hbh_test.fx WHERE k='room1'),
          (SELECT v FROM hbh_test.fxt WHERE k='day_start'),
          (SELECT v FROM hbh_test.fxt WHERE k='day_end'), 'MAINTENANCE', 'دهان')
  RETURNING block_id)
INSERT INTO hbh_test.fx (k, v) SELECT 'blk_room', block_id FROM b;

CALL hbh_test.chk_reason('closed', 'a room under maintenance is ROOM_BLOCKED',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room1'),
        (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) $q$, 'ROOM_BLOCKED');

-- The other room is untouched, which is how a receptionist knows to
-- move the room rather than the day.
CALL hbh_test.chk_reason('closed', 'and the OTHER room is still free',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room2'),
        (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) $q$, 'OK');

-- A block outside the slot must not touch it.
CALL hbh_test.chk('closed', 'a block on a different day leaves the slot alone',
  $q$ WITH b AS (INSERT INTO hbh.schedule_blocks
                   (center_id, scope, starts_at, ends_at, reason_code)
                 VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'CENTER',
                         (SELECT v FROM hbh_test.fxt WHERE k='day_start') + interval '14 days',
                         (SELECT v FROM hbh_test.fxt WHERE k='day_end')   + interval '14 days',
                         'HOLIDAY') RETURNING 1)
      SELECT count(*) = 1 FROM b $q$);

CALL hbh_test.chk_reason('closed', 'and the slot is still OK',
  $q$ SELECT reason FROM hbh.validate_slot(
        (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='child'),
        (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room2'),
        (SELECT v FROM hbh_test.fx WHERE k='svc'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_start'),
        (SELECT v FROM hbh_test.fxt WHERE k='slot_end')) $q$, 'OK');

-- =====================================================================
-- 3. THE SHAPE OF A BLOCK
--
-- A block scoped to a therapist that names none would match nothing,
-- silently. One naming both a therapist and a room is two rules
-- pretending to be one.
-- =====================================================================
CALL hbh_test.chk_raises('shape', 'a THERAPIST block naming no therapist is refused',
  $q$ INSERT INTO hbh.schedule_blocks (center_id, scope, starts_at, ends_at, reason_code)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'THERAPIST',
              now() + interval '1 day', now() + interval '2 days', 'LEAVE') $q$, '23514');

CALL hbh_test.chk_raises('shape', 'a THERAPIST block naming a room as well is refused',
  $q$ INSERT INTO hbh.schedule_blocks (center_id, scope, therapist_id, room_id, starts_at, ends_at, reason_code)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'THERAPIST',
              (SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='room1'),
              now() + interval '1 day', now() + interval '2 days', 'LEAVE') $q$, '23514');

CALL hbh_test.chk_raises('shape', 'a block that ends before it starts is refused',
  $q$ INSERT INTO hbh.schedule_blocks (center_id, scope, starts_at, ends_at, reason_code)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'CENTER',
              now() + interval '2 days', now() + interval '1 day', 'HOLIDAY') $q$, '23514');

-- =====================================================================
-- 4. DECLARING LEAVE MUST NOT SILENTLY STRAND BOOKINGS
-- =====================================================================
INSERT INTO hbh_test.fx (k, v)
SELECT 'appt', hbh.book_appointment(
  (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
  (SELECT v FROM hbh_test.fx WHERE k='child'), (SELECT v FROM hbh_test.fx WHERE k='th'),
  (SELECT v FROM hbh_test.fx WHERE k='room2'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
  (SELECT v FROM hbh_test.fxt WHERE k='slot_start'), (SELECT v FROM hbh_test.fxt WHERE k='slot_end'));

WITH b AS (
  INSERT INTO hbh.schedule_blocks (center_id, scope, therapist_id, starts_at, ends_at, reason_code)
  VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'THERAPIST',
          (SELECT v FROM hbh_test.fx WHERE k='th'),
          (SELECT v FROM hbh_test.fxt WHERE k='day_start'),
          (SELECT v FROM hbh_test.fxt WHERE k='day_end'), 'SICK')
  RETURNING block_id)
INSERT INTO hbh_test.fx (k, v) SELECT 'blk_sick', block_id FROM b;

-- The leave is a fact and is allowed. The bookings are a problem, and
-- the system says which ones rather than pretending there are none.
CALL hbh_test.chk('conflict', 'the block was created even though an appointment sits inside it',
  $q$ SELECT active_flg FROM hbh.schedule_blocks
      WHERE block_id = (SELECT v FROM hbh_test.fx WHERE k='blk_sick') $q$);

CALL hbh_test.chk('conflict', 'and block_conflicts names the stranded appointment',
  $q$ SELECT count(*) = 1 FROM hbh.block_conflicts((SELECT v FROM hbh_test.fx WHERE k='blk_sick'))
      WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt') $q$);

CALL hbh_test.chk('conflict', 'a block with nothing inside it reports nothing',
  $q$ SELECT count(*) = 0 FROM hbh.block_conflicts((SELECT v FROM hbh_test.fx WHERE k='blk_room')) $q$);

UPDATE hbh.schedule_blocks SET active_flg = false
 WHERE block_id IN ((SELECT v FROM hbh_test.fx WHERE k='blk_sick'),
                    (SELECT v FROM hbh_test.fx WHERE k='blk_room'));

-- =====================================================================
-- 5. STAFF SIGN-IN
-- =====================================================================
SET hbh.user_id = 'admin';

CALL hbh_test.chk_raises('password', 'a password shorter than the centre allows is refused',
  $q$ SELECT hbh.set_password((SELECT v FROM hbh_test.fx WHERE k='user_rc'), 'short') $q$, 'HB072');

-- The two mechanisms may not overlap on one account.
CALL hbh_test.chk_raises('password', 'a GUARDIAN cannot be given a password at all',
  $q$ SELECT hbh.set_password((SELECT v FROM hbh_test.fx WHERE k='user_gd'), 'a-long-enough-password') $q$,
  'HB071');

CALL hbh_test.chk_raises('password', 'and the constraint refuses it even by direct UPDATE',
  $q$ UPDATE hbh.users SET password_hash = 'x', password_set_at = now()
      WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_gd') $q$, '23514');

CALL hbh_test.chk('password', 'reception is given a password',
  $q$ WITH s AS (SELECT hbh.set_password((SELECT v FROM hbh_test.fx WHERE k='user_rc'),
                                         'correct-horse-battery'))
      SELECT count(*) = 1 FROM s $q$);

CALL hbh_test.chk('password', 'it is stored hashed with bcrypt, never in plaintext',
  $q$ SELECT password_hash LIKE '$2%' AND password_hash <> 'correct-horse-battery'
      FROM hbh.users WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_rc') $q$);

CALL hbh_test.chk('password', 'the right password is accepted and names the user',
  $q$ SELECT ok AND user_id = (SELECT v FROM hbh_test.fx WHERE k='user_rc')
      FROM hbh.verify_password('p8.reception', 'correct-horse-battery') $q$);

-- An unknown account and a wrong password give the SAME answer, so the
-- endpoint cannot be used to find out who works here.
CALL hbh_test.chk('password', 'a wrong password and an unknown account answer the same',
  $q$ SELECT (SELECT reason FROM hbh.verify_password('p8.reception', 'wrong-one-entirely'))
           = (SELECT reason FROM hbh.verify_password('nobody.at.all', 'wrong-one-entirely')) $q$);

-- The D-1 rule again: the counter has to survive the refusal.
CALL hbh_test.chk('password', 'and the failed attempt was counted',
  $q$ SELECT failed_login_cnt >= 1 FROM hbh.users
      WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_rc') $q$);

-- Two statements: the second half read the snapshot taken when the
-- statement began, so it saw the count from before the sign-in cleared
-- it - and reported a failure in code that was correct.
CALL hbh_test.chk('password', 'a good sign-in is accepted',
  $q$ SELECT ok FROM hbh.verify_password('p8.reception', 'correct-horse-battery') $q$);

CALL hbh_test.chk('password', 'and it cleared the failure count',
  $q$ SELECT failed_login_cnt = 0 FROM hbh.users
      WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='user_rc') $q$);

CALL hbh_test.chk('password', 'a guardian is told they are not a password user',
  $q$ SELECT reason = 'NOT_PASSWORD_USER' FROM hbh.verify_password('p8.guardian', 'anything') $q$);

-- Five wrong tries lock the account for a while.
CALL hbh_test.chk('password', 'five wrong attempts lock it temporarily',
  $q$ SELECT (SELECT reason FROM hbh.verify_password('p8.reception', 'x1')) = 'BAD_CREDENTIALS'
         AND (SELECT reason FROM hbh.verify_password('p8.reception', 'x2')) = 'BAD_CREDENTIALS'
         AND (SELECT reason FROM hbh.verify_password('p8.reception', 'x3')) = 'BAD_CREDENTIALS'
         AND (SELECT reason FROM hbh.verify_password('p8.reception', 'x4')) = 'BAD_CREDENTIALS'
         AND (SELECT reason FROM hbh.verify_password('p8.reception', 'x5')) = 'TEMPORARILY_LOCKED' $q$);

-- And the lock holds against the CORRECT password too. A lock that only
-- stops wrong guesses stops nothing.
CALL hbh_test.chk('password', 'even the correct password is refused while locked',
  $q$ SELECT reason = 'TEMPORARILY_LOCKED'
      FROM hbh.verify_password('p8.reception', 'correct-horse-battery') $q$);

CALL hbh_test.chk('password', 'setting a new password clears the lock',
  $q$ WITH s AS (SELECT hbh.set_password((SELECT v FROM hbh_test.fx WHERE k='user_rc'),
                                         'another-good-password'))
      SELECT count(*) = 1 FROM s $q$);

CALL hbh_test.chk('password', 'and sign-in works again',
  $q$ SELECT ok FROM hbh.verify_password('p8.reception', 'another-good-password') $q$);

-- Who may set whose.
SET hbh.user_id = 'p8.therapist';
CALL hbh_test.chk_raises('password', 'a therapist cannot set somebody else password',
  $q$ SELECT hbh.set_password((SELECT v FROM hbh_test.fx WHERE k='user_rc'), 'not-your-password') $q$,
  'HB073');

CALL hbh_test.chk('password', 'but can set their own',
  $q$ WITH s AS (SELECT hbh.set_password((SELECT v FROM hbh_test.fx WHERE k='user_th'),
                                         'my-own-password-ok'))
      SELECT count(*) = 1 FROM s $q$);

RESET hbh.user_id;
CALL hbh_test.chk_raises('password', 'and nobody anonymous can set any',
  $q$ SELECT hbh.set_password((SELECT v FROM hbh_test.fx WHERE k='user_rc'), 'anonymous-attempt') $q$,
  'HB073');

-- =====================================================================
-- 6. THE PERIODIC WORK NOW RUNS, AND SAYS SO
-- =====================================================================
SET hbh.user_id = 'admin';

CALL hbh_test.chk('maint', 'a package is sold and back-dated past its expiry',
  $q$ WITH s AS (SELECT hbh.sell_package((SELECT v FROM hbh_test.fx WHERE k='child'),
                                         (SELECT v FROM hbh_test.fx WHERE k='pkg')) AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'cpkg', id FROM s RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('maint', 'its expiry is moved into the past',
  $q$ WITH u AS (UPDATE hbh.child_packages
                    SET purchased_on = current_date - 60, expires_on = current_date - 1
                  WHERE child_package_id = (SELECT v FROM hbh_test.fx WHERE k='cpkg') RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

-- Before the work exists, this is exactly the state a package would
-- have sat in for ever.
CALL hbh_test.chk('maint', 'and it is still ACTIVE, because nothing has run yet',
  $q$ SELECT status = 'ACTIVE' FROM hbh.child_packages
      WHERE child_package_id = (SELECT v FROM hbh_test.fx WHERE k='cpkg') $q$);

CALL hbh_test.chk('maint', 'run_maintenance runs and records the run',
  $q$ WITH m AS (SELECT hbh.run_maintenance() AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'run', id::integer FROM m RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('maint', 'the run finished and reported no error',
  $q$ SELECT finished_at IS NOT NULL AND detail IS NULL FROM hbh.maintenance_runs
      WHERE run_id = (SELECT v FROM hbh_test.fx WHERE k='run') $q$);

CALL hbh_test.chk('maint', 'it expired at least one package',
  $q$ SELECT packages_expired >= 1 FROM hbh.maintenance_runs WHERE run_id = (SELECT v FROM hbh_test.fx WHERE k='run') $q$);

CALL hbh_test.chk('maint', 'and the package is EXPIRED now',
  $q$ SELECT status = 'EXPIRED' FROM hbh.child_packages
      WHERE child_package_id = (SELECT v FROM hbh_test.fx WHERE k='cpkg') $q$);

CALL hbh_test.chk('maint', 'with the forfeited sessions written to the ledger',
  $q$ SELECT delta = -4 AND balance_after = 0 FROM hbh.package_ledger
      WHERE child_package_id = (SELECT v FROM hbh_test.fx WHERE k='cpkg') AND reason = 'EXPIRY' $q$);

-- The point of the run record: staleness is a question the database can
-- answer, instead of something nobody notices for a month.
CALL hbh_test.chk('maint', 'the health view no longer reports it stale',
  $q$ SELECT NOT is_stale AND last_success_at IS NOT NULL FROM hbh.v_maintenance_health $q$);

-- Every assertion names the run it means, rather than "the latest one".
-- The maintenance container runs on its own schedule, and a suite that
-- reads whichever row happens to be newest would fail whenever the two
-- crossed - a flake that looks like a defect and is not.
CALL hbh_test.chk('maint', 'and a second run is harmless',
  $q$ WITH m AS (SELECT hbh.run_maintenance() AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'run2', id::integer FROM m RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('maint', 'the second run expired nothing',
  $q$ SELECT packages_expired = 0 FROM hbh.maintenance_runs
      WHERE run_id = (SELECT v FROM hbh_test.fx WHERE k='run2') $q$);

CALL hbh_test.chk('maint', 'the run table is not readable by the app role',
  $q$ SELECT count(*) = 0 FROM information_schema.role_table_grants
      WHERE grantee = 'hbh_app' AND table_name = 'maintenance_runs' $q$);

RESET hbh.user_id;

-- =====================================================================
-- 7. WHO SEES THE ROTA
-- =====================================================================
SET ROLE hbh_app;
SET hbh.user_id = 'p8.guardian';
CALL hbh_test.chk('visible', 'a guardian sees no schedule blocks',
  $q$ SELECT count(*) = 0 FROM hbh.schedule_blocks $q$);

SET hbh.user_id = 'p8.therapist';
CALL hbh_test.chk('visible', 'a therapist with CHILD.VIEW_ALL does',
  $q$ SELECT count(*) >= 1 FROM hbh.schedule_blocks $q$);

RESET hbh.user_id;
CALL hbh_test.chk('visible', 'and no identity sees none',
  $q$ SELECT count(*) = 0 FROM hbh.schedule_blocks $q$);

RESET ROLE;

-- =====================================================================
-- CLEANUP
-- =====================================================================
ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;
CALL hbh_test.chk('cleanup', 'appointments and blocks removed',
  $q$ WITH h AS (DELETE FROM hbh.appointment_status_history WHERE appointment_id IN
                   (SELECT appointment_id FROM hbh.appointments
                    WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child')) RETURNING 1),
           a AS (DELETE FROM hbh.appointments WHERE child_id =
                   (SELECT v FROM hbh_test.fx WHERE k='child') RETURNING 1),
           b AS (DELETE FROM hbh.schedule_blocks WHERE center_id =
                   (SELECT v FROM hbh_test.fx WHERE k='center')
                   AND (therapist_id = (SELECT v FROM hbh_test.fx WHERE k='th')
                        OR room_id IN (SELECT v FROM hbh_test.fx WHERE k IN ('room1','room2'))
                        OR scope = 'CENTER') RETURNING 1)
      SELECT (SELECT count(*) FROM a) = 1 AND (SELECT count(*) FROM b) >= 4 $q$);
ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;

ALTER TABLE hbh.package_ledger DISABLE TRIGGER trg_led_append_only;
CALL hbh_test.chk('cleanup', 'packages and the ledger removed',
  $q$ WITH l AS (DELETE FROM hbh.package_ledger WHERE child_package_id IN
                   (SELECT child_package_id FROM hbh.child_packages
                    WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child')) RETURNING 1),
           c AS (DELETE FROM hbh.child_packages WHERE child_id =
                   (SELECT v FROM hbh_test.fx WHERE k='child') RETURNING 1),
           p AS (DELETE FROM hbh.service_packages WHERE code = 'P8-PKG' RETURNING 1)
      SELECT (SELECT count(*) FROM c) = 1 AND (SELECT count(*) FROM l) = 2 $q$);
ALTER TABLE hbh.package_ledger ENABLE TRIGGER trg_led_append_only;

-- Same as p3: 0089 added staff notifications, so the run now leaves
-- rows pointing at these users and the old teardown walked into
-- fk_ntf_user.
CALL hbh_test.chk('cleanup', 'notifications written during the run are removed',
  $q$ WITH d AS (DELETE FROM hbh.notifications WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'p8.%') RETURNING 1)
      SELECT count(*) >= 0 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the rest removed',
  $q$ WITH k AS (DELETE FROM hbh.children WHERE child_no = 'P8-A' RETURNING 1),
           w AS (DELETE FROM hbh.therapist_working_hours WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           ts AS (DELETE FROM hbh.therapist_services WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           t AS (DELETE FROM hbh.therapists WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           r AS (DELETE FROM hbh.rooms    WHERE code LIKE 'P8-%' RETURNING 1),
           s AS (DELETE FROM hbh.services WHERE code LIKE 'P8-%' RETURNING 1),
           ur AS (DELETE FROM hbh.user_roles WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'p8.%') RETURNING 1),
           u AS (DELETE FROM hbh.users WHERE username LIKE 'p8.%' RETURNING 1)
      SELECT (SELECT count(*) FROM u) = 3 AND (SELECT count(*) FROM r) = 2 $q$);

CALL hbh_test.chk('cleanup', 'both append-only triggers are enabled again',
  $q$ SELECT count(*) = 2 FROM pg_trigger
      WHERE tgname IN ('trg_ash_append_only','trg_led_append_only') AND tgenabled = 'O' $q$);

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
  IF v_fail = 0 AND v_total > 0 THEN RAISE NOTICE '  PHASE 8 ACCEPTED';
  ELSE RAISE NOTICE '  *** PHASE 8 NOT ACCEPTED'; END IF;
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
