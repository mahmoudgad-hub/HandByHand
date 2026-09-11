-- =====================================================================
-- 0044 down - drop the six site-content foreign key indexes.
--
-- Reverting puts the schema back in the state p00 refuses, so a database
-- reverted to here fails its own conventions suite on the next run. That
-- is correct: the check is the reason these exist.
-- =====================================================================

DROP INDEX IF EXISTS hbh.ix_sc_publisher;
DROP INDEX IF EXISTS hbh.ix_sf_publisher;
DROP INDEX IF EXISTS hbh.ix_sr_publisher;
DROP INDEX IF EXISTS hbh.ix_sr_consenter;
DROP INDEX IF EXISTS hbh.ix_st_publisher;
DROP INDEX IF EXISTS hbh.ix_st_consenter;

DELETE FROM hbh.schema_migrations WHERE version = '0044';
