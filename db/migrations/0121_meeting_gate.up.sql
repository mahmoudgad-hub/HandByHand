-- =====================================================================
-- 0121 - the room opens itself, and the door decides who comes in
--
-- NUMBER RESERVED BEFORE WRITING. 0119 belongs to another session in
-- this tree; 0112-0118 and 0120 are mine and this completes 0120.
--
-- ORDER OF DEPLOYMENT: EITHER WAY ROUND. HB252 and HB253 are new, and
-- businessRefusal answers any unknown HB code with 409 rather than 500.
--
-- ---------------------------------------------------------------------
-- FIRST, A GRANT 0120 PUT IN THE WRONG PLACE
--
-- 0120 ran GRANT ... ON ALL SEQUENCES before it created
-- hbh.meeting_tokens, so that table's identity sequence was not covered
-- - ALL SEQUENCES means the ones that exist when the statement runs.
-- The table reads perfectly and refuses every insert with "permission
-- denied for sequence", which looks like a policy fault when the
-- policies are fine.
--
-- It is the defect 0061 shipped and 0062 fixed, and it was caught here
-- by the check that exists because of it: p00_verify's "every sequence
-- is usable by hbh_app", within a minute of applying.
-- ---------------------------------------------------------------------
\set ON_ERROR_STOP on

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0121') THEN
    RAISE EXCEPTION 'migration 0121 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0120') THEN
    RAISE EXCEPTION 'migration 0120 must be applied first';
  END IF;
END
$guard$;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

-- =====================================================================
-- 1. THE ROOM APPEARS WITH THE APPOINTMENT
--
-- A TRIGGER AND NOT A CALL IN book_appointment, because there is more
-- than one way an appointment is created - book_appointment,
-- book_recurring, decide_request, and whatever is added next - and a
-- consultation with no room is a family pressing a button that does
-- nothing. "No path forgets to call it" is a property of the table, not
-- of today's callers.
--
-- THE DOOR IS COMPUTED ONCE AND STORED, not derived at display time from
-- the parameters. Moving CONSULT_DOOR_OPENS_MIN next month must not
-- silently move the door on consultations a family has already been told
-- about.
--
-- AND IT MOVES WHEN THE APPOINTMENT MOVES. Rescheduling is an ordinary
-- thing here - hbh.parent_requests has a RESCHEDULE kind - and a room
-- whose door still opens at last week's time is a room nobody can enter.
--
-- AND IT CLOSES WHEN THE APPOINTMENT DIES. This is the rule the
-- architect's note states outright: "الإلغاء وإعادة الجدولة تكتبان صفّ
-- إغلاق. غرفة موعد مُلغى تبقى مفتوحة، ومن يملك رابطها يدخل." A token
-- already in a browser cannot be called back, so closing the row is the
-- only thing that stops the NEXT pass being issued.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.trg_appointment_meeting()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_opens_min integer;
  l_grace_min integer;
  l_provider  text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.delivery_mode <> 'ONLINE' THEN
      RETURN NULL;
    END IF;

    l_opens_min := hbh.param(NEW.center_id, 'CONSULT_DOOR_OPENS_MIN', '10')::integer;
    l_grace_min := hbh.param(NEW.center_id, 'CONSULT_DOOR_GRACE_MIN', '15')::integer;
    l_provider  := hbh.param(NEW.center_id, 'MEETING_PROVIDER', 'JITSI_PUBLIC');

    INSERT INTO hbh.meetings (center_id, appointment_id, provider, room_ref,
                              status, opens_at, expires_at)
    VALUES (NEW.center_id, NEW.appointment_id, l_provider,
            -- 32 hex characters of randomness. Not the appointment
            -- number, not a hash of it: with Jitsi a room exists by
            -- being joined, so a guessable name is an open door.
            encode(public.gen_random_bytes(16), 'hex'),
            'READY',
            NEW.starts_at - make_interval(mins => l_opens_min),
            NEW.ends_at   + make_interval(mins => l_grace_min));

    RETURN NULL;
  END IF;

  -- UPDATE from here.

  -- The appointment moved. The door moves with it, and only for a room
  -- still open - a closed one stays closed.
  IF NEW.starts_at IS DISTINCT FROM OLD.starts_at
     OR NEW.ends_at IS DISTINCT FROM OLD.ends_at THEN
    l_opens_min := hbh.param(NEW.center_id, 'CONSULT_DOOR_OPENS_MIN', '10')::integer;
    l_grace_min := hbh.param(NEW.center_id, 'CONSULT_DOOR_GRACE_MIN', '15')::integer;

    UPDATE hbh.meetings m
       SET opens_at   = NEW.starts_at - make_interval(mins => l_opens_min),
           expires_at = NEW.ends_at   + make_interval(mins => l_grace_min)
     WHERE m.appointment_id = NEW.appointment_id
       AND m.status = 'READY';
  END IF;

  -- The appointment died. So does the room.
  --
  -- A SEPARATE STATEMENT FROM THE ONE ABOVE, and deliberately: a row may
  -- be updated once per statement, and a reschedule that also cancelled
  -- would have left whichever came second silently discarded.
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NEW.status IN ('CANCELLED', 'NO_SHOW') THEN
    UPDATE hbh.meetings m
       SET status        = 'CLOSED',
           closed_at     = now(),
           closed_reason = 'APPOINTMENT_' || NEW.status
     WHERE m.appointment_id = NEW.appointment_id
       AND m.status <> 'CLOSED';
  END IF;

  RETURN NULL;
END
$fn$;

COMMENT ON FUNCTION hbh.trg_appointment_meeting() IS
  'Opens a room for an ONLINE appointment, moves its door when the appointment moves, and closes it when the appointment is cancelled or missed. A closed room is the only thing that stops the next pass being issued - the ones already in a browser cannot be called back.';

DROP TRIGGER IF EXISTS trg_appointments_meeting ON hbh.appointments;
CREATE TRIGGER trg_appointments_meeting
  AFTER INSERT OR UPDATE OF starts_at, ends_at, status ON hbh.appointments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_appointment_meeting();

-- =====================================================================
-- 2. THE DOOR
--
-- WHY THIS IS TWO FUNCTIONS AND NOT THE ONE THE ARCHITECT'S NOTE NAMES.
--
-- The note calls for issue_meeting_token. It cannot be one function
-- here, because the thing being issued is a JWT signed with the
-- provider's private key - and that key lives in the service's
-- environment, not in the database. A database that could mint the pass
-- would be a database holding the credential for every consultation the
-- centre will ever hold.
--
-- So the decision and the evidence are separated:
--
--   authorize_meeting_entry  decides, and writes nothing
--   record_meeting_token     writes, and decides nothing
--
-- Which is D-1 exactly - "the function either changes state or refuses,
-- never both" - arriving by a different road.
--
-- THE SERVICE MUST RECORD BEFORE IT ANSWERS. If recording fails, the
-- pass is not handed out. The other order gives away a pass with no
-- record of who took it, which is the one outcome this pair exists to
-- prevent.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.authorize_meeting_entry(p_appointment_id integer)
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
  -- Fails closed. No identity is not "allowed by default".
  IF hbh.current_user_id() IS NULL THEN
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
    least(now() + make_interval(mins => l_ttl), l_mtg.expires_at);
END
$fn$;

COMMENT ON FUNCTION hbh.authorize_meeting_entry(integer) IS
  'Decides whether this caller may enter this consultation now, and until when. Writes nothing: the pass is signed in the service, where the provider key lives. Raises HB021 / HB250 / HB252 / HB253.';

REVOKE ALL ON FUNCTION hbh.authorize_meeting_entry(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.authorize_meeting_entry(integer) TO hbh_app;

CREATE OR REPLACE FUNCTION hbh.record_meeting_token(
  p_meeting_id bigint, p_token_hash bytea,
  p_moderator boolean, p_expires_at timestamptz,
  p_client_ip inet DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_center integer;
  l_user   integer;
  l_id     bigint;
BEGIN
  l_user := hbh.current_user_id();
  IF l_user IS NULL THEN
    RAISE EXCEPTION 'no identity' USING ERRCODE = 'HB028';
  END IF;

  IF p_token_hash IS NULL OR length(p_token_hash) < 16 THEN
    RAISE EXCEPTION 'a pass record needs the hash of the pass'
      USING ERRCODE = 'HB231';
  END IF;

  SELECT m.center_id INTO l_center FROM hbh.meetings m WHERE m.meeting_id = p_meeting_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such meeting %', p_meeting_id USING ERRCODE = 'HB021';
  END IF;

  -- The centre comes from the ROW, never from an argument. Eight
  -- functions in this schema once took a raw identifier and asked only
  -- "may you do this kind of thing", and one of them was account
  -- takeover across centres.
  INSERT INTO hbh.meeting_tokens (center_id, token_hash, meeting_id, user_id,
                                  moderator_flg, expires_at, client_ip)
  VALUES (l_center, p_token_hash, p_meeting_id, l_user,
          coalesce(p_moderator, false), p_expires_at, p_client_ip)
  RETURNING meeting_token_id INTO l_id;

  RETURN l_id;
END
$fn$;

COMMENT ON FUNCTION hbh.record_meeting_token(bigint, bytea, boolean, timestamptz, inet) IS
  'Writes the evidence that a pass was issued: who, which room, when, until when, from where. Decides nothing - authorize_meeting_entry has already done that, and the service calls this BEFORE it answers.';

REVOKE ALL ON FUNCTION hbh.record_meeting_token(bigint, bytea, boolean, timestamptz, inet) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.record_meeting_token(bigint, bytea, boolean, timestamptz, inet) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0121');
