-- =====================================================================
-- 0058 - a centre may change its own operating parameters
--
-- WHAT WAS MISSING
-- hbh.sys_params has carried the centre's operating values since the
-- reference seed, and the settings screen says, in a banner, that there
-- is no endpoint to read or write them. So every one of them - the
-- invoice due period, the tax rate, how long a waiting-list offer is
-- held - could only be changed by someone with a psql prompt. The
-- permission code SETTINGS.MANAGE has existed just as long, held by
-- CENTER_ADMIN, and nothing has ever checked it.
--
-- THREE DECISIONS, AND THE FIRST IS THE IMPORTANT ONE.
--
-- 1. NOT EVERY PARAMETER IS A SETTING. Some rows in this table are
--    product decisions or security limits that a screen must not be
--    able to move, and the seed already says so in their own
--    descriptions:
--
--      RECORDING_ENABLED     "التسجيل ممنوع دائمًا … ولا تُغيَّر"
--      STREAM_TOKEN_TTL_MIN  "لا تزيد أبدًا"
--
--    A settings page that could flip RECORDING_ENABLED would put a
--    permanent decision from CLAUDE.md - live only, never recorded -
--    behind a toggle in a browser. So editability is a COLUMN, seeded
--    per row, and it DEFAULTS TO FALSE: a parameter added tomorrow is
--    locked until somebody deliberately opens it. Fail closed, the same
--    way identity does.
--
--    It is a column and not a list inside the function because it is
--    data about a parameter, and this project keeps that in the table -
--    opening one later is an UPDATE, not a migration.
--
-- 2. A WRITE CREATES A CENTRE OVERRIDE. It never touches the global
--    row. hbh.param() already resolves centre-before-global, p1 already
--    asserts "a centre override of the same code IS allowed", and the
--    unique index is NULLS NOT DISTINCT precisely so two globals
--    collide while a centre copy does not. Keeping the global row
--    untouched means the shipped default is always still there to
--    return to, and one centre can never move another's floor.
--
-- 3. NO WRITE GRANT ON THE TABLE. hbh_app keeps SELECT and nothing
--    else; this function is SECURITY DEFINER and is the only door.
--    A grant would let any future code path write a parameter without
--    passing the permission check or the editable flag.
--
-- An unknown code is refused rather than created. A typo would
-- otherwise become a new row that nothing reads, sitting in the table
-- looking like a setting.
--
-- HB180/HB181/HB182/HB183: HB172 was the highest, so this starts its
-- own group.
--
-- ORDER OF DEPLOYMENT: THE API GOES FIRST, for the reason written at
-- the head of 0053 - a SQLSTATE the running binary does not recognise
-- becomes a 500 with the cause in the log.
-- =====================================================================

\set ON_ERROR_STOP on

ALTER TABLE hbh.sys_params
  ADD COLUMN IF NOT EXISTS editable_flg boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN hbh.sys_params.editable_flg IS
  'May the settings screen change this? Defaults to false: a parameter is locked until somebody opens it deliberately.';

-- THIS UPDATE IS NOT THE ONE THAT MATTERS - see db/seed/0001_reference.sql.
--
-- It was written here and it was wrong here: db.sh applies every
-- migration BEFORE the seeds, so on a rebuilt database this runs while
-- hbh.sys_params is still empty. It matched the five rows that other
-- migrations happen to insert and silently missed the three that exist
-- only in the seed. Nothing failed; the screen just offered five
-- editable parameters instead of eight, on a fresh install only.
--
-- It stays because this migration is applied and editing an applied one
-- changes nothing on a database that already ran it. It is harmless -
-- idempotent, and it flags whatever exists - and the seed, which runs on
-- every migrate, completes the job. The authoritative list is there.
--
-- The operating values a centre manager legitimately tunes. Everything
-- absent from this list stays locked, and the omissions are deliberate:
--   OTP_* · LOGIN_* · MIN_PASSWORD_LENGTH · SESSION_TTL_MINUTES
--     security limits - a screen that can raise them weakens the door
--   ENROLMENT_MAX_PER_*        anti-abuse ceilings
--   MOBILE_PATTERN · NATIONAL_ID_LENGTH
--     country rules; changing the pattern locks out every family whose
--     number no longer matches, and no screen should do that quietly
--   MEDIA_GATEWAY_* · STREAM_TOKEN_TTL_MIN · RECORDING_ENABLED
--     infrastructure and the permanent no-recording decision
--   AUDIT_ARCHIVE_AFTER_DAYS · REQUEST_LOG_RETENTION_DAYS
--     retention of evidence; the owner decides, not a screen
UPDATE hbh.sys_params
   SET editable_flg = true
 WHERE center_id IS NULL
   AND param_code IN (
     'ALLOW_BACKDATED_BOOKING_DAYS',
     'INVOICE_DUE_DAYS',
     'DEFAULT_TAX_RATE',
     'WAITLIST_OFFER_HOURS',
     'MAX_ATTACHMENT_MB',
     'BACKUP_MAX_AGE_HOURS',
     'MAINTENANCE_MAX_AGE_MIN',
     'DATE_DISPLAY_FORMAT'
   );

-- ---------------------------------------------------------------------
-- The only door.
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
                updated_at  = now(),
                updated_by  = hbh.current_app_user();

  RETURN l_value;
END
$fn$;

COMMENT ON FUNCTION hbh.set_center_param(text, text) IS
  'Writes a CENTRE-SCOPED override of an editable parameter. Needs SETTINGS.MANAGE. Never touches the global default. Raises HB180 / HB181 / HB182 / HB183.';

REVOKE ALL ON FUNCTION hbh.set_center_param(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.set_center_param(text, text) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0058');
