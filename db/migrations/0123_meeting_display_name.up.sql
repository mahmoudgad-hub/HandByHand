-- =====================================================================
-- 0123 - the door says who is knocking
--
-- NUMBER RESERVED BEFORE WRITING. 0119 and 0122 belong to another
-- session in this tree; 0112-0118, 0120 and 0121 are mine, and this
-- completes 0121.
--
-- NO NEW SQLSTATE, so the API does not have to go down first.
--
-- ---------------------------------------------------------------------
-- WHY
--
-- The waiting room is half of the security model. The architect's note
-- puts it in one line - "غرفة انتظار مفعّلة دائمًا، والأخصائي يقبل
-- الداخل بالاسم. التوكن يمنع الغريب، والانتظار يمنع الخطأ" - and a
-- therapist cannot admit anybody by name if the name is not there.
--
-- 0121 returned everything about the ROOM and nothing about the person,
-- so the service had a decision and no name to sign into it.
--
-- ---------------------------------------------------------------------
-- WHY IT COMES FROM HERE AND NOT FROM THE BROWSER
--
-- The obvious shortcut is to let the page send the name it is already
-- showing. It is also the one thing that must not happen: a name the
-- client chooses is a name the client can choose, and the waiting room
-- is exactly where somebody would type a therapist's name to be waved
-- through. It is read from hbh.users, inside the function that already
-- decided who the caller is.
--
-- ---------------------------------------------------------------------
-- AND IT IS THE ADULT'S NAME, NEVER THE CHILD'S
--
-- The child is not in the consultation - that is the whole reason
-- ex_appointments_child stopped covering ONLINE in 0117. Sending their
-- name to a video provider would be sending a piece of a clinical record
-- to a third party for no purpose at all: nobody in the room needs it,
-- because everybody in the room already knows it.
-- =====================================================================

\set ON_ERROR_STOP on

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0123') THEN
    RAISE EXCEPTION 'migration 0123 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0121') THEN
    RAISE EXCEPTION 'migration 0121 must be applied first';
  END IF;
END
$guard$;

-- Dropped and recreated: a returned record cannot gain a column in
-- place. Nothing else calls it yet, so there is no caller to move.
DROP FUNCTION IF EXISTS hbh.authorize_meeting_entry(integer);

CREATE FUNCTION hbh.authorize_meeting_entry(p_appointment_id integer)
RETURNS TABLE(meeting_id bigint, room_ref text, provider text,
              moderator_flg boolean, expires_at timestamptz,
              display_name text, user_ref text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_appt hbh.appointments%ROWTYPE;
  l_mtg  hbh.meetings%ROWTYPE;
  l_user hbh.users%ROWTYPE;
  l_ttl  integer;
BEGIN
  -- Fails closed. No identity is not "allowed by default".
  IF hbh.current_user_id() IS NULL THEN
    RAISE EXCEPTION 'no identity' USING ERRCODE = 'HB028';
  END IF;

  SELECT * INTO l_user FROM hbh.users u WHERE u.user_id = hbh.current_user_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no identity' USING ERRCODE = 'HB028';
  END IF;

  SELECT * INTO l_appt FROM hbh.appointments a
  WHERE a.appointment_id = p_appointment_id;

  -- NOT FOUND and NOT YOURS answer the same way on purpose. Telling a
  -- stranger that an appointment exists but is not theirs is telling
  -- them it exists.
  IF NOT FOUND OR NOT hbh.can_access_child(l_appt.child_id) THEN
    RAISE EXCEPTION 'no such appointment %', p_appointment_id USING ERRCODE = 'HB021';
  END IF;

  IF l_appt.delivery_mode <> 'ONLINE' THEN
    RAISE EXCEPTION 'appointment % is not an online consultation', p_appointment_id
      USING ERRCODE = 'HB250';
  END IF;

  -- PAID MEANS CONFIRMED, and that is not a shortcut. The invoice
  -- reaching PAID is what moves an appointment from BOOKED to CONFIRMED
  -- - so asking the status here asks about the money without this
  -- function knowing anything about invoices.
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
    -- A GUARDIAN IS NEVER A MODERATOR. Moderator rights let somebody
    -- mute, remove and admit - which is the therapist's job in the
    -- family's own consultation, not the family's.
    hbh.current_user_is_staff(),
    -- Never past the door, whatever the parameter says. A pass that
    -- outlived its own consultation could not be called back.
    least(now() + make_interval(mins => l_ttl), l_mtg.expires_at),
    -- The adult's own name, for the waiting room. Never the child's.
    l_user.full_name_ar,
    -- An opaque handle for the provider, so two tabs are one person.
    -- The account id and nothing else: not a mobile, not a national id,
    -- nothing that means anything outside this system.
    l_user.user_id::text;
END
$fn$;

COMMENT ON FUNCTION hbh.authorize_meeting_entry(integer) IS
  'Decides whether this caller may enter this consultation now, until when, and under what name. Writes nothing: the pass is signed in the service, where the provider key lives. Raises HB021 / HB250 / HB252 / HB253.';

REVOKE ALL ON FUNCTION hbh.authorize_meeting_entry(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.authorize_meeting_entry(integer) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0123');
