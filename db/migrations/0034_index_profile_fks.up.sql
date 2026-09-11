-- =====================================================================
-- Hand By Hand (new) - migration 0034: index the two keys 0033 added
--
-- CAUGHT BY THE CONVENTIONS SUITE, not by review:
--
--   index | every foreign key has a supporting index
--         | offenders: therapists.therapists_consent_by_fkey,
--         |            therapists.therapists_published_by_fkey
--
-- That check lives in tests/db/p00_verify.sql precisely so a new table
-- cannot quietly skip a rule the rest of the schema follows, and it
-- went red on the first run after 0033. It is doing its job.
--
-- WHY INDEXES AND NOT AN EXEMPTION. There is an argument for exempting
-- these: hbh.users is never hard-deleted - rule 3, no DELETE grant
-- anywhere - so the usual cost of an unindexed foreign key, a
-- sequential scan of the child on every parent delete, cannot arise.
--
-- It was not taken, for two reasons. The columns answer a real question
-- - "which profiles did this administrator publish", "whose consent did
-- we record" - and that is an audit query somebody will run the week
-- something is disputed. And an invariant with one exemption in it is a
-- weaker instrument than one with none: the next person to hit it
-- argues from this precedent rather than from the rule.
--
-- Two small indexes are cheaper than either.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0034') THEN
    RAISE EXCEPTION 'migration 0034 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0033') THEN
    RAISE EXCEPTION 'migration 0033 must be applied first';
  END IF;
END
$guard$;

-- Partial: the overwhelming majority of rows have neither set, and an
-- index over a column that is NULL for most of the table is mostly
-- storage. WHERE ... IS NOT NULL indexes what exists.
CREATE INDEX ix_th_published_by ON hbh.therapists (published_by)
  WHERE published_by IS NOT NULL;

CREATE INDEX ix_th_consent_by ON hbh.therapists (consent_by)
  WHERE consent_by IS NOT NULL;

-- The invariant itself, asserted here rather than left to the next test
-- run. A migration that reintroduces the gap should fail as it is
-- applied, not hours later in somebody else's suite.
DO $verify$
DECLARE l_missing text;
BEGIN
  SELECT string_agg(c.conrelid::regclass::text || '.' || c.conname, ', ')
  INTO   l_missing
  FROM   pg_constraint c
  JOIN   pg_class t ON t.oid = c.conrelid
  JOIN   pg_namespace n ON n.oid = t.relnamespace
  WHERE  n.nspname = 'hbh' AND c.contype = 'f'
  AND    NOT EXISTS (
           SELECT 1 FROM pg_index i
           WHERE i.indrelid = c.conrelid
           AND   (i.indkey::smallint[])[0:array_length(c.conkey, 1) - 1] @> c.conkey);

  IF l_missing IS NOT NULL THEN
    RAISE EXCEPTION 'foreign key(s) with no supporting index: %', l_missing;
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0034');
