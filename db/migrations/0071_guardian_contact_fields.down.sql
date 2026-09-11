\set ON_ERROR_STOP on
ALTER TABLE hbh.guardians
  DROP COLUMN IF EXISTS email,
  DROP COLUMN IF EXISTS city,
  DROP COLUMN IF EXISTS relationship;
DELETE FROM hbh.schema_migrations WHERE version = '0071';
