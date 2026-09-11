-- =====================================================================
-- 0060 - returning a parameter to the value it shipped with
--
-- 0058 let a centre override a parameter and deliberately never touched
-- the global row, so the shipped default is always still there. What it
-- did not give anybody was the way back: a value once overridden stayed
-- overridden, and the screen could show "معدَّل" beside it forever with
-- no action next to the badge.
--
-- IT IS NOT A DELETE, WHATEVER THE VERB ON THE SCREEN SAYS.
-- CLAUDE.md rule 3: soft delete always, and no DELETE grant on any table
-- in this schema. hbh_app holds SELECT on hbh.sys_params and nothing
-- else, and that does not change here either - this function is
-- SECURITY DEFINER and is the only door, exactly as set_center_param is.
--
-- The override row is DEACTIVATED. That is not a compromise to satisfy
-- the rule; it is the better behaviour anyway:
--
--   hbh.param() reads `... AND active_flg`, so an inactive centre row
--   falls straight through to the global one - which is precisely the
--   result wanted, with no row removed and no history lost;
--
--   uq_sys_params is UNIQUE (center_id, param_code) and NOT partial, so
--   the deactivated row keeps its slot - and set_center_param's
--   ON CONFLICT ... DO UPDATE already sets active_flg = true, so
--   overriding the same parameter again revives the same row rather
--   than colliding with a corpse;
--
--   and the audit trail keeps both the setting and the clearing on one
--   row, attributed. A deleted row would take the question "who put
--   this centre on 21 days last March" with it.
--
-- WHY IT DOES NOT RAISE WHEN THERE IS NOTHING TO CLEAR. Asking for the
-- default when the default is already in force is not a mistake - it is
-- a screen that was drawn a moment ago. The function answers with the
-- value now in force either way, and the caller is told the truth
-- rather than an error about a row it never claimed existed.
--
-- The three refusals are 0058's, reused rather than multiplied: the
-- permission, the unknown code, and the parameter that is not a setting.
-- Clearing something you were never allowed to set is the same refusal,
-- and a second number for it would be a second thing to look up.
--
-- ORDER OF DEPLOYMENT: the API goes first. No new SQLSTATE here, so a
-- lagging binary answers correctly - but the ROUTE is what the screen
-- needs, and a button calling a path that 404s is worse than no button.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION hbh.clear_center_param(p_code text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_center integer := hbh.current_center_id();
  l_base   hbh.sys_params%ROWTYPE;
BEGIN
  IF l_center IS NULL THEN
    RAISE EXCEPTION 'no identity' USING ERRCODE = 'HB180';
  END IF;

  IF NOT hbh.has_permission('SETTINGS.MANAGE') THEN
    RAISE EXCEPTION 'returning a centre parameter to its default needs SETTINGS.MANAGE'
      USING ERRCODE = 'HB180';
  END IF;

  SELECT * INTO l_base
    FROM hbh.sys_params
   WHERE param_code = p_code AND center_id IS NULL AND active_flg;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such parameter %', p_code USING ERRCODE = 'HB181';
  END IF;

  -- A parameter nobody may set is a parameter nobody may clear. Not
  -- because clearing it would do harm - a locked one has no override to
  -- clear - but because answering "done" to a request about a value
  -- this screen does not govern says the wrong thing.
  IF NOT l_base.editable_flg THEN
    RAISE EXCEPTION 'parameter % is not editable from a screen', p_code
      USING ERRCODE = 'HB182',
            HINT = 'hbh.sys_params.editable_flg decides; some values are product or security decisions';
  END IF;

  UPDATE hbh.sys_params
     SET active_flg = false,
         deleted_at = now(),
         updated_at = now(),
         updated_by = hbh.current_app_user()
   WHERE center_id = l_center
     AND param_code = p_code
     AND active_flg;

  RETURN l_base.param_value;
END
$fn$;

COMMENT ON FUNCTION hbh.clear_center_param(text) IS
  'Deactivates a centre override so the shipped default applies again, and returns it. Needs SETTINGS.MANAGE. Soft, never a DELETE. Raises HB180 / HB181 / HB182.';

REVOKE ALL ON FUNCTION hbh.clear_center_param(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.clear_center_param(text) TO hbh_app;


-- ---------------------------------------------------------------------
-- And 0058's setter, corrected in the same breath.
--
-- Before this migration no override was ever deactivated, so a revived
-- row could not exist and the omission below could not show. Now that
-- clearing is possible it can: ON CONFLICT set active_flg = true and
-- left deleted_at alone, so overriding a parameter that had been
-- returned to its default produced a LIVE row carrying a deletion date.
--
-- Nothing reads deleted_at here - hbh.param() filters on active_flg - so
-- no value was ever wrong. But the pair is the schema's whole soft-delete
-- convention, hbh.Restore writes `active_flg = true, deleted_at = NULL`
-- everywhere else, and a row that is alive and dated dead is a question
-- somebody has to stop and answer.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.set_center_param(p_code text, p_value text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_center  integer := hbh.current_center_id();
  l_base    hbh.sys_params%ROWTYPE;
  l_value   text := btrim(coalesce(p_value, ''));
BEGIN
  IF l_center IS NULL THEN
    RAISE EXCEPTION 'no identity' USING ERRCODE = 'HB180';
  END IF;

  IF NOT hbh.has_permission('SETTINGS.MANAGE') THEN
    RAISE EXCEPTION 'changing a centre parameter needs SETTINGS.MANAGE'
      USING ERRCODE = 'HB180';
  END IF;

  -- The GLOBAL row is the definition: it carries the type and the
  -- editable flag, and a code with no global row is not a parameter.
  SELECT * INTO l_base
    FROM hbh.sys_params
   WHERE param_code = p_code AND center_id IS NULL AND active_flg;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such parameter %', p_code USING ERRCODE = 'HB181';
  END IF;

  IF NOT l_base.editable_flg THEN
    RAISE EXCEPTION 'parameter % is not editable from a screen', p_code
      USING ERRCODE = 'HB182',
            HINT = 'hbh.sys_params.editable_flg decides; some values are product or security decisions';
  END IF;

  -- The declared type is the contract the readers rely on. param() hands
  -- back text and every caller casts it, so a NUMBER holding "أربعة"
  -- fails at the point of use, far from the screen that stored it.
  -- Emptiness first, so an empty box is told it is empty rather than
  -- told it is not a number. The reason a person is given decides where
  -- they look next.
  IF l_value = '' THEN
    RAISE EXCEPTION 'parameter % may not be emptied', p_code USING ERRCODE = 'HB183';
  END IF;
  IF l_base.data_type = 'NUMBER' AND l_value !~ '^-?[0-9]+(\.[0-9]+)?$' THEN
    RAISE EXCEPTION 'parameter % expects a number', p_code USING ERRCODE = 'HB183';
  END IF;
  IF l_base.data_type = 'BOOLEAN' AND lower(l_value) NOT IN ('true', 'false') THEN
    RAISE EXCEPTION 'parameter % expects true or false', p_code USING ERRCODE = 'HB183';
  END IF;

  -- The centre's own copy. The global row is never touched.
  INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type,
                              description_ar, editable_flg)
  VALUES (l_center, p_code, l_value, l_base.data_type,
          l_base.description_ar, l_base.editable_flg)
  ON CONFLICT (center_id, param_code)
  DO UPDATE SET param_value = excluded.param_value,
                active_flg  = true,
                deleted_at  = NULL,
                updated_at  = now(),
                updated_by  = hbh.current_app_user();

  RETURN l_value;
END
$fn$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0060');
