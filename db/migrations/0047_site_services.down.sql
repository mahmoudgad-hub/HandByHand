-- =====================================================================
-- 0047 down - remove the site's service descriptions
--
-- Dropping the table takes its policies, indexes and triggers with it.
-- The catalogue rows in hbh.services are untouched: this table only ever
-- held text ABOUT them.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS hbh.site_services;

DELETE FROM hbh.schema_migrations WHERE version = '0047';
