-- =====================================================================
-- 0054 down - drop the eight site foreign key indexes.
--
-- A database reverted to here fails its own conventions suite on the
-- next run. That is correct: the check is the reason these exist.
-- =====================================================================

DROP INDEX IF EXISTS hbh.ix_sp_publisher;
DROP INDEX IF EXISTS hbh.ix_sr_text_rev;
DROP INDEX IF EXISTS hbh.ix_ssv_publisher;
DROP INDEX IF EXISTS hbh.ix_stc_center;
DROP INDEX IF EXISTS hbh.ix_stc_checker;
DROP INDEX IF EXISTS hbh.ix_stc_consenter;
DROP INDEX IF EXISTS hbh.ix_stc_publisher;
DROP INDEX IF EXISTS hbh.ix_stf_center;

DELETE FROM hbh.schema_migrations WHERE version = '0054';
