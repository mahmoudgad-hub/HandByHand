-- =====================================================================
-- 0118 - the service says whether it opens a session and whether it
--        needs a caseload
--
-- NUMBER RESERVED BEFORE WRITING. 0106-0111 belong to another session in
-- this tree; 0112-0117 are mine.
--
-- ORDER OF DEPLOYMENT: EITHER WAY ROUND. This raises HB251, which is
-- new, and businessRefusal answers any unknown HB code with 409 REFUSED
-- rather than 500 - proven by business_refusal_test.go walking HB000 to
-- HB999. The build that lands beside this one says SERVICE_NEEDS_ROOM;
-- one that has not heard of it says "refused". Checked, not assumed.
--
-- ---------------------------------------------------------------------
-- WHY
--
-- docs/architect/03-online-consultation.md, section 1, change four:
--
--   "علَمان على services: needs_caseload_flg · creates_session_flg
--    start_session ترفض بلا caseload (HB023)، والاستشارة لا caseload لها
--    ولا تُنشئ therapy_session"
--
-- start_session requires a caseload row - therapist, child, service -
-- before a session may open, and that is right for therapy: it is how
-- the schema says this clinician is responsible for this child's speech
-- work. A consultation has none of that. The parent is paying for an
-- hour of an opinion; nobody is taking a child onto a caseload, and
-- there is no therapy session to open at the end of it.
--
-- ---------------------------------------------------------------------
-- WHY FLAGS AND NOT kind_code
--
-- services.kind_code already exists and the note calls the consultation
-- service CONSULT. It is tempting to branch on it. It is also free text:
-- no CHECK, no lookup, and the two values in the table today are OT and
-- SPEECH because somebody typed them.
--
-- A behaviour keyed off it would be a rule enforced by a spelling. The
-- day a centre adds CONSULTATION, or CONSULT_ONLINE, or writes it in
-- Arabic, sessions start opening on consultations again - silently,
-- because nothing anywhere says those strings are load-bearing.
--
-- A flag is a decision somebody made and can be read. kind_code stays
-- what it is: a label for a screen.
--
-- ---------------------------------------------------------------------
-- WHAT REPLACES THE 0117 GUARD
--
-- 0117 made start_session refuse anything not delivered IN_PERSON, and
-- said in its own comment that this was the narrow version of a rule
-- that belongs here. It was narrow in both directions:
--
--   TOO WIDE - it refused an in-person appointment for a service that
--     does not open sessions too, but by accident rather than by rule.
--   TOO NARROW - it said nothing about a therapy service booked ONLINE
--     by mistake, which would have reached the INSERT and failed on
--     therapy_sessions.room_id NOT NULL.
--
-- So HB250 now asks the real question - does this SERVICE open a
-- session - and the second case is closed where it should have been all
-- along: at booking, by the trigger below, before anybody is waiting.
--
-- ---------------------------------------------------------------------
-- AND THE NEW RULE IS ABOUT A ROOM, NOT ABOUT A MODE
--
-- The trigger says "a service that opens a session must be booked into a
-- room", not "must be IN_PERSON". They mean the same thing today, since
-- ck_appointments_room_mode ties the two - but they are not the same
-- statement, and the difference is where the next change lands.
--
-- therapy_sessions.room_id is NOT NULL. THAT is why a session needs a
-- room. The day the centre wants to record a session delivered at a
-- child's school, the thing to change is that column - not a rule here
-- that would have been quietly asserting something about video calls.
-- =====================================================================

\set ON_ERROR_STOP on

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0118') THEN
    RAISE EXCEPTION 'migration 0118 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0117') THEN
    RAISE EXCEPTION 'migration 0117 must be applied first';
  END IF;
END
$guard$;

-- ---------------------------------------------------------------------
-- The two flags.
--
-- BOTH DEFAULT TRUE, and that is the conservative direction rather than
-- the convenient one. Every service in this table today is therapy: it
-- opens a session and it wants a caseload. A default of false would
-- silently switch off the caseload check - the rule that says which
-- clinician is answerable for which child's work - on every existing
-- row, which is a safeguard disappearing rather than a column arriving.
--
-- NOT NULL for the same reason. A third state would have to be given a
-- meaning by every reader, and readers disagree.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.services
  ADD COLUMN IF NOT EXISTS creates_session_flg boolean NOT NULL DEFAULT true;

ALTER TABLE hbh.services
  ADD COLUMN IF NOT EXISTS needs_caseload_flg boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN hbh.services.creates_session_flg IS
  'Whether an appointment for this service opens a hbh.therapy_sessions row. False for a consultation: the hour is an opinion, written up as a note. Read by hbh.start_session and by the guard that keeps such a service in a room.';

COMMENT ON COLUMN hbh.services.needs_caseload_flg IS
  'Whether hbh.start_session requires a caseload row before opening a session. True for therapy - it is how the schema says this clinician is answerable for this child. Meaningless when creates_session_flg is false, and that is checked rather than assumed.';

-- The two are not independent. A service that opens no session is never
-- asked about a caseload, so a row claiming to need one is a statement
-- with no effect - and a setting with no effect is a setting somebody
-- will rely on.
ALTER TABLE hbh.services
  ADD CONSTRAINT ck_services_caseload_needs_session
  CHECK (creates_session_flg OR NOT needs_caseload_flg);

-- ---------------------------------------------------------------------
-- A service that opens a session must be booked into a room.
--
-- WHY A TRIGGER AND NOT A CHECK. The rule spans two tables - the
-- appointment's room and the service's flag - and a CHECK may only see
-- its own row. This is the smallest thing that can ask the question.
--
-- WHY AT BOOKING AND NOT AT START. Because at booking it is a typo
-- somebody can fix, and at start it is a family in a room. 0117 left it
-- to start_session by default, and that is the later, more expensive
-- half of the same discovery.
--
-- SECURITY DEFINER with a fixed search_path, like every other trigger
-- function here: it reads hbh.services, which is behind RLS, from
-- whatever session happens to be booking.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.guard_service_needs_room()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_creates boolean;
BEGIN
  IF NEW.room_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT s.creates_session_flg INTO l_creates
  FROM hbh.services s WHERE s.service_id = NEW.service_id;

  -- A service that is not there is the foreign key's problem, not this
  -- one. Answering here would be a second opinion on a question already
  -- decided, and a worse one.
  IF l_creates IS NULL OR NOT l_creates THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'service % opens a therapy session and a session needs a room', NEW.service_id
    USING ERRCODE = 'HB251',
          HINT = 'book it in person, or use a service that does not open a session';
END
$fn$;

COMMENT ON FUNCTION hbh.guard_service_needs_room() IS
  'Refuses an appointment with no room for a service that opens a therapy session. Raises HB251. The rule is about the room because hbh.therapy_sessions.room_id is NOT NULL.';

DROP TRIGGER IF EXISTS trg_appointments_service_room ON hbh.appointments;
CREATE TRIGGER trg_appointments_service_room
  BEFORE INSERT OR UPDATE OF service_id, room_id ON hbh.appointments
  FOR EACH ROW EXECUTE FUNCTION hbh.guard_service_needs_room();

-- ---------------------------------------------------------------------
-- validate_slot explains it before the insert refuses it.
--
-- Same signature as 0117, so CREATE OR REPLACE rather than a drop, and
-- no caller moves.
--
-- The new check sits with the other two about the shape of the request -
-- ROOM_REQUIRED and ROOM_NOT_ALLOWED - because it is the same kind of
-- question: is this combination of fields a thing at all. It reads the
-- service, and a service that does not exist falls through to
-- THERAPIST_SERVICE_MISMATCH below, which already names that.
-- ---------------------------------------------------------------------
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
  l_creates   boolean;
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

  -- ADDED IN 0118, and it mirrors trg_appointments_service_room.
  IF p_room_id IS NULL THEN
    SELECT s.creates_session_flg INTO l_creates
    FROM hbh.services s WHERE s.service_id = p_service_id;
    IF l_creates THEN
      RETURN QUERY SELECT false, 'SERVICE_NEEDS_ROOM'; RETURN;
    END IF;
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

-- ---------------------------------------------------------------------
-- start_session asks the service, not the mode.
--
-- THE CASELOAD CHECK BECOMES CONDITIONAL AND NOT OPTIONAL. It is skipped
-- only for a service whose row says it does not want one; for everything
-- else it is exactly the check it was, raising exactly HB023. A flag
-- that could be set to false on a therapy service by accident would be
-- a safeguard with an off switch - which is why the default is true and
-- ck_services_caseload_needs_session keeps the pair coherent.
--
-- Otherwise identical to 0117.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.start_session(p_appointment_id integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_appt     hbh.appointments%ROWTYPE;
  l_svc      hbh.services%ROWTYPE;
  l_id       integer;
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

  SELECT * INTO l_svc FROM hbh.services s WHERE s.service_id = l_appt.service_id;

  -- fk_appointments_service makes this impossible, AND IT IS CHECKED
  -- ANYWAY. Without it, a missing row leaves every flag NULL, `NOT NULL`
  -- is UNKNOWN rather than true, `IF UNKNOWN THEN` does not run, and
  -- BOTH gates below are skipped on the way to an INSERT - a session
  -- opened for a service that says it has none, with no caseload check.
  -- That is the shape that let a NULL code sign somebody in through
  -- verify_otp, and it costs one IF to not have it here.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'appointment % names service %, which does not exist',
                    p_appointment_id, l_appt.service_id
      USING ERRCODE = 'HB021';
  END IF;

  -- ADDED IN 0117 AS A QUESTION ABOUT THE MODE, ASKED HERE AS A QUESTION
  -- ABOUT THE SERVICE. Still before the status check: a therapist who
  -- checked a consultation in is better told what it is than sent to fix
  -- a status that was never the problem.
  IF NOT l_svc.creates_session_flg THEN
    RAISE EXCEPTION 'service % does not open a therapy session', l_svc.code
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

  IF l_svc.needs_caseload_flg
     AND NOT EXISTS (SELECT 1 FROM hbh.caseload c
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

INSERT INTO hbh.schema_migrations (version) VALUES ('0118');
