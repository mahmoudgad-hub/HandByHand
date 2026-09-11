-- =====================================================================
-- Hand By Hand (new) - migration 0003 DOWN
-- Tables before functions - see the note in 0002's down migration.
-- =====================================================================

DROP TABLE IF EXISTS hbh.convention_exemptions;

DELETE FROM hbh.schema_migrations WHERE version = '0003';
