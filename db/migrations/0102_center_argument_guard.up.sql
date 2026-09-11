-- =====================================================================
-- Hand By Hand (new) - migration 0102: the centre that arrives as an
-- argument.
--
-- NUMBER RESERVED BEFORE WRITING, and checked against both the
-- filesystem and hbh.schema_migrations. 0098 and 0100 belong to another
-- session working in this same tree; 0101 is this task's first
-- migration. This tree has no version control, so a collision is not
-- recoverable.
--
-- A DIFFERENT DEFECT SHAPE FROM 0099 AND 0101, and kept in its own
-- migration for exactly that reason. Those two were "the function trusts
-- an ENTITY ID". This is "the function trusts a TENANT".
--
-- ---------------------------------------------------------------------
-- WHAT WAS INSPECTED, BEFORE ANYTHING WAS CHANGED
--
-- REACHABILITY: not reachable. store.BookAppointment sends
--
--     SELECT hbh.book_appointment(
--         hbh.current_center_id(),                <- derived, not sent
--         (SELECT branch_id FROM hbh.rooms WHERE room_id = $3),
--         $1, $2, $3, $4, $5, $6, nullif($7, ''))
--
-- and no handler anywhere reads a center_id out of a request body -
-- grepped and confirmed. hbh.book_recurring has no Go caller at all.
--
-- DB CALLERS: none. A text search named hbh.decide_request, which turned
-- out to mention book_appointment in a COMMENT explaining what it
-- deliberately does not do. Searching for a word is not proof that a
-- path is exercised - this project has paid for that lesson twice and
-- it was true again here.
--
-- EXPLOITABILITY TODAY: zero through the product. The only caller that
-- could pass a foreign centre is one holding the hbh_app credentials
-- directly, and anyone with those is already past every gate this
-- migration could add.
--
-- SO WHY CHANGE IT. Rule 4: a condition in the caller is the weaker copy
-- of a rule, and the weaker copy decides. The safety here lives in one
-- line of Go. One new handler that forwards a client-supplied centre,
-- one refactor of that query, and a receptionist books into another
-- centre's diary - with the function raising no objection, because
-- nobody ever asked it to.
--
-- ---------------------------------------------------------------------
-- COMPATIBILITY IMPACT, which is why this shape and not the "preferred"
-- one.
--
-- Deriving the centre INSIDE the function and dropping the parameter
-- would be cleaner and is the wrong move here: it changes a nine-argument
-- signature that eight acceptance suites and a seed file call directly,
-- and it would break every caller that legitimately runs WITH NO
-- IDENTITY - fixtures and seeds build diaries as the owner, where
-- current_center_id() is NULL by design. A function that derived the
-- centre would have nothing to derive it from and would fail closed on
-- all of them.
--
-- So the parameter stays and is VALIDATED instead:
--
--   caller has an identity  ->  p_center_id must be their own centre
--   caller has none         ->  unchanged, exactly as today
--
-- That is the same shape as the permission check already sitting at the
-- top of book_appointment, which has read "IF current_user_id() IS NOT
-- NULL AND NOT has_permission(...)" since 0016 for the same reason.
--
-- Backward compatible for every caller that was already correct. The
-- only call it refuses is one that was already wrong.
--
-- book_recurring is NOT changed here. It has no caller at all - not Go,
-- not SQL, not a test - so there is nothing to regress and nothing to
-- protect; changing an unused nine-argument function during a security
-- migration buys nothing and costs a rollback path. It is listed as a
-- remaining item instead.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0102') THEN
    RAISE EXCEPTION 'migration 0102 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0101') THEN
    RAISE EXCEPTION 'migration 0101 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- THE GUARD
--
-- Separate from assert_same_center on purpose: that one answers "does
-- this ROW belong to me" and takes an entity. This answers "is this the
-- centre I am in" and takes a tenant. Folding them together would mean
-- one function with two meanings, and the p00 rule would then have to
-- treat a call to it as evidence of either - which is how a check stops
-- meaning anything.
--
-- IT STEPS ASIDE FOR A CALLER WITH NO IDENTITY. That is not a hole: an
-- unauthenticated connection cannot reach these functions through the
-- API at all, and the paths that legitimately have no identity are the
-- owner-run fixtures and seeds.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.assert_center_argument(p_center_id integer)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  IF hbh.current_center_id() IS NOT NULL
     AND p_center_id IS DISTINCT FROM hbh.current_center_id() THEN
    RAISE EXCEPTION 'centre % is not this caller''s centre', p_center_id
      USING ERRCODE = 'HB232';
  END IF;
END
$fn$;

REVOKE ALL ON FUNCTION hbh.assert_center_argument(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.assert_center_argument(integer) TO hbh_app;

-- =====================================================================
-- book_appointment
--
-- The guard goes FIRST - above the permission check, above validate_slot
-- and a long way above next_number. next_number advances a sequence, and
-- a refusal below that line would still burn an appointment number out
-- of another centre's series: a permanent gap nobody could explain.
--
-- Everything below the guard is the deployed body, copied verbatim from
-- pg_get_functiondef rather than retyped. The first attempt at this
-- migration was written from memory and dropped a sentence from the
-- exclusion_violation comment; reading the deployed definition first is
-- the same discipline that caught offer_slot's signature in 0099.
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
    -- Another transaction committed the same slot between the check and
    -- this insert. The index caught it - which is the whole point - and
    -- the caller gets the same reason it would have got a moment
    -- earlier, instead of a raw 23P01.
    RAISE EXCEPTION 'slot rejected: SLOT_TAKEN' USING ERRCODE = 'HB021';
  END;

  RETURN l_id;
END
$fn$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0102');
