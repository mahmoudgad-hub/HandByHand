-- =====================================================================
-- 0042 down - stop stamping the publisher
--
-- Triggers before the function they call: a function a trigger still
-- references cannot be dropped, and one failed statement rolls back the
-- whole migration and leaves everything looking untouched.
--
-- Reversing this makes the rows unpublishable again rather than
-- unprotected: ck_*_published still demands published_at and
-- published_by, and after this nothing fills them in.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TRIGGER IF EXISTS trg_site_contact_stamp ON hbh.site_contact;
DROP TRIGGER IF EXISTS trg_site_faq_stamp     ON hbh.site_faq;
DROP TRIGGER IF EXISTS trg_site_team_stamp    ON hbh.site_team;
DROP TRIGGER IF EXISTS trg_site_reviews_stamp ON hbh.site_reviews;

DROP FUNCTION IF EXISTS hbh.trg_site_publish_stamp();

DELETE FROM hbh.schema_migrations WHERE version = '0042';
