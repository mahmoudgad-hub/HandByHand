-- =====================================================================
-- Hand By Hand (new) - migration 0017: the history triggers write as
-- the system, not as the caller
--
-- WHY. Migration 0016 gave hbh_app the right to move an appointment
-- along its state machine, and the UPDATE still failed - inside
-- hbh.trg_appointment_history, with a permission error on
-- hbh.appointment_status_history.
--
-- The cause: a trigger function runs as the CALLING user unless it is
-- SECURITY DEFINER, and hbh_app has no grant on the history tables -
-- correctly, because a history row is written BY THE SYSTEM and must
-- never be composed by a client.
--
-- It had never surfaced because every earlier path into these tables
-- went through a SECURITY DEFINER function - book_appointment,
-- start_session, close_session - and a trigger fired inside one of
-- those already runs as the owner. Migration 0016 opened the first
-- direct UPDATE, and the gap appeared immediately.
--
-- THE FIX, AND THE ONE REJECTED.
--
--   Rejected: GRANT INSERT on the history tables to hbh_app. It works,
--   and it also lets a client insert a history row that never happened
--   - a fabricated audit trail on an append-only table. The tables are
--   append-only precisely so that what they say is what occurred.
--
--   Taken: the trigger functions become SECURITY DEFINER, like
--   hbh.trg_audit already is. The history is written by the system with
--   the system's rights, the tables keep no grant at all, and a client
--   still cannot reach them by any route.
--
-- search_path is pinned on each one. A SECURITY DEFINER function with a
-- mutable search_path is a privilege escalation waiting to happen, and
-- these now run as the table owner.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0017') THEN
    RAISE EXCEPTION 'migration 0017 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0016') THEN
    RAISE EXCEPTION 'migration 0016 must be applied first';
  END IF;
END
$guard$;

-- Body unchanged from migration 0005. Only SECURITY DEFINER and the
-- pinned search_path are added.
CREATE OR REPLACE FUNCTION hbh.trg_appointment_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO hbh.appointment_status_history (center_id, appointment_id, from_status, to_status, note_ar)
    VALUES (NEW.center_id, NEW.appointment_id, NULL, NEW.status, NEW.note_ar);
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO hbh.appointment_status_history (center_id, appointment_id, from_status, to_status, reason)
    VALUES (NEW.center_id, NEW.appointment_id, OLD.status, NEW.status,
            CASE WHEN NEW.status = 'CANCELLED' THEN NEW.cancel_reason END);
  END IF;
  RETURN NEW;
END
$$;

-- The session history has the same shape and the same exposure the
-- moment anything updates hbh.therapy_sessions directly. Fixed now
-- rather than when it bites: the two tables are one mechanism, and
-- leaving half of it to be discovered later is how a pair drifts.
CREATE OR REPLACE FUNCTION hbh.trg_session_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO hbh.session_status_history (center_id, session_id, from_status, to_status)
    VALUES (NEW.center_id, NEW.session_id, NULL, NEW.status);
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO hbh.session_status_history (center_id, session_id, from_status, to_status, reason)
    VALUES (NEW.center_id, NEW.session_id, OLD.status, NEW.status, NEW.abort_reason);
  END IF;
  RETURN NEW;
END
$$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0017');
