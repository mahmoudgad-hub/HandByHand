-- =====================================================================
-- 0049 down - accept any icon key again, and fall back in silence
-- =====================================================================
\set ON_ERROR_STOP on
ALTER TABLE hbh.site_services DROP CONSTRAINT IF EXISTS ck_ssv_icon;
ALTER TABLE hbh.site_programs DROP CONSTRAINT IF EXISTS ck_sp_icon;
DELETE FROM hbh.schema_migrations WHERE version = '0049';
