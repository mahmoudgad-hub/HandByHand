-- =====================================================================
-- 0127 down - the booking diary only offers rooms again
--
-- THIS DOWN CAN REFUSE, AND IT SHOULD. Going back means reception can no
-- longer be offered a roomless window, so an online consultation can no
-- longer be booked. That is survivable for appointments already in the
-- diary - they keep their rows, their rooms and their doors - but it is
-- not survivable silently, because the console would simply return an
-- empty day for an online service with no message anywhere saying why.
--
-- So it stops and names the count of ONLINE appointments that exist. If
-- there are none, nobody has used the feature and the revert costs
-- nothing. If there are some, whoever is reverting has to decide what
-- happens to them, and that decision is not this file's to make.
-- =====================================================================

\set ON_ERROR_STOP on

DO $guard$
DECLARE
  l_online integer;
BEGIN
  SELECT count(*) INTO l_online
  FROM hbh.appointments
  WHERE delivery_mode <> 'IN_PERSON' AND active_flg;

  IF l_online > 0 THEN
    RAISE EXCEPTION
      'refusing: % appointment(s) are not IN_PERSON. Reverting 0127 leaves them in the diary with no way for reception to book another, and no message on the screen saying so. Decide what happens to them first.',
      l_online;
  END IF;
END
$guard$;

DROP FUNCTION IF EXISTS hbh.available_slots(integer, integer, integer, date, integer, text);

CREATE FUNCTION hbh.available_slots(
  p_center_id    integer,
  p_therapist_id integer,
  p_service_id   integer,
  p_date         date,
  p_room_id      integer DEFAULT NULL
)
RETURNS TABLE(
  starts_at    timestamptz,
  ends_at      timestamptz,
  room_id      integer,
  room_name_ar text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_tz       text;
  l_weekday  smallint;
  l_duration integer;
  l_step     integer;
  l_window   record;
  l_room     record;
  l_local    timestamp;
  l_starts   timestamptz;
  l_ends     timestamptz;
  l_ok       boolean;
BEGIN
  IF NOT hbh.has_permission('APPOINTMENT.BOOK') THEN
    RAISE EXCEPTION 'not permitted to read the booking diary'
      USING ERRCODE = 'HB240';
  END IF;

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

  SELECT s.default_duration_min INTO l_duration
  FROM hbh.services s
  WHERE s.service_id = p_service_id AND s.center_id = p_center_id AND s.active_flg;
  IF NOT FOUND OR l_duration IS NULL OR l_duration <= 0 THEN
    RETURN;
  END IF;

  l_step := greatest(5, hbh.param(p_center_id, 'SLOT_GRANULARITY_MIN', '15')::integer);

  l_weekday := extract(isodow FROM p_date)::smallint;

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
      AND (l_local + make_interval(mins => l_duration))::date = p_date
    LOOP
      l_starts := l_local AT TIME ZONE l_tz;
      l_ends   := (l_local + make_interval(mins => l_duration)) AT TIME ZONE l_tz;

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
          EXIT;
        END IF;
      END LOOP;

      l_local := l_local + make_interval(mins => l_step);
    END LOOP;
  END LOOP;

  RETURN;
END
$fn$;

REVOKE ALL ON FUNCTION hbh.available_slots(integer, integer, integer, date, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.available_slots(integer, integer, integer, date, integer) TO hbh_app;

DELETE FROM hbh.schema_migrations WHERE version = '0127';
