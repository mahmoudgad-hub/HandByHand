-- =====================================================================
-- 0044 - the six missing indexes on the site content foreign keys
--
-- WHAT THIS FIXES
-- 0040 created four site tables, each carrying a publisher and two of
-- them a consenter, and none of those six foreign keys got an index.
-- p00 refuses the whole schema for it - "every foreign key has a
-- supporting index" - and that check exists because an unindexed
-- foreign key makes the PARENT slow to delete or update: Postgres has
-- to scan the child table to find out whether any row still points at
-- the row being touched.
--
-- Here the parent is hbh.users. Archiving a member of staff who has
-- ever published a site entry would scan every one of these tables.
-- They are small today, which is exactly when this is cheap to fix.
--
-- WHY A NEW MIGRATION AND NOT AN EDIT TO 0040
-- 0040 is applied. Editing an applied migration changes nothing on any
-- database that already ran it, and leaves the two out of step - the
-- file says one thing and the schema is another. Forward, always.
--
-- IF NOT EXISTS, deliberately: another session is working in these
-- tables as this is written, and if they add the same indexes first
-- this migration must still apply rather than fail on a name clash.
-- =====================================================================

CREATE INDEX IF NOT EXISTS ix_sc_publisher ON hbh.site_contact (published_by);
CREATE INDEX IF NOT EXISTS ix_sf_publisher ON hbh.site_faq     (published_by);
CREATE INDEX IF NOT EXISTS ix_sr_publisher ON hbh.site_reviews (published_by);
CREATE INDEX IF NOT EXISTS ix_sr_consenter ON hbh.site_reviews (consent_obtained_by);
CREATE INDEX IF NOT EXISTS ix_st_publisher ON hbh.site_team    (published_by);
CREATE INDEX IF NOT EXISTS ix_st_consenter ON hbh.site_team    (consent_obtained_by);

INSERT INTO hbh.schema_migrations (version) VALUES ('0044');
