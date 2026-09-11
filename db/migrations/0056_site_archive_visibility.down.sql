-- Down for 0056. Dropping these puts archiving back in the state where
-- it answers 403 - see the up migration for why that is not obvious.
\set ON_ERROR_STOP on

DROP POLICY IF EXISTS p_site_contact_select_archived           ON hbh.site_contact;
DROP POLICY IF EXISTS p_site_faq_select_archived               ON hbh.site_faq;
DROP POLICY IF EXISTS p_site_services_select_archived          ON hbh.site_services;
DROP POLICY IF EXISTS p_site_programs_select_archived          ON hbh.site_programs;
DROP POLICY IF EXISTS p_site_team_select_archived              ON hbh.site_team;
DROP POLICY IF EXISTS p_site_team_facts_select_archived        ON hbh.site_team_facts;
DROP POLICY IF EXISTS p_site_team_certificates_select_archived ON hbh.site_team_certificates;
DROP POLICY IF EXISTS p_site_reviews_select_archived           ON hbh.site_reviews;
DROP POLICY IF EXISTS p_nps_select_archived                    ON hbh.nps_surveys;

DELETE FROM hbh.schema_migrations WHERE version = '0056';
