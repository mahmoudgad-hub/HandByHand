-- =====================================================================
-- 0040 down - remove the site's content tables
--
-- Dropping a table takes its policies, indexes and triggers with it, so
-- the order here is only about foreign keys - and there are none between
-- these five, so any order works. They are listed in the order they were
-- created for readability rather than necessity.
--
-- WHAT THIS DESTROYS. Every consent record for a published photograph or
-- testimonial. If the tables are ever rolled back after real consents
-- have been taken, those consents are gone and each one has to be asked
-- for again - which is a conversation with a family, not a data loss.
-- To stop the site showing a section without losing that, hide the
-- section instead:
--
--   UPDATE hbh.site_sections SET visible_flg = false WHERE code = 'REVIEWS';
--
-- The permission rows live in db/seed/0002_rbac.sql and are not removed
-- here: a permission nobody holds is inert, and the seed is re-run on
-- every rebuild.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS hbh.site_reviews;
DROP TABLE IF EXISTS hbh.site_team;
DROP TABLE IF EXISTS hbh.site_faq;
DROP TABLE IF EXISTS hbh.site_contact;
DROP TABLE IF EXISTS hbh.site_sections;

DELETE FROM hbh.schema_migrations WHERE version = '0040';
