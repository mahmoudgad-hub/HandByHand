-- =====================================================================
-- 0117 - an appointment can be delivered over video, and then it has no
--        room and the child is not in it
--
-- NUMBER RESERVED BEFORE WRITING. 0106-0111 belong to another session in
-- this tree; 0112-0116 are mine.
--
-- ORDER OF DEPLOYMENT: EITHER WAY ROUND, AND THAT IS NOT LUCK.
--
-- This raises HB250, which is new. 0053 had to say "the API goes first"
-- for exactly this, because a code the layer did not know fell through
-- to a `default` and answered 500 - a rule refusing on purpose reaching
-- the desk as "an unexpected error occurred".
--
-- That hole was closed since. businessRefusal in ops_handlers.go answers
-- ANY HB code it does not recognise with 409 REFUSED rather than 500,
-- and business_refusal_test.go walks HB000 to HB999 to prove it - a test
-- that asserts the property instead of a list, written after eight live
-- codes fell past an earlier fallback and nothing noticed for a month.
--
-- So an API build that has never heard of HB250 still says "refused",
-- and the build that lands beside this one says NOT_IN_PERSON. Checked
-- rather than assumed, because a deployment note that is wrong is worse
-- than no deployment note.
--
-- The new validate_slot REASONS need no care either. day-screen.ts
-- routes an unknown reason to slot.UNKNOWN by design - "a reason added
-- to the schema tomorrow must not print its own constant in Latin
-- letters on an Arabic screen". Their Arabic is added anyway.
--
-- ---------------------------------------------------------------------
-- WHAT THIS IS FOR
--
-- docs/architect/03-online-consultation.md, section 1: a paid online
-- consultation is an APPOINTMENT like any other, in the same table, with
-- a service in the catalogue. Not a consultations table of its own - and
-- the reason is the whole of D-13.
--
-- Double booking is prevented by EXCLUDE USING gist constraints, AND
-- THOSE WORK INSIDE ONE TABLE. A second table would give a therapist's
-- time two sources, and nothing in the engine could stop a consultation
-- and a therapy session at the same minute. The problem whose fix cost
-- what it cost would come back in the one shape no constraint can catch.
--
-- So the appointment stays, and three things about it change.
--
-- ---------------------------------------------------------------------
-- 1. A MODE, AND A ROOM ONLY WHEN THERE IS A ROOM
--
-- room_id was NOT NULL, which said "every appointment happens somewhere
-- in this building". That is no longer true. It becomes nullable, and a
-- CHECK ties it to the mode in both directions.
--
-- BOTH DIRECTIONS, and the second is the one that matters. "IN_PERSON
-- needs a room" is obvious. "ONLINE must NOT have one" is what stops an
-- online consultation from quietly holding a treatment room for an hour
-- against the room exclusion below - a room nobody is in, that reception
-- cannot book, for a reason nothing on the screen would explain.
--
-- It is the same shape as ck_appointments_cancel, two lines above it in
-- the table: (status = 'CANCELLED') = (cancel_reason IS NOT NULL).
--
-- EXTERNAL is in the list because it is in the brief - an appointment
-- delivered somewhere that is not this centre - and it has no room here
-- for the same reason ONLINE does not. Nothing creates one yet.
--
-- ---------------------------------------------------------------------
-- 2. THE ROOM EXCLUSION BECOMES PARTIAL
--
-- Strictly, NULL room_id already cannot collide: the constraint asks
-- room_id = room_id, NULL = NULL is NULL rather than true, and a row
-- that answers NULL excludes nothing. The predicate is added anyway for
-- two reasons, and the first is not the index size.
--
-- A RULE THAT IS TRUE BY ACCIDENT IS A RULE NOBODY CAN SEE. "Online
-- appointments do not take rooms" currently reads as a fact about
-- three-valued logic. Written into the constraint it reads as the
-- decision it is, and it survives the day somebody proposes a sentinel
-- "online room" row to tidy the NULLs away - which is the design the
-- architect's note is actually warning about, because one such row would
-- cap the whole centre at one consultation an hour.
--
-- The second reason is that the index stops carrying entries for rows
-- that can never match.
--
-- ---------------------------------------------------------------------
-- 3. THE CHILD EXCLUSION STOPS COVERING ONLINE
--
-- THE CHILD IS NOT THE ATTENDEE. A consultation is the parent and the
-- therapist talking about the child; the child may be at school. Today
-- the constraint blocks a father from consulting the speech therapist
-- while his son is in a sensory integration session, and that is a
-- perfectly ordinary hour in a centre like this one.
--
-- WHY delivery_mode AND NOT services.creates_session_flg, WHICH IS WHAT
-- THIS RULE IS REALLY ABOUT. An exclusion constraint's predicate may
-- only name columns of its own row. A flag on hbh.services cannot be
-- reached from here at all - and that, rather than convenience, is why
-- the mode lives on the appointment.
--
-- EXTERNAL STAYS INSIDE the constraint: a child seen at their school is
-- still one child in one place at one time.
--
-- AND THE THERAPIST CONSTRAINT IS NOT TOUCHED, not by one character. A
-- consultation occupies the therapist's hour exactly as a session does,
-- and that is the entire point of putting it in this table.
-- =====================================================================

\set ON_ERROR_STOP on

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0117') THEN
    RAISE EXCEPTION 'migration 0117 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0005') THEN
    RAISE EXCEPTION 'migration 0005 must be applied first';
  END IF;
END
$guard$;

-- ---------------------------------------------------------------------
-- The column.
--
-- NOT NULL with a constant default is metadata only on this version of
-- PostgreSQL - no rewrite, no long lock on the diary.
--
-- THE DEFAULT IS LOAD-BEARING, not tidiness. hbh.decide_request and
-- hbh.book_recurring insert appointments without knowing this column
-- exists, and so does every API build until the next one. IN_PERSON is
-- what they have always meant.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.appointments
  ADD COLUMN IF NOT EXISTS delivery_mode text NOT NULL DEFAULT 'IN_PERSON';

ALTER TABLE hbh.appointments
  ADD CONSTRAINT ck_appointments_delivery_mode
  CHECK (delivery_mode IN ('IN_PERSON', 'ONLINE', 'EXTERNAL'));

COMMENT ON COLUMN hbh.appointments.delivery_mode IS
  'Where the hour happens: IN_PERSON in a room here, ONLINE over video, EXTERNAL somewhere else. It decides whether a room is required and whether the child is the attendee.';

ALTER TABLE hbh.appointments ALTER COLUMN room_id DROP NOT NULL;

-- VALIDATED, not NOT VALID. Every existing row is IN_PERSON with a room,
-- so this is true of the table as it stands and there is nothing to
-- excuse. A NOT VALID here would be recording a debt that does not
-- exist.
ALTER TABLE hbh.appointments
  ADD CONSTRAINT ck_appointments_room_mode
  CHECK ((delivery_mode = 'IN_PERSON') = (room_id IS NOT NULL));

-- ---------------------------------------------------------------------
-- The two exclusion constraints, rebuilt.
--
-- Dropped and re-added rather than altered: a constraint's predicate
-- cannot be changed in place. Both rebuild their GiST index, which on a
-- diary this size is a moment - and it is an ACCESS EXCLUSIVE lock, so
-- it is a moment when nothing books.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.appointments DROP CONSTRAINT ex_appointments_room;

ALTER TABLE hbh.appointments
  ADD CONSTRAINT ex_appointments_room
  EXCLUDE USING gist (
    room_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&)
  WHERE (status IN ('BOOKED', 'CONFIRMED', 'CHECKED_IN', 'COMPLETED')
         AND room_id IS NOT NULL);

ALTER TABLE hbh.appointments DROP CONSTRAINT ex_appointments_child;

ALTER TABLE hbh.appointments
  ADD CONSTRAINT ex_appointments_child
  EXCLUDE USING gist (
    child_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&)
  WHERE (status IN ('BOOKED', 'CONFIRMED', 'CHECKED_IN', 'COMPLETED')
         AND delivery_mode <> 'ONLINE');

-- ---------------------------------------------------------------------
-- validate_slot: the explanation has to agree with the guarantee
--
-- Its own comment says the three overlap checks "duplicate the exclusion
-- constraints on purpose: the constraint is the guarantee, this is the
-- explanation". An explanation that no longer matches is worse than
-- none - reception would be told CHILD_BUSY by this function and then
-- have the booking accepted by the index, or the reverse, and neither
-- has an answer anybody at a desk can act on. So CHILD_BUSY gains the
-- same AND the constraint just gained.
--
-- DROPPED AND RECREATED because a parameter is being added, and a
-- defaulted trailing parameter on a second overload would make every
-- existing eight-argument call ambiguous rather than backward
-- compatible. With the old one gone, api/internal/store/ops_write.go
-- keeps working unchanged - it passes eight and gets IN_PERSON.
--
-- THREE NEW REASONS. Each is a case that used to be impossible and is
-- now merely wrong, and every one of them is a sentence a receptionist
-- can act on rather than a constraint name.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS hbh.validate_slot(integer, integer, integer, integer, integer,
                                          timestamptz, timestamptz, integer);

CREATE FUNCTION hbh.validate_slot(
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
  -- Declared, NOT initialised here.
  --
  -- A DECLARE initialiser runs before the first line of the body, so
  -- building the range up there happened BEFORE the check below - and a
  -- reversed window raised 22000 "range lower bound must be less than
  -- or equal to range upper bound" instead of returning BAD_WINDOW.
  -- The guard has to come first, which means the range comes after it.
  l_span      tstzrange;
BEGIN
  IF p_ends_at <= p_starts_at THEN
    RETURN QUERY SELECT false, 'BAD_WINDOW'; RETURN;
  END IF;

  IF p_delivery_mode IS NULL
     OR p_delivery_mode NOT IN ('IN_PERSON', 'ONLINE', 'EXTERNAL') THEN
    RETURN QUERY SELECT false, 'BAD_DELIVERY_MODE'; RETURN;
  END IF;

  -- The two halves of ck_appointments_room_mode, said early and said in
  -- words. Reaching the INSERT and coming back as a check violation
  -- would name a constraint at a person who asked about a room.
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

  -- The weekend and the working day are questions about the centre's
  -- LOCAL calendar, so the instant is rendered in the centre's zone
  -- before either is asked.
  --
  -- AND THAT STAYS TRUE FOR A CONSULTATION WITH A FAMILY IN RIYADH. The
  -- hour belongs to the therapist, who is here; a parent an hour ahead
  -- reads it converted. Anything else would let a booking land outside
  -- the centre's own working day because of where the caller was.
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

  -- The room, and the branch that comes with it. With no room there is
  -- no branch either, and the BRANCH_CLOSED check below already asks
  -- whether it found one - so a consultation is subject to the CENTRE's
  -- closures and not to any one branch's.
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

  -- ---------------------------------------------------------------
  -- Closures. Checked BEFORE working hours, because "the centre is
  -- shut on Eid" is a better answer than "outside working hours".
  -- ---------------------------------------------------------------
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

  -- These three duplicate the exclusion constraints on purpose: the
  -- constraint is the guarantee, this is the explanation. Each predicate
  -- below is the predicate of its constraint, and they have to be
  -- changed together or the screen and the index start disagreeing.

  -- Unchanged, and deliberately so: a consultation takes the
  -- therapist's hour exactly as a session does.
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

  -- TWO CHANGES, AND THEY ARE NOT THE SAME CHANGE.
  --
  -- The outer one: an ONLINE booking does not ask this question at all,
  -- because the child is not the one attending it.
  --
  -- The inner one: an existing ONLINE appointment does not answer it
  -- either. Without that, booking a child's therapy session would be
  -- refused because their father is on a video call about them - the
  -- exact hour the constraint was just changed to allow.
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

COMMENT ON FUNCTION hbh.validate_slot(integer, integer, integer, integer, integer,
                                      timestamptz, timestamptz, integer, text) IS
  'Why a slot is or is not bookable, in one word. Its three overlap checks mirror the exclusion constraints on hbh.appointments exactly; change one and change the other.';

REVOKE ALL ON FUNCTION hbh.validate_slot(integer, integer, integer, integer, integer,
                                         timestamptz, timestamptz, integer, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.validate_slot(integer, integer, integer, integer, integer,
                                            timestamptz, timestamptz, integer, text) TO hbh_app;

-- ---------------------------------------------------------------------
-- book_appointment: the same parameter, in the same place, defaulted the
-- same way.
--
-- Dropped and recreated for the reason above. api/internal/store/
-- ops_write.go passes nine arguments and keeps working; the tenth
-- defaults to IN_PERSON.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS hbh.book_appointment(integer, integer, integer, integer, integer,
                                             integer, timestamptz, timestamptz, text);

CREATE FUNCTION hbh.book_appointment(
  p_center_id integer, p_branch_id integer, p_child_id integer,
  p_therapist_id integer, p_room_id integer, p_service_id integer,
  p_starts_at timestamptz, p_ends_at timestamptz,
  p_note_ar text DEFAULT NULL,
  p_delivery_mode text DEFAULT 'IN_PERSON')
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
  -- ADDED IN 0102.
  PERFORM hbh.assert_center_argument(p_center_id);

  -- ADDED IN 0016. A family asks; the centre decides. Without this a
  -- guardian could book straight into the diary, which makes
  -- hbh.parent_requests - and its RESCHEDULE and CANCEL kinds -
  -- decorative.
  IF hbh.current_user_id() IS NOT NULL
     AND NOT hbh.has_permission('APPOINTMENT.BOOK') THEN
    RAISE EXCEPTION 'not permitted to book an appointment'
      USING ERRCODE = 'HB027';
  END IF;

  SELECT * INTO l_check
  FROM hbh.validate_slot(p_center_id, p_child_id, p_therapist_id, p_room_id,
                         p_service_id, p_starts_at, p_ends_at, NULL, p_delivery_mode);
  IF NOT l_check.ok THEN
    RAISE EXCEPTION 'slot rejected: %', l_check.reason USING ERRCODE = 'HB021';
  END IF;

  l_no := hbh.next_number(p_center_id, 'APPT');

  BEGIN
    INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id,
                                  therapist_id, room_id, service_id, starts_at, ends_at,
                                  note_ar, delivery_mode)
    VALUES (p_center_id, p_branch_id, l_no, p_child_id, p_therapist_id, p_room_id,
            p_service_id, p_starts_at, p_ends_at, p_note_ar, p_delivery_mode)
    RETURNING appointment_id INTO l_id;
  EXCEPTION WHEN exclusion_violation THEN
    -- Another transaction committed the same slot between the check and
    -- this insert. The index caught it - which is the whole point - and
    -- the caller gets the same reason it would have got a moment
    -- earlier, instead of a raw 23P01.
    RAISE EXCEPTION 'slot rejected: SLOT_TAKEN' USING ERRCODE = 'HB021';
  END;

  RETURN l_id;
END
$fn$;

COMMENT ON FUNCTION hbh.book_appointment(integer, integer, integer, integer, integer,
                                         integer, timestamptz, timestamptz, text, text) IS
  'Books one appointment after hbh.validate_slot accepts it. p_delivery_mode defaults to IN_PERSON so every caller written before 0117 keeps its meaning.';

REVOKE ALL ON FUNCTION hbh.book_appointment(integer, integer, integer, integer, integer,
                                            integer, timestamptz, timestamptz, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.book_appointment(integer, integer, integer, integer, integer,
                                               integer, timestamptz, timestamptz, text, text) TO hbh_app;

-- ---------------------------------------------------------------------
-- start_session refuses a consultation, by name
--
-- WHY THIS IS PART OF THE SAME CHANGE. hbh.therapy_sessions.room_id is
-- NOT NULL. The moment room_id here became nullable, start_session on an
-- ONLINE appointment stopped being impossible and started being a raw
-- 23502 from inside a SECURITY DEFINER function - a null value in column
-- "room_id", named at a therapist who pressed Start.
--
-- Making room_id nullable without this would be leaving the landmine and
-- calling it someone else's step.
--
-- WHAT IT IS NOT. This is not services.creates_session_flg, which is the
-- rule the architect's note actually asks for and which belongs with the
-- catalogue work. This is the narrower fact that a consultation has no
-- room and a therapy session needs one. When the flag arrives, this
-- check becomes its special case rather than its competitor.
--
-- ORDER OF THE CHECKS. The mode is asked after "is this row mine" and
-- BEFORE "is it CHECKED_IN": a therapist who checked a consultation in
-- and pressed Start is better told "a consultation has no session" than
-- told the status is wrong, which would be true and useless.
--
-- Otherwise identical to 0087.
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
  -- Fails closed. No identity is not "allowed by default".
  IF hbh.current_user_id() IS NULL THEN
    RAISE EXCEPTION 'no identity' USING ERRCODE = 'HB028';
  END IF;

  -- Permission BEFORE the row is read - see the header.
  IF NOT hbh.has_permission('SESSION.START') THEN
    RAISE EXCEPTION 'not permitted to start a session' USING ERRCODE = 'HB028';
  END IF;

  SELECT * INTO l_appt FROM hbh.appointments a
  WHERE a.appointment_id = p_appointment_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such appointment %', p_appointment_id USING ERRCODE = 'HB021';
  END IF;

  -- Whose appointment it is. Asked after the row is found because the
  -- rule is about this row, and only a caller who already holds
  -- SESSION.START has got this far.
  IF NOT hbh.can_start_session(p_appointment_id) THEN
    RAISE EXCEPTION 'appointment % belongs to another therapist', p_appointment_id
      USING ERRCODE = 'HB028';
  END IF;

  -- ADDED IN 0117.
  IF l_appt.delivery_mode <> 'IN_PERSON' THEN
    RAISE EXCEPTION 'appointment % is delivered %, and only an in-person appointment opens a therapy session',
                    p_appointment_id, l_appt.delivery_mode
      USING ERRCODE = 'HB250',
            HINT = 'a consultation is written up as a note, not as a session';
  END IF;

  -- The child must be in the building. This is the check, and a test
  -- that expects it must assert HB024 and nothing else - a refusal for
  -- some other reason has proven nothing.
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

INSERT INTO hbh.schema_migrations (version) VALUES ('0117');
