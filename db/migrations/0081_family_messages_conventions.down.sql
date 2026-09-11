-- Hand By Hand (new) - migration 0081 DOWN. Development only.
DROP TRIGGER IF EXISTS trg_family_messages_touch ON hbh.family_messages;
DROP TRIGGER IF EXISTS trg_family_reads_touch    ON hbh.family_message_reads;
DROP INDEX IF EXISTS hbh.ix_family_message_reads_message;
DROP INDEX IF EXISTS hbh.ix_family_message_reads_guardian;
DROP INDEX IF EXISTS hbh.ix_family_messages_guardian;
ALTER TABLE hbh.family_message_reads
  DROP COLUMN IF EXISTS updated_by, DROP COLUMN IF EXISTS updated_at,
  DROP COLUMN IF EXISTS created_by, DROP COLUMN IF EXISTS created_at;
ALTER TABLE hbh.family_messages
  DROP COLUMN IF EXISTS updated_by, DROP COLUMN IF EXISTS updated_at,
  DROP COLUMN IF EXISTS created_by;
DELETE FROM hbh.schema_migrations WHERE version = '0081';
