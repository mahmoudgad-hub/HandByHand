-- =====================================================================
-- 0123 down - the door stops saying who is knocking
--
-- Restores 0121's five-column form, verbatim. Anything that selects
-- display_name or user_ref has to go down with it - today that is the
-- meeting handler, which is the only caller.
--
-- The waiting room then has no name to show, so the therapist admits
-- whoever knocks. That is the half of the model this column exists to
-- keep working, and it is worth knowing that going down past here costs
-- it.
-- =====================================================================

\set ON_ERROR_STOP on

DROP FUNCTION IF EXISTS hbh.authorize_meeting_entry(integer);

CREATE FUNCTION hbh.authorize_meeting_entry(p_appointment_id integer)
RETURNS TABLE(meeting_id bigint, room_ref text, provider text,
              moderator_flg boolean, expires_at timestamptz)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_appt hbh.appointments%ROWTYPE;
  l_mtg  hbh.meetings%ROWTYPE;
  l_ttl  integer;
BEGIN
  IF hbh.current_user_id() IS NULL THEN
    RAISE EXCEPTION 'no identity' USING ERRCODE = 'HB028';
  END IF;

  SELECT * INTO l_appt FROM hbh.appointments a
  WHERE a.appointment_id = p_appointment_id;

  IF NOT FOUND OR NOT hbh.can_access_child(l_appt.child_id) THEN
    RAISE EXCEPTION 'no such appointment %', p_appointment_id USING ERRCODE = 'HB021';
  END IF;

  IF l_appt.delivery_mode <> 'ONLINE' THEN
    RAISE EXCEPTION 'appointment % is not an online consultation', p_appointment_id
      USING ERRCODE = 'HB250';
  END IF;

  IF l_appt.status <> 'CONFIRMED' THEN
    RAISE EXCEPTION 'appointment % is % - a consultation opens once it is confirmed',
                    p_appointment_id, l_appt.status
      USING ERRCODE = 'HB253',
            HINT = 'the invoice is what confirms it';
  END IF;

  SELECT * INTO l_mtg FROM hbh.meetings m
  WHERE m.appointment_id = p_appointment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'appointment % has no room', p_appointment_id USING ERRCODE = 'HB021';
  END IF;

  IF l_mtg.status <> 'READY' THEN
    RAISE EXCEPTION 'the room for appointment % is %', p_appointment_id, l_mtg.status
      USING ERRCODE = 'HB252',
            HINT = 'a cancelled consultation closes its room';
  END IF;

  IF now() < l_mtg.opens_at OR now() >= l_mtg.expires_at THEN
    RAISE EXCEPTION 'the door for appointment % is not open', p_appointment_id
      USING ERRCODE = 'HB252';
  END IF;

  l_ttl := hbh.param(l_appt.center_id, 'MEETING_TOKEN_TTL_MIN', '15')::integer;

  RETURN QUERY SELECT
    l_mtg.meeting_id,
    l_mtg.room_ref,
    l_mtg.provider,
    hbh.current_user_is_staff(),
    least(now() + make_interval(mins => l_ttl), l_mtg.expires_at);
END
$fn$;

REVOKE ALL ON FUNCTION hbh.authorize_meeting_entry(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.authorize_meeting_entry(integer) TO hbh_app;

DELETE FROM hbh.schema_migrations WHERE version = '0123';
