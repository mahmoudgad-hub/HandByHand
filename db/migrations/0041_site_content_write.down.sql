-- =====================================================================
-- 0041 down - take back the write access, keep the rows
--
-- Policies go with the tables they are on, so they are dropped by name
-- rather than by dropping anything. The triggers go before the functions
-- they call: a function a trigger still references cannot be dropped,
-- and the whole migration is one transaction, so that failure would roll
-- back every statement here and leave the state looking untouched.
--
-- The tables and every row in them survive. Reversing this migration
-- makes the content read-only, which is a smaller thing than 0040 down.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TRIGGER IF EXISTS trg_site_sections_publish ON hbh.site_sections;
DROP TRIGGER IF EXISTS trg_site_contact_publish  ON hbh.site_contact;
DROP TRIGGER IF EXISTS trg_site_faq_publish      ON hbh.site_faq;
DROP TRIGGER IF EXISTS trg_site_team_publish     ON hbh.site_team;
DROP TRIGGER IF EXISTS trg_site_reviews_publish  ON hbh.site_reviews;

DROP FUNCTION IF EXISTS hbh.trg_site_section_guard();
DROP FUNCTION IF EXISTS hbh.trg_site_publish_guard();

DROP POLICY IF EXISTS p_site_sections_update ON hbh.site_sections;
DROP POLICY IF EXISTS p_site_contact_insert  ON hbh.site_contact;
DROP POLICY IF EXISTS p_site_contact_update  ON hbh.site_contact;
DROP POLICY IF EXISTS p_site_faq_insert      ON hbh.site_faq;
DROP POLICY IF EXISTS p_site_faq_update      ON hbh.site_faq;
DROP POLICY IF EXISTS p_site_team_insert     ON hbh.site_team;
DROP POLICY IF EXISTS p_site_team_update     ON hbh.site_team;
DROP POLICY IF EXISTS p_site_reviews_insert  ON hbh.site_reviews;
DROP POLICY IF EXISTS p_site_reviews_update  ON hbh.site_reviews;

REVOKE INSERT, UPDATE ON hbh.site_contact, hbh.site_faq,
                         hbh.site_team, hbh.site_reviews FROM hbh_app;
REVOKE UPDATE ON hbh.site_sections FROM hbh_app;

DELETE FROM hbh.schema_migrations WHERE version = '0041';
