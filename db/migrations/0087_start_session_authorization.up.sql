-- =====================================================================
-- start_session had no authorization check at all.
--
-- WHAT WAS WRONG. hbh.start_session is SECURITY DEFINER, so RLS does not
-- apply inside it, and it asked four questions - does the appointment
-- exist, is it CHECKED_IN, does it already have a session, is the
-- APPOINTMENT'S therapist on the caseload - and not one of them is about
-- the CALLER. It never asked for SESSION.START and never asked whether
-- the caller is the therapist the appointment names.
--
-- Proven, not inferred: signed in as a GUARDIAN - hbh.has_permission
-- ('SESSION.START') returns false for them - the call reached the status
-- check and was refused with HB024 "appointment is COMPLETED". A refusal
-- about the ROW's state is a refusal that already walked past the
-- caller's identity. On a CHECKED_IN appointment it would have inserted
-- the session.
--
-- The console was never the hole: day-spec.ts gates the button on
-- SESSION.START, so reception - which does not hold it - has never seen
-- it. The rule existed in the client and nowhere else, which is the one
-- place this project says a rule may never live (CLAUDE.md, rule 4).
--
-- WHAT THIS DOES NOT CHANGE. No role gains or loses a permission, and
-- the seed is untouched. RECEPTION could technically call this before
-- and cannot now: that is the RBAC seed being enforced rather than
-- amended - checking a child in is reception's work, starting the
-- clinical session is not, and their role has never listed SESSION.START.
--
-- ORDER IS LOAD-BEARING, and it is the ordering 0030 already argued for
-- on check_session_edit: the permission is asked FIRST, before the
-- appointment is even looked up. Reversed, HB021 "no such appointment"
-- becomes an existence oracle over the centre's diary for anyone who can
-- reach the endpoint.
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- WHO MAY START ONE
--
-- Deliberately the same shape as hbh.can_close_session, and for the same
-- reason it gives: a clinician starts their OWN work, an administrator
-- may start anyone's. Two different justifications, so two branches.
--
-- user_type = 'STAFF' is load-bearing on the second branch. THERAPIST
-- holds CHILD.VIEW_ALL so a clinician can cover for a colleague; without
-- the STAFF test that grant alone would let any therapist start any
-- other therapist's session, which is not an administrative override but
-- no rule at all. can_close_session learned this from the acceptance
-- suite; this function is not going to relearn it.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.can_start_session(p_appointment_id integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT EXISTS (
    -- the therapist the appointment names
    SELECT 1 FROM hbh.appointments a
    JOIN   hbh.therapists t ON t.therapist_id = a.therapist_id
    WHERE  a.appointment_id = p_appointment_id
    AND    t.user_id = hbh.current_user_id()

    UNION ALL

    -- or an administrator: STAFF holding both rights.
    SELECT 1 FROM hbh.appointments a
    JOIN   hbh.users u ON u.user_id = hbh.current_user_id()
    WHERE  a.appointment_id = p_appointment_id
    AND    u.user_type = 'STAFF'
    AND    hbh.has_permission('CHILD.VIEW_ALL')
    AND    hbh.has_permission('SESSION.START')
  )
$$;

COMMENT ON FUNCTION hbh.can_start_session(integer) IS
  'Who may open a session on an appointment: the therapist it names, or STAFF holding CHILD.VIEW_ALL and SESSION.START. Mirrors can_close_session - do not restate the rule anywhere else.';

-- ---------------------------------------------------------------------
-- THE GUARD, ADDED TO start_session
--
-- Everything below the two new blocks is the body as it shipped in
-- 0005_scheduling.up.sql, unchanged: same checks, same SQLSTATEs, same
-- order, same insert. Only the authorization is new.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.start_session(p_appointment_id integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
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
$$;

REVOKE ALL ON FUNCTION hbh.can_start_session(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.can_start_session(integer) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0087');
