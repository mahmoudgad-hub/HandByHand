-- =====================================================================
-- Hand By Hand (new) - migration 0106: the twelfth section.
--
-- NUMBER RESERVED BEFORE WRITING, checked against both the filesystem
-- and hbh.schema_migrations: the highest on disk and the highest applied
-- were both 0105. This tree has no version control, so a collision is
-- not recoverable.
--
-- ---------------------------------------------------------------------
-- WHY
--
-- hbh.site_sections is the one place that decides whether a block of the
-- public page is shown, and ck_ss_code lists the eleven codes it will
-- accept. The page has a twelfth block - the call-to-action band,
-- <section id="cta"> - and it was never in that list.
--
-- So when the owner asked for it to go away on 2026-09-10 the only way
-- to do it was the `hidden` attribute in site/index.html. That decision
-- now lives in a file on the web host rather than in a row, which means
-- it is invisible to the console, unauditable, and undone by anybody who
-- redeploys the site from a checkout that predates it.
--
-- The section-visibility screen makes every OTHER section a row that a
-- centre admin can flip. This adds the twelfth so the screen is not
-- lying by omission about the one section that is actually off.
--
-- ---------------------------------------------------------------------
-- WHY THE ROW IS INSERTED false
--
-- Because that is the state the owner asked for, and a migration is not
-- a place to quietly re-publish content somebody removed. site/app.js
-- reads the map and sets `section.hidden = (map[code] === false)`, so a
-- row of true would have UNHIDDEN the band the moment the next export
-- ran - a migration turning marketing copy back on by itself.
--
-- The `hidden` attribute STAYS in index.html, deliberately. It is the
-- authored fallback for a page opened with no content.js at all, and for
-- this one section the owner's answer is "off". Every other section is
-- authored visible and can only be hidden by a row; this one is authored
-- hidden and can only be shown by a row. Both directions still end at
-- the same place: the row wins whenever there is one.
--
-- ---------------------------------------------------------------------
-- NOT A PUBLISH
--
-- trg_site_sections_publish is BEFORE UPDATE and gates visible_flg on
-- SITE.PUBLISH. This is an INSERT by the owner during migration, so the
-- trigger does not fire - which is correct and is not a hole: hbh_app
-- has no INSERT grant on this table at all (0041), so no request can
-- reach this path. Rows here are created by schema, never by a client.
-- =====================================================================

ALTER TABLE hbh.site_sections DROP CONSTRAINT ck_ss_code;
ALTER TABLE hbh.site_sections ADD CONSTRAINT ck_ss_code CHECK (
  code IN ('home', 'services', 'programs', 'how', 'why', 'live',
           'portal', 'team', 'reviews', 'cta', 'contact', 'faq'));

-- One row per centre that already has sections, and only there. A centre
-- with no section rows is a centre whose site was never set up; giving
-- it one orphan row would make the new screen show a single line and
-- nothing else.
INSERT INTO hbh.site_sections (center_id, code, visible_flg, created_by)
SELECT DISTINCT s.center_id, 'cta', false, 'migration-0106'
FROM hbh.site_sections s
WHERE NOT EXISTS (
  SELECT 1 FROM hbh.site_sections x
  WHERE x.center_id = s.center_id AND x.code = 'cta');

INSERT INTO hbh.schema_migrations (version) VALUES ('0106');
