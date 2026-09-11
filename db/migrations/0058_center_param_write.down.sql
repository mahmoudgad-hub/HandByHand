-- =====================================================================
-- 0058 down - remove the parameter write path.
--
-- The centre overrides written while this was applied are LEFT IN
-- PLACE. They are the centre's real operating values, and dropping
-- them would silently return the invoice period, the tax rate and the
-- rest to the shipped defaults - a change nobody asked for, made by a
-- rollback. Reverting removes the door, not what came through it.
--
-- The column goes because nothing else reads it.
-- =====================================================================

DROP FUNCTION IF EXISTS hbh.set_center_param(text, text);

ALTER TABLE hbh.sys_params DROP COLUMN IF EXISTS editable_flg;

DELETE FROM hbh.schema_migrations WHERE version = '0058';
