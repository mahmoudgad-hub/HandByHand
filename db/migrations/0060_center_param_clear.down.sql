-- =====================================================================
-- 0060 down - remove the way back.
--
-- Overrides already cleared stay cleared. Their rows are inactive, and
-- reactivating them here would put every centre back on a value somebody
-- deliberately abandoned - a change nobody asked for, made by a
-- rollback. Reverting removes the door, not what went through it, which
-- is the same rule 0058's down file follows.
-- =====================================================================

-- set_center_param keeps its correction. Reverting it would put back a
-- setter that leaves deleted_at standing on a row it has just brought
-- back to life - and rows cleared while 0060 was applied are exactly the
-- ones that would hit it. A rollback should remove a capability, not
-- reintroduce a defect.
DROP FUNCTION IF EXISTS hbh.clear_center_param(text);

DELETE FROM hbh.schema_migrations WHERE version = '0060';
