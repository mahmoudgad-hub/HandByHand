-- Hand By Hand (new) - migration 0129 DOWN. Development only.
DROP TRIGGER IF EXISTS trg_children_origin_immutable  ON hbh.children;
DROP TRIGGER IF EXISTS trg_guardians_origin_immutable ON hbh.guardians;
DROP FUNCTION IF EXISTS hbh.trg_origin_immutable();
DROP INDEX IF EXISTS hbh.ix_children_origin;
DROP INDEX IF EXISTS hbh.ix_guardians_reg_source;
ALTER TABLE hbh.children
  DROP CONSTRAINT IF EXISTS ck_children_origin_ref,
  DROP CONSTRAINT IF EXISTS ck_children_origin;
ALTER TABLE hbh.children
  DROP COLUMN IF EXISTS origin_reference_id,
  DROP COLUMN IF EXISTS origin_source;
ALTER TABLE hbh.guardians
  DROP CONSTRAINT IF EXISTS ck_guardians_completeness,
  DROP CONSTRAINT IF EXISTS ck_guardians_reg_source;
ALTER TABLE hbh.guardians
  DROP COLUMN IF EXISTS record_completeness,
  DROP COLUMN IF EXISTS registration_source;
DELETE FROM hbh.schema_migrations WHERE version = '0129';
