-- =====================================================================
-- 0043 down - stop stamping consents
--
-- Triggers first, then the function they call. Reversing this returns
-- the tables to the state 0040 left them in: the consent constraint
-- still stands and nothing can fill it, so nothing can be published.
-- That is a wall rather than a hole, which is the safe direction, but it
-- is worth knowing before rolling back.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TRIGGER IF EXISTS trg_site_team_consent    ON hbh.site_team;
DROP TRIGGER IF EXISTS trg_site_reviews_consent ON hbh.site_reviews;

DROP FUNCTION IF EXISTS hbh.trg_site_consent_stamp();

DELETE FROM hbh.schema_migrations WHERE version = '0043';
