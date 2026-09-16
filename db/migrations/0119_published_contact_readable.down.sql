-- Reverses 0119. Dropping this policy leaves p_site_contact_select in
-- place, so editors keep their access and families lose theirs.
DROP POLICY IF EXISTS p_site_contact_read_published ON hbh.site_contact;

DELETE FROM hbh.schema_migrations WHERE version = '0119';
