-- =====================================================================
-- Hand By Hand (new) - migration 0014: auditing what 0012 made writable
--
-- WHY. Migration 0012 opened nine tables for writing that had no change
-- audit on them. That was harmless while they were read-only - nothing
-- changed, so there was nothing to record - and it stopped being
-- harmless the moment the operations app could edit them.
--
-- Without this, an administrator could change a price, retire a
-- service, move a therapist's hours, or REPOINT A CAMERA, and the only
-- trace would be updated_by on the row itself: the current value, not
-- the change, and gone the next time somebody edits it.
--
-- The camera is the one that decides the matter. cameras.gateway_path
-- says which room the portal shows a family. Changing it is the single
-- most consequential edit in the operations app, and until now it left
-- no record of what it used to be.
--
-- Found by the phase-4 acceptance suite, which asked the database for
-- an INSERT record after creating a service through the API and did not
-- get one.
--
-- These are ordinary change records - hbh.trg_audit, inside the
-- transaction - so a rolled back edit takes its record with it. That is
-- correct for a change: it did not happen. Attempt records are the
-- other kind and are written by the API (D-1).
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0014') THEN
    RAISE EXCEPTION 'migration 0014 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0013') THEN
    RAISE EXCEPTION 'migration 0013 must be applied first';
  END IF;
END
$guard$;

CREATE TRIGGER trg_services_audit          AFTER INSERT OR UPDATE OR DELETE ON hbh.services
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('service_id');

CREATE TRIGGER trg_rooms_audit             AFTER INSERT OR UPDATE OR DELETE ON hbh.rooms
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('room_id');

CREATE TRIGGER trg_activity_library_audit  AFTER INSERT OR UPDATE OR DELETE ON hbh.activity_library
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('activity_id');

CREATE TRIGGER trg_service_packages_audit  AFTER INSERT OR UPDATE OR DELETE ON hbh.service_packages
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('package_id');

CREATE TRIGGER trg_therapists_audit        AFTER INSERT OR UPDATE OR DELETE ON hbh.therapists
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('therapist_id');

CREATE TRIGGER trg_therapist_hours_audit   AFTER INSERT OR UPDATE OR DELETE ON hbh.therapist_working_hours
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('working_hour_id');

-- therapist_services has a composite key. trg_audit records ONE column
-- as row_pk, so it records the therapist - which is the useful half:
-- "this therapist's services changed" is the question anybody asks. The
-- full before and after are in old_data and new_data regardless.
CREATE TRIGGER trg_therapist_services_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.therapist_services
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('therapist_id');

CREATE TRIGGER trg_measurements_audit      AFTER INSERT OR UPDATE OR DELETE ON hbh.goal_measurements
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('measurement_id');

-- The family's own reports of a home exercise. A correction to one is a
-- change to a clinical record like any other.
CREATE TRIGGER trg_activity_log_audit      AFTER INSERT OR UPDATE OR DELETE ON hbh.activity_log
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('log_id');

-- Cameras were audited by nothing until now, and gateway_path is the
-- most consequential column in the operations app.
CREATE TRIGGER trg_cameras_audit           AFTER INSERT OR UPDATE OR DELETE ON hbh.cameras
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('camera_id');

INSERT INTO hbh.schema_migrations (version) VALUES ('0014');
