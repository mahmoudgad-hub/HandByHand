-- Hand By Hand (new) - migration 0024 DOWN. Development only.
DROP VIEW     IF EXISTS hbh.v_attachment_index;
DROP TABLE    IF EXISTS hbh.attachments;
DROP FUNCTION IF EXISTS hbh.publish_attachment(integer);
DROP FUNCTION IF EXISTS hbh.attach_file(text, integer, integer, text, text, bytea, text);
DROP FUNCTION IF EXISTS hbh.trg_attachment_audit();
DROP FUNCTION IF EXISTS hbh.trg_attachment_publish_guard();
DROP FUNCTION IF EXISTS hbh.trg_attachment_born_internal();
DELETE FROM hbh.schema_migrations WHERE version = '0024';
