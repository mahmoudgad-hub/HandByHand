-- Hand By Hand (new) - migration 0084 DOWN. Development only.
-- Restores the read policy from 0079 (no active_flg clause) BEFORE the
-- column it references is dropped.
DROP POLICY IF EXISTS family_messages_read ON hbh.family_messages;
CREATE POLICY family_messages_read ON hbh.family_messages
  FOR SELECT TO hbh_app
  USING (
    center_id = hbh.current_center_id()
    AND EXISTS (
      SELECT 1 FROM hbh.guardians g
      WHERE g.guardian_id = family_messages.guardian_id
        AND g.center_id   = family_messages.center_id
        AND g.active_flg
        AND (hbh.has_permission('REQUEST.MANAGE') OR g.user_id = hbh.current_user_id())));

ALTER TABLE hbh.family_messages DROP CONSTRAINT IF EXISTS ck_family_messages_deleted;
ALTER TABLE hbh.family_messages
  DROP COLUMN IF EXISTS deleted_at,
  DROP COLUMN IF EXISTS active_flg;

DELETE FROM hbh.convention_exemptions
 WHERE table_name = 'family_message_reads' AND rule_code = 'SOFT_DELETE';
DELETE FROM hbh.schema_migrations WHERE version = '0084';
