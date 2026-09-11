-- Reverses 0106. The rows go first: narrowing ck_ss_code while a 'cta'
-- row exists fails the constraint check, and the whole migration is one
-- transaction, so nothing would be reversed at all.
--
-- This is a HARD delete, and it is the one shape where that is right: the
-- rows did not exist before this migration and carry no history of their
-- own. Their audit lines stay in hbh.audit_log regardless.
DELETE FROM hbh.site_sections WHERE code = 'cta';

ALTER TABLE hbh.site_sections DROP CONSTRAINT ck_ss_code;
ALTER TABLE hbh.site_sections ADD CONSTRAINT ck_ss_code CHECK (
  code IN ('home', 'services', 'programs', 'how', 'why', 'live',
           'portal', 'team', 'reviews', 'contact', 'faq'));

DELETE FROM hbh.schema_migrations WHERE version = '0106';
