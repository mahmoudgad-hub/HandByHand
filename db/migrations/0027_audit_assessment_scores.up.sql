-- =====================================================================
-- Hand By Hand (new) - migration 0027: an assessment score leaves a trail
--
-- FOUND BY AN INVARIANT, not by a review. The phase-4 acceptance suite
-- asserts that EVERY table hbh_app may write has a change audit, rather
-- than checking a list of tables somebody remembered to write down.
-- Migration 0023 opened hbh.assessment_item_scores for writing and the
-- check went red on the next run.
--
-- WHY IT MATTERS HERE. A score on an assessment item is a clinical
-- judgement about a child, and it is the kind of number that gets
-- revised: a therapist re-scores an item, a supervisor disagrees, a
-- total moves. Without an audit row the table holds only the CURRENT
-- answer, and the question "who changed this, and from what" has no
-- answer at all - which is exactly the question asked when a report
-- built on those scores is challenged.
--
-- hbh.trg_audit is the standard recorder and is already SECURITY
-- DEFINER with a pinned search_path, so the table needs no grant on
-- hbh.audit_log - and a client still cannot compose an audit row.
--
-- hbh.attachments is deliberately NOT touched. It carries its own
-- recorder, hbh.trg_attachment_audit, which does the same job while
-- stripping the file content out of the record - a generic to_jsonb(NEW)
-- would copy an entire uploaded file into the audit log on every write.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0027') THEN
    RAISE EXCEPTION 'migration 0027 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0023') THEN
    RAISE EXCEPTION 'migration 0023 must be applied first';
  END IF;
END
$guard$;

DROP TRIGGER IF EXISTS trg_ascore_audit ON hbh.assessment_item_scores;
CREATE TRIGGER trg_ascore_audit
  AFTER INSERT OR UPDATE OR DELETE ON hbh.assessment_item_scores
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit();

-- The invariant the suite asserts, asserted here as well: a migration
-- that opens a table for writing and forgets the trail should fail at
-- apply time, not on somebody's next test run.
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
    AND    p.prosrc LIKE '%hbh.audit_log%');

  IF l_missing IS NOT NULL THEN
    RAISE EXCEPTION 'writable table(s) with no change audit: %', l_missing;
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0027');
