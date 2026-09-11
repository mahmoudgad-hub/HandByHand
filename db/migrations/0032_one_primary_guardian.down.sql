-- =====================================================================
-- Hand By Hand (new) - migration 0032 rollback
--
-- Dropping this lets a child have two primary guardians again. Nothing
-- in the code starts checking for that on its own: hbh.create_invoice
-- and the printed card go back to picking whichever guardian_id is
-- smaller, silently.
-- =====================================================================

DROP INDEX IF EXISTS hbh.uix_gc_one_primary;

DELETE FROM hbh.schema_migrations WHERE version = '0032';
