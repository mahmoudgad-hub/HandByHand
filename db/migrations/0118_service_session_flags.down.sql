-- =====================================================================
-- 0118 down - the mode decides again instead of the service
--
-- ORDER, as in 0117's down: the functions and the trigger come back
-- first, the columns they read go last. The file is one transaction, so
-- a step that fails on a dependency drops nothing at all and the rebuild
-- silently keeps the new definitions while appearing to have reverted.
--
-- THIS DOWN CAN REFUSE. Going back means start_session asks about the
-- delivery mode again, and a service marked creates_session_flg = false
-- would become a service that opens sessions - on every in-person
-- appointment already booked for it. It stops and names them rather than
-- turning a deliberate setting into its opposite in silence.
-- =====================================================================

\set ON_ERROR_STOP on

DO $flags$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.services
   WHERE NOT creates_session_flg OR NOT needs_caseload_flg;
  IF n > 0 THEN
    RAISE EXCEPTION '0118 down: % service(s) carry a non-default flag, and this migration is about to delete the columns that hold it', n
      USING HINT = 'an in-person appointment for such a service would start opening therapy sessions again - decide what those services should be first';
  END IF;
END
$flags$;

-- ---------------------------------------------------------------------
-- start_session, back to asking about the delivery mode.
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

  IF l_appt.delivery_mode <> 'IN_PERSON' THEN
    RAISE EXCEPTION 'appointment % is delivered %, and only an in-person appointment opens a therapy session',
                    p_appointment_id, l_appt.delivery_mode
      USING ERRCODE = 'HB250',
            HINT = 'a consultation is written up as a note, not as a session';
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
-- The booking-time guard goes, and so does the reason that explained it.
-- validate_slot is restored to its 0117 body - same signature, so
-- CREATE OR REPLACE and no caller moves.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_appointments_service_room ON hbh.appointments;

CREATE OR REPLACE FUNCTION hbh.validate_slot(
  p_center_id integer, p_child_id integer, p_therapist_id integer,
  p_room_id integer, p_service_id integer,
  p_starts_at timestamptz, p_ends_at timestamptz,
  p_exclude_id integer DEFAULT NULL,
  p_delivery_mode text DEFAULT 'IN_PERSON')
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

  IF p_delivery_mode IS NULL
     OR p_delivery_mode NOT IN ('IN_PERSON', 'ONLINE', 'EXTERNAL') THEN
    RETURN QUERY SELECT false, 'BAD_DELIVERY_MODE'; RETURN;
  END IF;

  IF p_delivery_mode = 'IN_PERSON' AND p_room_id IS NULL THEN
    RETURN QUERY SELECT false, 'ROOM_REQUIRED'; RETURN;
  END IF;

  IF p_delivery_mode <> 'IN_PERSON' AND p_room_id IS NOT NULL THEN
    RETURN QUERY SELECT false, 'ROOM_NOT_ALLOWED'; RETURN;
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

  IF p_room_id IS NOT NULL THEN
    SELECT r.branch_id INTO l_branch FROM hbh.rooms r
    WHERE r.room_id = p_room_id AND r.center_id = p_center_id AND r.active_flg;
    IF NOT FOUND THEN
      RETURN QUERY SELECT false, 'ROOM_UNAVAILABLE'; RETURN;
    END IF;
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

  IF p_room_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM hbh.schedule_blocks b
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

  IF p_room_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM hbh.appointments a
       WHERE a.room_id = p_room_id
         AND a.status IN ('BOOKED','CONFIRMED','CHECKED_IN','COMPLETED')
         AND a.appointment_id IS DISTINCT FROM p_exclude_id
         AND tstzrange(a.starts_at, a.ends_at, '[)') && l_span) THEN
    RETURN QUERY SELECT false, 'ROOM_BUSY'; RETURN;
  END IF;

  IF p_delivery_mode <> 'ONLINE' AND EXISTS (
       SELECT 1 FROM hbh.appointments a
       WHERE a.child_id = p_child_id
         AND a.status IN ('BOOKED','CONFIRMED','CHECKED_IN','COMPLETED')
         AND a.delivery_mode <> 'ONLINE'
         AND a.appointment_id IS DISTINCT FROM p_exclude_id
         AND tstzrange(a.starts_at, a.ends_at, '[)') && l_span) THEN
    RETURN QUERY SELECT false, 'CHILD_BUSY'; RETURN;
  END IF;

  RETURN QUERY SELECT true, 'OK';
END
$fn$;

DROP FUNCTION IF EXISTS hbh.guard_service_needs_room();

-- ---------------------------------------------------------------------
-- And the columns, once nothing reads them.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.services DROP CONSTRAINT IF EXISTS ck_services_caseload_needs_session;
ALTER TABLE hbh.services DROP COLUMN IF EXISTS needs_caseload_flg;
ALTER TABLE hbh.services DROP COLUMN IF EXISTS creates_session_flg;

DELETE FROM hbh.schema_migrations WHERE version = '0118';
