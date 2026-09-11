-- =====================================================================
-- 0100 — WHICH SLOTS ARE FREE
--
-- Booking a session currently means typing two instants by hand and
-- pressing "check": the receptionist proposes a time and the service
-- says no. Eight refusals to find a gap is not a screen, it is a guess
-- with a validator attached.
--
-- So this answers the question the other way round: given a therapist,
-- a service and a day, WHICH windows would be accepted.
--
-- IT DOES NOT CONTAIN THE RULES. It enumerates candidates and asks
-- hbh.validate_slot about each one - the same function the booking
-- itself goes through. That is the whole design:
--
--   A second copy of "when may a session happen" would be a second
--   answer, and the two would agree until the day somebody changed one.
--   The screen would then offer a slot the booking refuses, or hide one
--   it would have accepted - and the second failure is invisible.
--
-- WHAT IT DELIBERATELY DOES NOT ASK ABOUT IS THE CHILD. The child is
-- chosen after the slot (Service -> Therapist -> Day -> Slot -> Child),
-- so p_child_id goes to validate_slot as NULL and its CHILD_BUSY test
-- - `a.child_id = p_child_id` - matches nothing. A child already booked
-- elsewhere at that hour is refused at confirm, by the same function,
-- with CHILD_BUSY. The list says "the therapist and a room are free",
-- which is exactly what it is called.
--
-- SECURITY DEFINER, so it must do for itself what RLS does for
-- everything else:
--
--   * the permission is checked here, by name. Without it the function
--     would report every therapist's diary to anyone signed in - a
--     read-only leak that looks like a helpful list.
--   * the centre is compared to the caller's own. Go already passes
--     hbh.current_center_id(), so the comparison never fails in
--     practice - which is the point of writing it down: the day
--     somebody adds a second caller that passes an id from a request,
--     this refuses instead of enumerating another centre's day.
--
-- Raises HB240 when the permission is missing. Not zero rows: "you may
-- not ask" and "there is nothing free" are different answers, and a
-- screen that prints the second for the first sends a receptionist to
-- ring a family about a day that was never full.
-- =====================================================================

CREATE OR REPLACE FUNCTION hbh.available_slots(
  p_center_id    integer,
  p_therapist_id integer,
  p_service_id   integer,
  p_date         date,
  p_room_id      integer DEFAULT NULL)
RETURNS TABLE (starts_at timestamptz, ends_at timestamptz,
               room_id integer, room_name_ar text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_tz        text;
  l_weekday   smallint;
  l_duration  integer;
  l_step      integer;
  l_window    record;
  l_room      record;
  l_local     timestamp;
  l_starts    timestamptz;
  l_ends      timestamptz;
  l_ok        boolean;
BEGIN
  -- Permission first, before anything is read. A refusal that arrives
  -- after the work is a refusal that did the work.
  IF NOT hbh.has_permission('APPOINTMENT.BOOK') THEN
    RAISE EXCEPTION 'not permitted to read the booking diary'
      USING ERRCODE = 'HB240';
  END IF;

  -- Identity fails closed, and so does a centre that is not the
  -- caller's. Both return nothing rather than raising: an unauthenticated
  -- connection has no diary, which is not an error, it is an empty day.
  IF p_center_id IS NULL
     OR hbh.current_center_id() IS NULL
     OR p_center_id IS DISTINCT FROM hbh.current_center_id() THEN
    RETURN;
  END IF;

  IF p_date IS NULL OR p_therapist_id IS NULL OR p_service_id IS NULL THEN
    RETURN;
  END IF;

  SELECT c.time_zone INTO l_tz
  FROM hbh.centers c WHERE c.center_id = p_center_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- The length of the appointment is the SERVICE's, not the screen's.
  -- A receptionist typing an end time is the reason a forty-five minute
  -- speech session gets booked for an hour and the next family waits.
  SELECT s.default_duration_min INTO l_duration
  FROM hbh.services s
  WHERE s.service_id = p_service_id AND s.center_id = p_center_id AND s.active_flg;
  IF NOT FOUND OR l_duration IS NULL OR l_duration <= 0 THEN
    RETURN;
  END IF;

  -- How far apart the offered starts are. A parameter, not 15 written
  -- into a function: a centre that works on the half hour should not
  -- have to read PL/pgSQL to say so.
  l_step := greatest(5, hbh.param(p_center_id, 'SLOT_GRANULARITY_MIN', '15')::integer);

  l_weekday := extract(isodow FROM p_date)::smallint;

  -- Candidates come from the therapist's own hours for that weekday.
  -- validate_slot checks them again - along with the weekend, closures,
  -- leave, the room, and every existing appointment - and that second
  -- pass is the one that decides. This loop only proposes.
  FOR l_window IN
    SELECT w.start_time, w.end_time
    FROM   hbh.therapist_working_hours w
    WHERE  w.therapist_id = p_therapist_id
      AND  w.center_id = p_center_id
      AND  w.active_flg
      AND  w.weekday = l_weekday
    ORDER  BY w.start_time
  LOOP
    l_local := p_date + l_window.start_time;

    WHILE (l_local + make_interval(mins => l_duration))::time <= l_window.end_time
      -- The date test stops a window that ends at midnight from walking
      -- into the next day, where ::time would wrap and compare true
      -- again for ever.
      AND (l_local + make_interval(mins => l_duration))::date = p_date
    LOOP
      l_starts := l_local AT TIME ZONE l_tz;
      l_ends   := (l_local + make_interval(mins => l_duration)) AT TIME ZONE l_tz;

      -- One room per slot, the first that is free. Offering the same
      -- hour four times - once per room - would turn a short list into
      -- a wall of identical times.
      FOR l_room IN
        SELECT r.room_id, r.name_ar
        FROM   hbh.rooms r
        WHERE  r.center_id = p_center_id
          AND  r.active_flg
          AND  (p_room_id IS NULL OR r.room_id = p_room_id)
        ORDER  BY r.room_id
      LOOP
        SELECT v.ok INTO l_ok
        FROM hbh.validate_slot(
               p_center_id, NULL, p_therapist_id, l_room.room_id,
               p_service_id, l_starts, l_ends, NULL) v;

        IF l_ok THEN
          starts_at    := l_starts;
          ends_at      := l_ends;
          room_id      := l_room.room_id;
          room_name_ar := l_room.name_ar;
          RETURN NEXT;
          EXIT;  -- this slot is answered; move to the next start time
        END IF;
      END LOOP;

      l_local := l_local + make_interval(mins => l_step);
    END LOOP;
  END LOOP;

  RETURN;
END
$fn$;

COMMENT ON FUNCTION hbh.available_slots(integer, integer, integer, date, integer) IS
  'Free windows for a therapist on one day, each with a free room. Every candidate is passed through hbh.validate_slot - the rules live there, not here. The child is not considered; CHILD_BUSY is answered at confirm.';

REVOKE ALL ON FUNCTION hbh.available_slots(integer, integer, integer, date, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.available_slots(integer, integer, integer, date, integer) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0100');
