-- =====================================================================
-- 0048 down - remove the certificate store
--
-- Triggers go with the table. The stamp function is dropped after,
-- because a function a trigger still references cannot be dropped and
-- the whole migration is one transaction.
--
-- WHAT THIS DESTROYS: every recorded consent and every recorded
-- redaction check. Those are statements made by named members of staff
-- about documents belonging to named colleagues, and re-creating them
-- means asking each person again. The files themselves live in
-- site/assets and are untouched - which is the wrong way round to be
-- comfortable about, so do not roll this back to "clean up": set
-- active_flg = false, or withdraw the rows to DRAFT, and the export
-- stops carrying them immediately.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS hbh.site_team_certificates;
DROP FUNCTION IF EXISTS hbh.trg_site_redaction_stamp();

DELETE FROM hbh.schema_migrations WHERE version = '0048';
