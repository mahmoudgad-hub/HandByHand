-- =====================================================================
-- Hand By Hand (new) - migration 0081: the two family-message tables
-- join the schema's conventions
--
-- p00 went red on three counts across hbh.family_messages and
-- hbh.family_message_reads: the four audit columns, soft delete, and an
-- index behind every foreign key. This migration fixes TWO of the
-- three, on purpose.
--
-- WHAT THIS DOES NOT DO, AND WHY
--
-- Soft delete is left alone. It is not an oversight and not a bug: it
-- is a business decision sitting with the owner as BL-21 - whether a
-- message sent to a family in error can be withdrawn at all, or is
-- corrected by a following message the way a clinical note is. Writing
-- the columns now would answer that question in SQL before the owner
-- answers it in words, and "final" may well be the intended reading.
-- p00 therefore stays red on exactly one check until BL-21 is decided.
--
-- AND WHY COLUMNS RATHER THAN AN EXEMPTION
--
-- hbh.family_messages holds no UPDATE grant today, so updated_at and
-- updated_by look decorative, and the append-only tables in this schema
-- (audit_log, consent_events, package_ledger) all took an AUDIT_COLUMNS
-- exemption instead. The difference is that an exemption is a decision
-- - it says the rule does not apply here, permanently - and one of the
-- three BL-21 outcomes (soft withdrawal) makes withdrawing an UPDATE
-- that very much wants to record who did it. Columns are additive and
-- correct under all three outcomes; an exemption is correct under only
-- two. So: columns.
--
-- AND ONE THING THE CONVENTION FIXED THAT WAS A REAL GAP
--
-- family_message_reads is a read WATERMARK - primary key
-- (user_id, guardian_id), message_id being how far that user has read
-- in that thread - and it recorded no time at all. "Has this family
-- seen it yet" had an answer; "since when" had none. updated_at is that
-- answer, and trg_touch keeps it true rather than decorative.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0081') THEN
    RAISE EXCEPTION 'migration 0081 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0080') THEN
    RAISE EXCEPTION 'migration 0080 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- AUDIT COLUMNS
-- =====================================================================
ALTER TABLE hbh.family_messages
  ADD COLUMN created_by text NOT NULL DEFAULT hbh.current_app_user(),
  ADD COLUMN updated_at timestamptz,
  ADD COLUMN updated_by text;

-- All four here: the table had none, not even created_at.
ALTER TABLE hbh.family_message_reads
  ADD COLUMN created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN created_by text NOT NULL DEFAULT hbh.current_app_user(),
  ADD COLUMN updated_at timestamptz,
  ADD COLUMN updated_by text;

-- A column that never moves is a lie told by a schema. The watermark is
-- updated in place, so this trigger is what makes updated_at mean
-- "last read at" instead of "always null".
CREATE TRIGGER trg_family_reads_touch
  BEFORE UPDATE ON hbh.family_message_reads
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

-- family_messages holds no UPDATE grant, so nothing routine will fire
-- this. It exists so that the day an UPDATE path is opened - BL-21's
-- withdrawal option is exactly that - the row records who moved it
-- without anybody having to remember to add this.
CREATE TRIGGER trg_family_messages_touch
  BEFORE UPDATE ON hbh.family_messages
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

-- =====================================================================
-- AN INDEX BEHIND EVERY FOREIGN KEY
--
-- ix_family_messages_thread is (center_id, guardian_id, message_id DESC)
-- and does NOT serve guardian_id: centre leads, so a lookup by guardian
-- alone cannot use it. Same story on the reads table, where the primary
-- key (user_id, guardian_id) serves user_id and nothing else.
-- =====================================================================
CREATE INDEX ix_family_messages_guardian     ON hbh.family_messages (guardian_id);
CREATE INDEX ix_family_message_reads_guardian ON hbh.family_message_reads (guardian_id);
CREATE INDEX ix_family_message_reads_message  ON hbh.family_message_reads (message_id);

INSERT INTO hbh.schema_migrations (version) VALUES ('0081');
