-- Down for 0050. Dropping these loses the landline and the directions;
-- they exist nowhere else once the page reads them from the database.
\set ON_ERROR_STOP on

ALTER TABLE hbh.site_contact
  DROP COLUMN IF EXISTS landline,
  DROP COLUMN IF EXISTS arrival_ar,
  DROP COLUMN IF EXISTS arrival_en;
