-- =====================================================================
-- 0049 - icon_key is a closed vocabulary, not free text
--
-- The eight service icons are inline SVG in site/index.html. icon_key
-- CHOOSES one of them; it does not carry one. The accepted values are
-- i1..i8, and anything else falls back to the icon for that POSITION -
-- silently, with the card still rendering and nothing anywhere saying
-- the key was wrong.
--
-- 0047 left the column free text and its comment guessed at values like
-- "ic-music", which are not among them. A row written that way would
-- have looked correct in the console and drawn the wrong picture on the
-- page, and the only way to notice is to compare the two by eye.
--
-- A refusal is better than a silent fallback. That is the whole of this
-- migration.
--
-- IT WILL NEED A MIGRATION IF THE SITE ADDS AN ICON, and that is the
-- honest cost: the alternative is a column that accepts anything and
-- means nothing.
-- =====================================================================

\set ON_ERROR_STOP on

ALTER TABLE hbh.site_services
  ADD CONSTRAINT ck_ssv_icon CHECK (
    icon_key IS NULL OR icon_key IN ('i1','i2','i3','i4','i5','i6','i7','i8')
  );

ALTER TABLE hbh.site_programs
  ADD CONSTRAINT ck_sp_icon CHECK (
    icon_key IS NULL OR icon_key IN ('i1','i2','i3','i4','i5','i6','i7','i8')
  );

INSERT INTO hbh.schema_migrations (version) VALUES ('0049');
