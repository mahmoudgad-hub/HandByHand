-- =====================================================================
-- Hand By Hand (new) - migration 0082 rollback
--
-- The audit rows already written stay. A record of a change describes
-- something that happened, and removing the recorder is not a reason to
-- deny it.
--
-- Rolling this back puts the schema back in the state the phase-4
-- invariant refuses. That is the point of the check.
-- =====================================================================

DROP TRIGGER IF EXISTS trg_family_message_reads_audit ON hbh.family_message_reads;
DROP TRIGGER IF EXISTS trg_family_messages_audit ON hbh.family_messages;

DELETE FROM hbh.schema_migrations WHERE version = '0082';
