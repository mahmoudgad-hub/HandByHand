-- =====================================================================
-- Hand By Hand (new) - migration 0034 rollback
--
-- Dropping these puts the schema back in the state the conventions
-- suite refuses. That is the point of the check, and this rollback is
-- only meaningful alongside rolling back 0033.
-- =====================================================================

DROP INDEX IF EXISTS hbh.ix_th_consent_by;
DROP INDEX IF EXISTS hbh.ix_th_published_by;

DELETE FROM hbh.schema_migrations WHERE version = '0034';
