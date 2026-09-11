-- =====================================================================
-- 0050 - the landline and the arrival notes
--
-- The site's contact section shows three things that hbh.site_contact
-- has no column for, so they live as literal text in site/index.html:
-- a second telephone number, and three lines of directions - "you can
-- reach us by the Mohamed Naguib axis", "near the Rehab bridge and the
-- Fifth Settlement", "use Google Maps to arrive precisely".
--
-- Text on a page that the console cannot reach is text nobody can
-- correct. The centre moves, the axis is renamed, a number changes -
-- and the only way to fix it is a developer editing HTML.
--
-- ARRIVAL IS THREE LINES, NOT A PARAGRAPH. Each line is a separate
-- instruction and the page renders them as separate lines. Stored as
-- one text column with newlines in it, which is what it is - unlike the
-- team's qualifications, where each row is a CLAIM ABOUT A NAMED
-- PERSON'S CREDENTIALS that has to be correctable and auditable on its
-- own. Directions to a building are one fact with line breaks in it.
-- The console's field is a textarea for the same reason.
--
-- WHY A SEPARATE landline COLUMN rather than reusing phone. The row the
-- centre actually saved has phone = '0226127381' - a Cairo landline -
-- and the mobile in whatsapp. So the centre has two numbers and the
-- table had one column, and the value that survived is whichever was
-- typed last. Nothing here moves the existing value: which number
-- belongs in which column is the centre's to say, and guessing it would
-- silently change what the public page shows as the main number.
--
-- NO FORMAT CHECK, deliberately. The saved whatsapp value is
-- '00201095006478', which wa.me refuses - it wants bare digits, so the
-- leading 00 produces a dead link. A CHECK constraint written now would
-- refuse to install against the centre's own published row, and a
-- migration that fixes somebody's data to let itself run is a migration
-- that edits data. The number is reported to the owner instead; one
-- correction through the console fixes it, and the site already
-- tolerates both spellings when it builds the link.
-- =====================================================================

\set ON_ERROR_STOP on

ALTER TABLE hbh.site_contact
  -- The fixed line. Nullable: a centre with only a mobile is normal.
  ADD COLUMN landline   text,

  -- How to get here, in the visitor's language. Newlines are meaningful:
  -- the page renders one line per instruction.
  ADD COLUMN arrival_ar text,
  ADD COLUMN arrival_en text;

COMMENT ON COLUMN hbh.site_contact.landline IS
  'Fixed line, shown beside the mobile. Nullable.';
COMMENT ON COLUMN hbh.site_contact.arrival_ar IS
  'Directions, one instruction per line. Newlines are meaningful.';
COMMENT ON COLUMN hbh.site_contact.arrival_en IS
  'Directions in English. Written, never machine-translated.';

INSERT INTO hbh.schema_migrations (version) VALUES ('0050');
