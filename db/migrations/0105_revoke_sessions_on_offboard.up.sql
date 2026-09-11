-- =====================================================================
-- 0105 — CLOSING AN ACCOUNT CLOSES ITS SESSIONS
--
-- NUMBER RESERVED BEFORE WRITING. 0101-0104 belong to another session
-- working in this same tree and were all applied while this was being
-- written; 0100 (available_slots) is mine. Two files on one number is a
-- migration that vanishes without a word.
--
-- NO NEW SQLSTATE, so the API does not have to go down first. This
-- raises nothing: it is a trigger that writes rows.
--
-- ---------------------------------------------------------------------
-- WHAT WAS ALREADY TRUE, AND WHY IT WAS NOT ENOUGH
--
-- Suspending somebody already ends their access IMMEDIATELY, and that
-- was measured, not assumed: hbh.resolve_auth_session checks active_flg
-- and status on every single request, so a live bearer token answers 401
-- on the next call and a fresh login answers 423 USER_LOCKED. There is
-- no window and there was no hole.
--
-- What was wrong was the RECORD. The row in hbh.auth_sessions kept
-- revoked_at NULL and an expires_at eight hours out, so the table went on
-- describing a suspended employee as having an open session. Every
-- question anybody would ask it - who is signed in now, was anyone signed
-- in when we let X go, how many sessions did this account have open -
-- answered wrongly, and answered wrongly with total confidence.
--
-- That is the failure mode 0084 already named for this same table:
-- derived state that FALSIFIES rather than conceals. An inert session
-- that still reads as live is worse than no record at all, because
-- somebody will believe it.
--
-- ---------------------------------------------------------------------
-- WHY A TRIGGER AND NOT A LINE IN update_user
--
-- Three paths take an account out of service - hbh.update_user sets the
-- status, hbh.archive_user clears active_flg, and a future fourth will do
-- something nobody has thought of yet. A line in one of them is a rule
-- that holds for one path, and the path that forgets it is the one that
-- leaves a session reading as live.
--
-- It also keeps the rule in PL/pgSQL where rule 2 puts it, rather than in
-- the Go handler that happens to call today's function.
--
-- AND IT ONLY EVER CLOSES. Reinstating somebody does NOT bring their old
-- sessions back: the tokens are gone from every browser that held them,
-- and un-revoking a row would describe a session nobody can use. They
-- sign in again, which is what actually happens.
-- =====================================================================

CREATE OR REPLACE FUNCTION hbh.trg_revoke_sessions_on_offboard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_reason text;
BEGIN
  -- Only on the CROSSING, not on every update of a suspended account.
  -- Without this test, editing a suspended person's mobile number would
  -- restamp revoked_at and move the moment their access ended - which is
  -- exactly the fact somebody will one day need to be accurate.
  IF (OLD.active_flg AND OLD.status = 'ACTIVE')
     AND NOT (NEW.active_flg AND NEW.status = 'ACTIVE') THEN

    -- Archived beats suspended when both change at once: an archived
    -- account is out of the list whatever its status column says.
    l_reason := CASE
                  WHEN NOT NEW.active_flg THEN 'USER_ARCHIVED'
                  ELSE 'USER_' || NEW.status
                END;

    UPDATE hbh.auth_sessions
       SET revoked_at     = now(),
           revoked_reason = l_reason
     WHERE user_id    = NEW.user_id
       -- Open ones only. A session revoked at logout an hour ago keeps
       -- the reason it was actually revoked for; overwriting it would
       -- rewrite history to match today's event.
       AND revoked_at IS NULL
       AND expires_at > now();
  END IF;

  RETURN NULL;  -- AFTER trigger; the return value is ignored.
END
$fn$;

COMMENT ON FUNCTION hbh.trg_revoke_sessions_on_offboard() IS
  'Marks a user''s open sessions revoked when their account stops being usable. The ACCESS was already ended by resolve_auth_session on the next request; this makes the record say so.';

DROP TRIGGER IF EXISTS trg_users_revoke_sessions ON hbh.users;
CREATE TRIGGER trg_users_revoke_sessions
AFTER UPDATE OF status, active_flg ON hbh.users
FOR EACH ROW
EXECUTE FUNCTION hbh.trg_revoke_sessions_on_offboard();

INSERT INTO hbh.schema_migrations (version) VALUES ('0105');
