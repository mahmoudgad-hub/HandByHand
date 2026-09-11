-- =====================================================================
-- 0102 down - book_appointment stops checking the centre it is handed.
--
-- WHAT THIS RESTORES. A function that inserts an appointment into
-- whatever centre its caller names. It is not reachable through the API
-- today - store.BookAppointment derives the centre from the session and
-- no handler reads one from a request body - so running this down
-- migration restores a latent defect rather than a live one.
--
-- That is still a real loss. The safety would be back to living in a
-- single line of Go, which is the arrangement rule 4 of this project
-- exists to refuse: a condition in the caller is the weaker copy of a
-- rule, and the weaker copy decides.
--
-- assert_center_argument is dropped here because 0102 is the only thing
-- that created it and the only thing that calls it. assert_same_center
-- belongs to 0099 and is untouched.
-- =====================================================================

CREATE OR REPLACE FUNCTION hbh.book_appointment(
  p_center_id    integer,
  p_branch_id    integer,
  p_child_id     integer,
  p_therapist_id integer,
  p_room_id      integer,
  p_service_id   integer,
  p_starts_at    timestamptz,
  p_ends_at      timestamptz,
  p_note_ar      text DEFAULT NULL)
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

DROP FUNCTION IF EXISTS hbh.assert_center_argument(integer);

DELETE FROM hbh.schema_migrations WHERE version = '0102';
