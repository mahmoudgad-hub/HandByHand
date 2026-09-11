-- =====================================================================
-- Hand By Hand (new) - migration 0082: family messages leave a trail
--
-- CAUGHT BY AN INVARIANT, not by review. The phase-4 acceptance suite
-- asserts that EVERY table hbh_app may write has a change audit, rather
-- than checking a list somebody remembered to keep. It went red on the
-- first run after 0079 and 0080:
--
--   audit | every writable table has a change audit
--         | offenders: family_message_reads, family_messages
--
-- Migration 0081 gave both tables their audit COLUMNS - created_by,
-- updated_by and the rest - which is a different thing from a change
-- audit. The columns say who last touched the row; the trigger says
-- what the row used to be.
--
-- WHY A TRIGGER AND NOT AN EXEMPTION.
--
-- There is a real argument for exempting hbh.family_messages: it holds
-- INSERT and SELECT and no UPDATE, so it is append-only in practice, and
-- hbh.trg_audit copies the whole row - body_ar included - into
-- hbh.audit_log, which is never purged and is read by more people than
-- the message itself. That is the reasoning that gave hbh.attachments a
-- recorder of its own.
--
-- The argument does not survive looking at what this schema already
-- does. hbh.session_notes and hbh.progress_reports both carry trg_audit,
-- bodies and all, and both are clinical free text about a child. A
-- message between the centre and a family is the same class of content
-- and the same question - who wrote this, and has it changed since. The
-- schema answered this before it was asked; the only new thing here is
-- noticing.
--
-- AND WHAT MIGRATION 0081 LEFT OPEN STAYS OPEN. Soft delete on these
-- tables waits on BL-21 - whether a message sent in error can be
-- withdrawn at all. This migration does not touch that question. It is
-- worth saying that the two answers interact: if BL-21 chooses soft
-- withdrawal, the UPDATE that hides a message is precisely the change
-- this trigger now records.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0082') THEN
    RAISE EXCEPTION 'migration 0082 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0080') THEN
    RAISE EXCEPTION 'migration 0080 must be applied first';
  END IF;
END
$guard$;

DROP TRIGGER IF EXISTS trg_family_messages_audit ON hbh.family_messages;
CREATE TRIGGER trg_family_messages_audit
  AFTER INSERT OR UPDATE OR DELETE ON hbh.family_messages
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit();

DROP TRIGGER IF EXISTS trg_family_message_reads_audit ON hbh.family_message_reads;
CREATE TRIGGER trg_family_message_reads_audit
  AFTER INSERT OR UPDATE OR DELETE ON hbh.family_message_reads
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit();

-- The invariant, asserted at apply time as well as in the suite. A
-- migration that opens a table for writing and forgets the trail should
-- fail as it is applied, not hours later in somebody else's run.
--
-- It honours hbh.convention_exemptions, because that is where a decision
-- to skip a rule belongs - written down, with a reason, next to every
-- other such decision. A rule whose exceptions live inside its own test
-- is a rule each phase quietly edits.
DO $verify$
DECLARE l_missing text;
BEGIN
  SELECT string_agg(g.table_name, ', ')
  INTO   l_missing
  FROM  (SELECT DISTINCT table_name FROM information_schema.role_table_grants
          WHERE grantee = 'hbh_app' AND table_schema = 'hbh'
          AND   privilege_type IN ('INSERT','UPDATE')
          AND   table_name <> 'audit_log') g
  WHERE NOT EXISTS (
          SELECT 1 FROM pg_trigger t
          JOIN   pg_class c     ON c.oid = t.tgrelid
          JOIN   pg_namespace n ON n.oid = c.relnamespace
          JOIN   pg_proc p      ON p.oid = t.tgfoid
          WHERE  n.nspname = 'hbh' AND c.relname = g.table_name
          AND    NOT t.tgisinternal
          AND    p.prosrc LIKE '%hbh.audit_log%')
  AND NOT EXISTS (
          SELECT 1 FROM hbh.convention_exemptions e
          WHERE  e.table_name = g.table_name AND e.rule_code = 'CHANGE_AUDIT');

  IF l_missing IS NOT NULL THEN
    RAISE EXCEPTION 'writable table(s) with no change audit and no CHANGE_AUDIT exemption: %', l_missing;
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0082');
