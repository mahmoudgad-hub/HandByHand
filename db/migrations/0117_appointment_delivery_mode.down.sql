-- =====================================================================
-- 0117 down - every appointment happens in a room again
--
-- ORDER IS THE POINT OF THIS FILE. The functions come back first, then
-- the constraints, and the COLUMN LAST - because ex_appointments_child
-- names delivery_mode in its predicate, and dropping the column would
-- take that constraint with it. The whole file is one transaction, so a
-- step that fails drops nothing at all and the rebuild quietly keeps the
-- new definitions while appearing to have reverted.
--
-- THIS DOWN CAN REFUSE, AND IT SHOULD. room_id was NOT NULL and is about
-- to be again. If any appointment has been booked without a room, there
-- is no honest value to put there - inventing one would put a family in
-- a treatment room that nobody scheduled, and deleting the row would
-- throw away a booking somebody made. It stops and names the count.
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- start_session, back to its 0087 body.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.start_session(p_appointment_id integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_appt hbh.appointments%ROWTYPE;
  l_id   integer;
BEGIN
  IF hbh.current_user_id() IS NULL THEN
    RAISE EXCEPTION 'no identity' USING ERRCODE = 'HB028';
  END IF;

  IF NOT hbh.has_permission('SESSION.START') THEN
    RAISE EXCEPTION 'not permitted to start a session' USING ERRCODE = 'HB028';
  END IF;

  SELECT * INTO l_appt FROM hbh.appointments a
  WHERE a.appointment_id = p_appointment_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such appointment %', p_appointment_id USING ERRCODE = 'HB021';
  END IF;

  IF NOT hbh.can_start_session(p_appointment_id) THEN
    RAISE EXCEPTION 'appointment % belongs to another therapist', p_appointment_id
      USING ERRCODE = 'HB028';
  END IF;

  IF l_appt.status <> 'CHECKED_IN' THEN
    RAISE EXCEPTION 'appointment % is % - a session starts only from CHECKED_IN',
                    p_appointment_id, l_appt.status
      USING ERRCODE = 'HB024';
  END IF;

  IF EXISTS (SELECT 1 FROM hbh.therapy_sessions s WHERE s.appointment_id = p_appointment_id) THEN
    RAISE EXCEPTION 'appointment % already has a session', p_appointment_id
      USING ERRCODE = 'HB022';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.caseload c
                 WHERE c.therapist_id = l_appt.therapist_id
                   AND c.child_id = l_appt.child_id
                   AND c.service_id = l_appt.service_id
                   AND c.active_flg) THEN
    RAISE EXCEPTION 'therapist % is not on child %''s caseload for this service',
                    l_appt.therapist_id, l_appt.child_id
      USING ERRCODE = 'HB023';
  END IF;

  INSERT INTO hbh.therapy_sessions (center_id, branch_id, appointment_id, child_id,
                                    therapist_id, room_id, service_id)
  VALUES (l_appt.center_id, l_appt.branch_id, p_appointment_id, l_appt.child_id,
          l_appt.therapist_id, l_appt.room_id, l_appt.service_id)
  RETURNING session_id INTO l_id;

  RETURN l_id;
END
$fn$;

REVOKE ALL ON FUNCTION hbh.start_session(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.start_session(integer) TO hbh_app;

-- ---------------------------------------------------------------------
-- book_appointment and validate_slot, back to nine and eight parameters.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS hbh.book_appointment(integer, integer, integer, integer, integer,
                                             integer, timestamptz, timestamptz, text, text);

DROP FUNCTION IF EXISTS hbh.validate_slot(integer, integer, integer, integer, integer,
                                          timestamptz, timestamptz, integer, text);

CREATE FUNCTION hbh.validate_slot(
  p_center_id integer, p_child_id integer, p_therapist_id integer,
  p_room_id integer, p_service_id integer,
  p_starts_at timestamptz, p_ends_at timestamptz,
  p_exclude_id integer DEFAULT NULL)
RETURNS TABLE(ok boolean, reason text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_tz        text;
  l_weekend   smallint[];
  l_local     timestamp;
  l_weekday   smallint;
  l_backdays  integer;
  l_branch    integer;
  l_span      tstzrange;
BEGIN
  IF p_ends_at <= p_starts_at THEN
    RETURN QUERY SELECT false, 'BAD_WINDOW'; RETURN;
  END IF;

  l_span := tstzrange(p_starts_at, p_ends_at, '[)');

  SELECT c.time_zone, c.weekend_days INTO l_tz, l_weekend
  FROM hbh.centers c WHERE c.center_id = p_center_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'NO_SUCH_CENTRE'; RETURN;
  END IF;

  l_local   := p_starts_at AT TIME ZONE l_tz;
  l_weekday := extract(isodow FROM l_local)::smallint;

  l_backdays := hbh.param(p_center_id, 'ALLOW_BACKDATED_BOOKING_DAYS', '0')::integer;
  IF l_local::date < (now() AT TIME ZONE l_tz)::date - l_backdays THEN
    RETURN QUERY SELECT false, 'IN_THE_PAST'; RETURN;
  END IF;

  IF l_weekday = ANY (l_weekend) THEN
    RETURN QUERY SELECT false, 'WEEKEND'; RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.therapists t
                 WHERE t.therapist_id = p_therapist_id AND t.center_id = p_center_id
                   AND t.active_flg AND t.status = 'ACTIVE') THEN
    RETURN QUERY SELECT false, 'THERAPIST_UNAVAILABLE'; RETURN;
  END IF;

  SELECT r.branch_id INTO l_branch FROM hbh.rooms r
  WHERE r.room_id = p_room_id AND r.center_id = p_center_id AND r.active_flg;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'ROOM_UNAVAILABLE'; RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.therapist_services ts
                 WHERE ts.therapist_id = p_therapist_id AND ts.service_id = p_service_id
                   AND ts.active_flg) THEN
    RETURN QUERY SELECT false, 'THERAPIST_SERVICE_MISMATCH'; RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM hbh.schedule_blocks b
             WHERE b.active_flg AND b.center_id = p_center_id
               AND b.scope = 'CENTER'
               AND tstzrange(b.starts_at, b.ends_at, '[)') && l_span) THEN
    RETURN QUERY SELECT false, 'CENTER_CLOSED'; RETURN;
  END IF;

  IF l_branch IS NOT NULL AND EXISTS (
       SELECT 1 FROM hbh.schedule_blocks b
       WHERE b.active_flg AND b.center_id = p_center_id
         AND b.scope = 'BRANCH' AND b.branch_id = l_branch
         AND tstzrange(b.starts_at, b.ends_at, '[)') && l_span) THEN
    RETURN QUERY SELECT false, 'BRANCH_CLOSED'; RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM hbh.schedule_blocks b
             WHERE b.active_flg AND b.scope = 'THERAPIST'
               AND b.therapist_id = p_therapist_id
               AND tstzrange(b.starts_at, b.ends_at, '[)') && l_span) THEN
    RETURN QUERY SELECT false, 'THERAPIST_ON_LEAVE'; RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM hbh.schedule_blocks b
             WHERE b.active_flg AND b.scope = 'ROOM'
               AND b.room_id = p_room_id
               AND tstzrange(b.starts_at, b.ends_at, '[)') && l_span) THEN
    RETURN QUERY SELECT false, 'ROOM_BLOCKED'; RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.therapist_working_hours w
                 WHERE w.therapist_id = p_therapist_id AND w.active_flg
                   AND w.weekday = l_weekday
                   AND w.start_time <= l_local::time
                   AND w.end_time   >= (p_ends_at AT TIME ZONE l_tz)::time) THEN
    RETURN QUERY SELECT false, 'OUTSIDE_WORKING_HOURS'; RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM hbh.appointments a
             WHERE a.therapist_id = p_therapist_id
               AND a.status IN ('BOOKED','CONFIRMED','CHECKED_IN','COMPLETED')
               AND a.appointment_id IS DISTINCT FROM p_exclude_id
               AND tstzrange(a.starts_at, a.ends_at, '[)') && l_span) THEN
    RETURN QUERY SELECT false, 'THERAPIST_BUSY'; RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM hbh.appointments a
             WHERE a.room_id = p_room_id
               AND a.status IN ('BOOKED','CONFIRMED','CHECKED_IN','COMPLETED')
               AND a.appointment_id IS DISTINCT FROM p_exclude_id
               AND tstzrange(a.starts_at, a.ends_at, '[)') && l_span) THEN
    RETURN QUERY SELECT false, 'ROOM_BUSY'; RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM hbh.appointments a
             WHERE a.child_id = p_child_id
               AND a.status IN ('BOOKED','CONFIRMED','CHECKED_IN','COMPLETED')
               AND a.appointment_id IS DISTINCT FROM p_exclude_id
               AND tstzrange(a.starts_at, a.ends_at, '[)') && l_span) THEN
    RETURN QUERY SELECT false, 'CHILD_BUSY'; RETURN;
  END IF;

  RETURN QUERY SELECT true, 'OK';
END
$fn$;

REVOKE ALL ON FUNCTION hbh.validate_slot(integer, integer, integer, integer, integer,
                                         timestamptz, timestamptz, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.validate_slot(integer, integer, integer, integer, integer,
                                            timestamptz, timestamptz, integer) TO hbh_app;

CREATE FUNCTION hbh.book_appointment(
  p_center_id integer, p_branch_id integer, p_child_id integer,
  p_therapist_id integer, p_room_id integer, p_service_id integer,
  p_starts_at timestamptz, p_ends_at timestamptz,
  p_note_ar text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_check  record;
  l_no     text;
  l_id     integer;
BEGIN
  PERFORM hbh.assert_center_argument(p_center_id);

  IF hbh.current_user_id() IS NOT NULL
     AND NOT hbh.has_permission('APPOINTMENT.BOOK') THEN
    RAISE EXCEPTION 'not permitted to book an appointment'
      USING ERRCODE = 'HB027';
  END IF;

  SELECT * INTO l_check
  FROM hbh.validate_slot(p_center_id, p_child_id, p_therapist_id, p_room_id,
                         p_service_id, p_starts_at, p_ends_at);
  IF NOT l_check.ok THEN
    RAISE EXCEPTION 'slot rejected: %', l_check.reason USING ERRCODE = 'HB021';
  END IF;

  l_no := hbh.next_number(p_center_id, 'APPT');

  BEGIN
    INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id,
                                  therapist_id, room_id, service_id, starts_at, ends_at, note_ar)
    VALUES (p_center_id, p_branch_id, l_no, p_child_id, p_therapist_id, p_room_id,
            p_service_id, p_starts_at, p_ends_at, p_note_ar)
    RETURNING appointment_id INTO l_id;
  EXCEPTION WHEN exclusion_violation THEN
    RAISE EXCEPTION 'slot rejected: SLOT_TAKEN' USING ERRCODE = 'HB021';
  END;

  RETURN l_id;
END
$fn$;

REVOKE ALL ON FUNCTION hbh.book_appointment(integer, integer, integer, integer, integer,
                                            integer, timestamptz, timestamptz, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.book_appointment(integer, integer, integer, integer, integer,
                                               integer, timestamptz, timestamptz, text) TO hbh_app;

-- ---------------------------------------------------------------------
-- The constraints, back to covering every row.
--
-- ex_appointments_child is rebuilt BEFORE the column is dropped,
-- because its predicate names that column.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.appointments DROP CONSTRAINT ex_appointments_child;

ALTER TABLE hbh.appointments
  ADD CONSTRAINT ex_appointments_child
  EXCLUDE USING gist (
    child_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&)
  WHERE (status IN ('BOOKED', 'CONFIRMED', 'CHECKED_IN', 'COMPLETED'));

ALTER TABLE hbh.appointments DROP CONSTRAINT ex_appointments_room;

ALTER TABLE hbh.appointments
  ADD CONSTRAINT ex_appointments_room
  EXCLUDE USING gist (
    room_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&)
  WHERE (status IN ('BOOKED', 'CONFIRMED', 'CHECKED_IN', 'COMPLETED'));

ALTER TABLE hbh.appointments DROP CONSTRAINT IF EXISTS ck_appointments_room_mode;

-- ---------------------------------------------------------------------
-- And the column, once there is nothing left that needs it.
-- ---------------------------------------------------------------------
DO $rooms$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.appointments WHERE room_id IS NULL;
  IF n > 0 THEN
    RAISE EXCEPTION '0117 down: % appointment(s) have no room, and room_id is about to be NOT NULL again', n
      USING HINT = 'give them a room or cancel them - this migration will not invent one, and will not delete a booking somebody made';
  END IF;
END
$rooms$;

ALTER TABLE hbh.appointments ALTER COLUMN room_id SET NOT NULL;

ALTER TABLE hbh.appointments DROP CONSTRAINT IF EXISTS ck_appointments_delivery_mode;
ALTER TABLE hbh.appointments DROP COLUMN IF EXISTS delivery_mode;

DELETE FROM hbh.schema_migrations WHERE version = '0117';
