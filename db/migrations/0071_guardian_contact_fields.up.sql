-- =====================================================================
-- 0071 - contact details on a guardian record
--
-- The DDL below is unchanged from how this migration was written. Three
-- things around it were repaired after the acceptance suites found the
-- file recorded nowhere:
--
-- 1. IT NOW REGISTERS ITSELF. Every migration in this project ends by
--    inserting its version into hbh.schema_migrations, and this one did
--    not - so scripts/db.sh re-applied it on every run and the ledger
--    said seventy-one files had produced seventy entries. Nothing broke
--    yet only because ADD COLUMN IF NOT EXISTS is harmless twice; the
--    first non-idempotent line added here would have failed for a
--    reason nothing on screen would explain. Same family as the
--    duplicate-number lesson in CLAUDE.md: a migration that goes
--    missing in silence.
--
-- 2. THE EXPLICIT BEGIN/COMMIT IS GONE. scripts/db.sh already runs each
--    file with --single-transaction, so these opened a transaction
--    inside a transaction - a warning today, and a file that cannot be
--    rolled back as a unit the day it grows a second statement.
--
-- STILL OPEN, AND NOT MINE TO SETTLE: guardians.relationship is free
-- text, while guardian_children.relationship_code already carries the
-- same meaning bound to a lookup table. Two columns for one idea in two
-- tables will drift, and the free-text one will be the one that drifts.
-- Raised with the owner rather than changed here.
-- =====================================================================

\set ON_ERROR_STOP on

ALTER TABLE hbh.guardians
  ADD COLUMN IF NOT EXISTS email text,
  ADD COLUMN IF NOT EXISTS city text,
  ADD COLUMN IF NOT EXISTS relationship text;

INSERT INTO hbh.schema_migrations (version) VALUES ('0071')
ON CONFLICT DO NOTHING;
