-- =====================================================================
-- Hand By Hand (new) - migration 0014 DOWN
--
-- Development convenience only. Dropping these leaves the tables from
-- 0012 writable and unaudited - see the note in the up migration.
-- =====================================================================

DROP TRIGGER IF EXISTS trg_services_audit           ON hbh.services;
DROP TRIGGER IF EXISTS trg_rooms_audit              ON hbh.rooms;
DROP TRIGGER IF EXISTS trg_activity_library_audit   ON hbh.activity_library;
DROP TRIGGER IF EXISTS trg_service_packages_audit   ON hbh.service_packages;
DROP TRIGGER IF EXISTS trg_therapists_audit         ON hbh.therapists;
DROP TRIGGER IF EXISTS trg_therapist_hours_audit    ON hbh.therapist_working_hours;
DROP TRIGGER IF EXISTS trg_therapist_services_audit ON hbh.therapist_services;
DROP TRIGGER IF EXISTS trg_measurements_audit       ON hbh.goal_measurements;
DROP TRIGGER IF EXISTS trg_activity_log_audit       ON hbh.activity_log;
DROP TRIGGER IF EXISTS trg_cameras_audit            ON hbh.cameras;

DELETE FROM hbh.schema_migrations WHERE version = '0014';
