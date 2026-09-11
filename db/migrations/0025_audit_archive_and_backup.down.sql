-- =====================================================================
-- Hand By Hand (new) - migration 0025 DOWN. Development only.
--
-- Archived rows are moved BACK into audit_log before the archive is
-- dropped. Rolling a migration back must not be a way to lose a
-- clinical audit trail.
-- =====================================================================
ALTER TABLE hbh.audit_log DISABLE TRIGGER trg_audit_log_append_only;
INSERT INTO hbh.audit_log (audit_id, center_id, table_name, row_pk, action,
                           old_data, new_data, changed_by, changed_at, client_ip, detail)
OVERRIDING SYSTEM VALUE
SELECT audit_id, center_id, table_name, row_pk, action,
       old_data, new_data, changed_by, changed_at, client_ip, detail
FROM   hbh.audit_log_archive
ON CONFLICT (audit_id) DO NOTHING;
ALTER TABLE hbh.audit_log ENABLE TRIGGER trg_audit_log_append_only;

DROP VIEW     IF EXISTS hbh.v_backup_health;
DROP VIEW     IF EXISTS hbh.v_audit_trail;
DROP TABLE    IF EXISTS hbh.backup_runs;
DROP TABLE    IF EXISTS hbh.audit_log_archive;
DROP FUNCTION IF EXISTS hbh.record_backup(text, text, bigint, text, boolean, integer, bigint, boolean, text);
DROP FUNCTION IF EXISTS hbh.archive_audit(integer);
DELETE FROM hbh.convention_exemptions WHERE table_name IN ('audit_log_archive','backup_runs');
DELETE FROM hbh.sys_params WHERE param_code IN ('AUDIT_ARCHIVE_AFTER_DAYS','BACKUP_MAX_AGE_HOURS');
DELETE FROM hbh.schema_migrations WHERE version = '0025';
