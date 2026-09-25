-- =====================================================================
-- 0164 down - the two functions go, and a child who already exists can
-- only be given a family by an INSERT as the owner again.
--
-- THE LINKS STAY. They say which family answers for which child, and that
-- is not scaffolding.
-- =====================================================================

DROP FUNCTION IF EXISTS hbh.link_guardian_to_child(integer, integer, text, boolean);
DROP FUNCTION IF EXISTS hbh.unlink_guardian_from_child(integer, integer);
DROP FUNCTION IF EXISTS hbh.set_primary_guardian(integer, integer);

DELETE FROM hbh.schema_migrations WHERE version = '0164';
