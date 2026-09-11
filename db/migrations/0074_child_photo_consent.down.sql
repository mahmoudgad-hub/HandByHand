-- Restores 0073's column. The photographs themselves stay in
-- hbh.attachments - dropping the purpose marker must not take a child's
-- picture with it.
\set ON_ERROR_STOP on

DROP FUNCTION IF EXISTS hbh.set_child_photo(integer, text, text, bytea);
DROP TRIGGER IF EXISTS trg_att_photo_consent ON hbh.attachments;
DROP FUNCTION IF EXISTS hbh.trg_child_photo_needs_consent();
DROP INDEX IF EXISTS hbh.uix_att_child_photo;

ALTER TABLE hbh.attachments DROP CONSTRAINT IF EXISTS ck_att_photo_shape;
ALTER TABLE hbh.attachments DROP CONSTRAINT IF EXISTS ck_att_purpose;
ALTER TABLE hbh.attachments DROP COLUMN IF EXISTS purpose;

ALTER TABLE hbh.children ADD COLUMN IF NOT EXISTS photo_url text;

DELETE FROM hbh.schema_migrations WHERE version = '0074';
