-- =====================================================================
-- 0054 - the eight foreign keys 0047..0050 left without an index
--
-- Same defect as 0044, in the tables added since it: p00 refuses the
-- schema for "every foreign key has a supporting index", and it is
-- right to. An unindexed foreign key makes the PARENT expensive to
-- delete or update, because Postgres has to scan the child table to
-- learn whether any row still points at the row being touched.
--
-- The parents here are hbh.users and hbh.centers. Archiving a member of
-- staff who has ever published or vetted a page of the public site
-- would scan all four of these tables, and centre_id is on the path of
-- anything that ever touches a centre row.
--
--   site_programs.published_by             users
--   site_reviews.text_reviewed_by          users
--   site_services.published_by             users
--   site_team_certificates.center_id       centers
--   site_team_certificates.redaction_checked_by  users
--   site_team_certificates.consent_obtained_by   users
--   site_team_certificates.published_by    users
--   site_team_facts.center_id              centers
--
-- FORWARD, NOT AN EDIT. 0047..0050 are applied; changing an applied
-- migration alters nothing on a database that already ran it and leaves
-- the file and the schema saying different things.
--
-- IF NOT EXISTS, deliberately: these tables belong to work another
-- session is still in the middle of. If they add the same indexes
-- first, this must still apply rather than fail on a name clash.
-- =====================================================================

CREATE INDEX IF NOT EXISTS ix_sp_publisher  ON hbh.site_programs (published_by);
CREATE INDEX IF NOT EXISTS ix_sr_text_rev   ON hbh.site_reviews (text_reviewed_by);
CREATE INDEX IF NOT EXISTS ix_ssv_publisher ON hbh.site_services (published_by);
CREATE INDEX IF NOT EXISTS ix_stc_center    ON hbh.site_team_certificates (center_id);
CREATE INDEX IF NOT EXISTS ix_stc_checker   ON hbh.site_team_certificates (redaction_checked_by);
CREATE INDEX IF NOT EXISTS ix_stc_consenter ON hbh.site_team_certificates (consent_obtained_by);
CREATE INDEX IF NOT EXISTS ix_stc_publisher ON hbh.site_team_certificates (published_by);
CREATE INDEX IF NOT EXISTS ix_stf_center    ON hbh.site_team_facts (center_id);

INSERT INTO hbh.schema_migrations (version) VALUES ('0054');
