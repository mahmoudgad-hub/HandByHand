-- =====================================================================
-- 0127 - the booking diary can offer a slot that has no room
--
-- NUMBER RESERVED BEFORE WRITING: 0126 was the highest in the ledger,
-- and 0125/0126 belong to another session in this tree.
--
-- WHY THIS EXISTS: 0117 made an appointment able to be ONLINE, and 0120
-- through 0124 built the room, the door and the pass for it. None of it
-- was reachable. hbh.available_slots - the ONLY thing that tells the
-- console which windows are bookable - loops over hbh.rooms and returns
-- a slot only when some room is free at that hour. An online
-- consultation has no room, so the loop offered nothing, so reception
-- could not book one, so no family could ever arrive at the door.
--
-- The feature was complete and unreachable. That is worth naming,
-- because everything downstream of this function tested green: the
-- schema, the API, the portal screen, 1150 acceptance checks. Nothing
-- asked the one question that mattered - can anybody create the row.
--
-- ORDER OF DEPLOYMENT: THE API GOES SECOND, AND EITHER WAY IS SAFE.
--
-- This DROPS the five-argument available_slots and creates a six-
-- argument one whose sixth argument defaults. A service built against
-- the old signature calls it with five and gets IN_PERSON - which is
-- exactly what it asked for and exactly what it got before. So the old
-- API keeps working against the new schema, and the new API needs this
-- migration to be useful rather than to avoid breaking.
--
-- The drop-and-recreate is not optional: CREATE OR REPLACE with a
-- different argument count makes a SECOND function, and then a
-- five-argument call matches both - the old one exactly and the new one
-- through its default - which is an "ambiguous function call" error on
-- the next booking screen somebody opens.
--
-- WHAT DECIDES REMAINS hbh.validate_slot, WHICH IS NOT TOUCHED HERE.
-- It already answers BAD_DELIVERY_MODE, ROOM_REQUIRED, ROOM_NOT_ALLOWED
-- and SERVICE_NEEDS_ROOM (0117, 0118), and it is the same function the
-- booking itself goes through. This one only proposes candidates; if it
-- held a second opinion about delivery mode, the list and the booking
-- could disagree, and the list is the half nobody would test.
-- =====================================================================

DROP FUNCTION IF EXISTS hbh.available_slots(integer, integer, integer, date, integer);

CREATE FUNCTION hbh.available_slots(
  p_center_id     integer,
  p_therapist_id  integer,
  p_service_id    integer,
  p_date          date,
  p_room_id       integer DEFAULT NULL,
  p_delivery_mode text    DEFAULT 'IN_PERSON'
)
RETURNS TABLE(
  starts_at    timestamptz,
  ends_at      timestamptz,
  -- NULL for a slot with no room, which is the whole point of this
  -- migration. The column stays in the shape it had so that every
  -- existing caller reads the same row it always did.
  room_id      integer,
  room_name_ar text
)
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
  l_in_person boolean;
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

  -- The mode is checked HERE ONLY to decide whether to walk the rooms.
  -- Whether the mode is legal for this service is validate_slot's
  -- question, and it is asked below on every candidate.
  IF p_delivery_mode IS NULL
     OR p_delivery_mode NOT IN ('IN_PERSON', 'ONLINE', 'EXTERNAL') THEN
    RETURN;
  END IF;
  l_in_person := (p_delivery_mode = 'IN_PERSON');

  -- A room named for a delivery mode that has no room is a contradiction,
  -- and the honest answer to it is no slots. validate_slot would refuse
  -- every candidate with ROOM_NOT_ALLOWED anyway; returning here reaches
  -- the same answer without walking the day to find it out.
  IF NOT l_in_person AND p_room_id IS NOT NULL THEN
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

      IF l_in_person THEN
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
                 p_service_id, l_starts, l_ends, NULL, p_delivery_mode) v;

          IF l_ok THEN
            starts_at    := l_starts;
            ends_at      := l_ends;
            room_id      := l_room.room_id;
            room_name_ar := l_room.name_ar;
            RETURN NEXT;
            EXIT;  -- this slot is answered; move to the next start time
          END IF;
        END LOOP;
      ELSE
        -- NO ROOM LOOP AT ALL, and that is the fix. There is nothing to
        -- choose between: the therapist's own diary and the centre's
        -- calendar are the whole of what makes an online hour free, and
        -- validate_slot is asked exactly once for it.
        --
        -- The child is NULL here for the same reason as above - the
        -- child is chosen after the slot - so a family already booked
        -- elsewhere at that hour is refused at confirm with CHILD_BUSY.
        SELECT v.ok INTO l_ok
        FROM hbh.validate_slot(
               p_center_id, NULL, p_therapist_id, NULL,
               p_service_id, l_starts, l_ends, NULL, p_delivery_mode) v;

        IF l_ok THEN
          starts_at    := l_starts;
          ends_at      := l_ends;
          room_id      := NULL;
          room_name_ar := NULL;
          RETURN NEXT;
        END IF;
      END IF;

      l_local := l_local + make_interval(mins => l_step);
    END LOOP;
  END LOOP;

  RETURN;
END
$fn$;

COMMENT ON FUNCTION hbh.available_slots(integer, integer, integer, date, integer, text) IS
  'Which windows a therapist could be booked into on one day. Every candidate is passed through hbh.validate_slot - the same function the booking goes through - so the list can never offer a slot the booking then refuses. For a delivery mode with no room, room_id and room_name_ar come back NULL.';

REVOKE ALL ON FUNCTION hbh.available_slots(integer, integer, integer, date, integer, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.available_slots(integer, integer, integer, date, integer, text) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0127');
