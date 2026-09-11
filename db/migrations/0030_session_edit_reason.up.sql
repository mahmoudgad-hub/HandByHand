-- =====================================================================
-- Hand By Hand (new) - migration 0030: telling apart "you may not" and
-- "not yours"
--
-- hbh.can_edit_session answers two different questions with one false,
-- and write_session_note turns both into HB031. So a therapist who
-- HOLDS SESSION.NOTES.EDIT, writing on a colleague's session, is told
-- the same thing as somebody who holds nothing - and the screen ends up
-- telling a clinician that their permission does not permit the thing
-- their permission is named after.
--
-- The fix belongs here and not in Go. Deciding which of two refusals
-- applies is reading the rule, and the rule lives in PL/pgSQL; a
-- handler that guessed from context would be a second copy of it, and
-- the weaker copy decides.
--
-- SO: hbh.check_session_edit is now the rule, returning (ok, reason),
-- and can_edit_session is DERIVED from it. One statement of the rule,
-- two shapes of answer - the same pattern as validate_slot.
--
-- ORDER OF CHECKS IS DELIBERATE. Permission is tested BEFORE authorship,
-- so NOT_YOUR_SESSION only ever reaches somebody who already holds
-- SESSION.NOTES.EDIT. Telling a stranger "that session belongs to
-- somebody else" confirms the session exists and that it is not theirs;
-- telling a colleague the same thing tells them nothing they may not
-- already ask the schedule.
--
-- Error classes:
--   HB031  (unchanged) you may not write notes
--   HB035  (new)       you may, but this session is not yours
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0030') THEN
    RAISE EXCEPTION 'migration 0030 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0006') THEN
    RAISE EXCEPTION 'migration 0006 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- THE RULE, STATED ONCE
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.check_session_edit(p_session_id integer)
RETURNS TABLE (ok boolean, reason text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_user_id      integer := hbh.current_user_id();
  l_owner_user   integer;
  l_status       text;
BEGIN
  -- Fails closed, like everything else. No identity is not "allowed by
  -- default", and it is not "not yours" either - it is no answer.
  IF l_user_id IS NULL THEN
    RETURN QUERY SELECT false, 'NO_IDENTITY'::text;
    RETURN;
  END IF;

  SELECT t.user_id, s.status
    INTO l_owner_user, l_status
  FROM   hbh.therapy_sessions s
  JOIN   hbh.therapists t ON t.therapist_id = s.therapist_id
  WHERE  s.session_id = p_session_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'NO_SESSION'::text;
    RETURN;
  END IF;

  -- Permission first. See the header: this ordering is what keeps
  -- NOT_YOUR_SESSION from being an existence oracle for strangers.
  IF NOT hbh.has_permission('SESSION.NOTES.EDIT') THEN
    RETURN QUERY SELECT false, 'NOT_PERMITTED'::text;
    RETURN;
  END IF;

  IF l_owner_user IS DISTINCT FROM l_user_id THEN
    RETURN QUERY SELECT false, 'NOT_YOUR_SESSION'::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'OK'::text;
END
$$;

COMMENT ON FUNCTION hbh.check_session_edit(integer) IS
  'The authorship rule, with its reason. OK · NO_IDENTITY · NO_SESSION · NOT_PERMITTED · NOT_YOUR_SESSION. can_edit_session is derived from this - do not restate the rule anywhere else.';

-- ---------------------------------------------------------------------
-- The boolean, DERIVED - not a second copy
--
-- Same signature, same meaning, same callers. What changes is that it
-- no longer holds its own statement of the rule that could drift from
-- the one above.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.can_edit_session(p_session_id integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT c.ok FROM hbh.check_session_edit(p_session_id) c
$$;

COMMENT ON FUNCTION hbh.can_edit_session(integer) IS
  'Authorship gate, derived from check_session_edit. The clinician who ran the session, holding SESSION.NOTES.EDIT. Never an administrator - closing is can_close_session.';

-- =====================================================================
-- AND THE CALLER SAYS WHICH REFUSAL IT IS
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.write_session_note(
  p_session_id integer,
  p_body_ar    text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_sess   hbh.therapy_sessions%ROWTYPE;
  l_id     integer;
  l_ok     boolean;
  l_reason text;
BEGIN
  SELECT c.ok, c.reason INTO l_ok, l_reason FROM hbh.check_session_edit(p_session_id) c;

  IF NOT l_ok THEN
    IF l_reason = 'NOT_YOUR_SESSION' THEN
      -- Holds the permission. The session is somebody else's work, and
      -- saying so is the only message that helps.
      RAISE EXCEPTION 'session % was run by another clinician', p_session_id
        USING ERRCODE = 'HB035';
    END IF;
    RAISE EXCEPTION 'not permitted to write notes on session %', p_session_id
      USING ERRCODE = 'HB031';
  END IF;

  SELECT * INTO l_sess FROM hbh.therapy_sessions WHERE session_id = p_session_id;

  INSERT INTO hbh.session_notes (center_id, session_id, child_id, author_user_id, body_ar)
  VALUES (l_sess.center_id, p_session_id, l_sess.child_id, hbh.current_user_id(), p_body_ar)
  RETURNING note_id INTO l_id;

  RETURN l_id;
END
$$;

REVOKE ALL ON FUNCTION hbh.check_session_edit(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.check_session_edit(integer) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0030');
