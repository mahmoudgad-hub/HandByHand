-- =====================================================================
-- Hand By Hand (new) - migration 0137: two owner decisions, and a defect
-- in 0133 that retiring guardian 668 exposed
--
-- ---------------------------------------------------------------------
-- OD-26 · A SHARED PHONE IS LEGITIMATE
--
-- Two guardians may share one mobile - a mother and a father on the
-- family phone. Uniqueness lives on the ACCOUNT (0098), not on the
-- number; the secondary guardian is a row with no account of their own.
-- EN-D5 (a unique index on guardians.mobile) is withdrawn.
--
-- find_guardian_matches therefore learns one rule: when a number matches
-- several guardians, PREFER THE ONE WHO HOLDS AN ACCOUNT. That person is
-- who the number actually signs in as.
--
--   one row                       -> EXACT
--   several, exactly one account  -> EXACT, that one
--   several, no account           -> AMBIGUOUS - no merge (OD-07)
--   several, more than one account-> AMBIGUOUS - OD-26 says this should
--                                    not exist; the function does not
--                                    guess which it is
--
-- ---------------------------------------------------------------------
-- WHAT THIS MIGRATION DELIBERATELY DOES NOT CARRY
--
-- OD-26 also says grant_portal_access "refuses the secondary with the
-- existing code". It does not. Measured, in a rolled-back transaction,
-- with two guardians on one number and the first already granted:
--
--   ERROR: 23505: duplicate key value violates unique constraint
--          "uix_guardians_user"
--   CONTEXT: grant_portal_access line 96 at UPDATE hbh.guardians
--
-- The lookup finds the first guardian's account, skips the HB204 check
-- entirely (that branch runs only when NO guardian account exists), and
-- tries to link a second guardian to it. The API renders a raw 23505 as
-- "هذه القيمة مستعملة بالفعل" - the very defect 0126 repaired for staff.
--
-- The fix needs its own SQLSTATE (a guardian account already belonging
-- to another guardian is not "belongs to a staff account"; a second
-- meaning for HB204 is the loss D-35 warns about). A new SQLSTATE the
-- API has not learned drops into its default branch and answers 500 -
-- strictly WORSE than today's 400. 0126's own header says it: THE API
-- GOES FIRST. And a migration file left unapplied on disk waiting for
-- Go is applied by the next `migrate` from any session. So it is not
-- here. It ships once the API maps the code.
--
-- ---------------------------------------------------------------------
-- OD-31 · THE DEPOSIT IS FIFTY PERCENT
--
-- PACKAGE_DEPOSIT_PCT = 50. PACKAGE_ACTIVATION_KIND stays FULL, as OD-28
-- wrote it - turning it to DEPOSIT is a row changed in the settings
-- screen, not a build decision. Nothing reads either yet; PK-03 does
-- (paid_amt >= CASE kind WHEN 'FULL' THEN total WHEN 'DEPOSIT' THEN
-- total * pct / 100 END).
--
-- ---------------------------------------------------------------------
-- AND 0133 COMPUTED COMPLETENESS FOR A RETIRED GUARDIAN
--
-- Retiring guardian 668 (OD-30) wrote two audit rows, not one:
--
--   187796  active_flg  true  -> false     the retirement
--   187797  active_flg  false -> false     record_completeness -> COMPLETE
--
-- The retirement UPDATE left record_completeness unchanged, so
-- trg_guardians_completeness_upd fired, computed a completeness for a
-- guardian who is no longer anybody's, and wrote it. Harmless, but every
-- retirement from now on would audit a meaningless second change. The
-- centre-wide pass already filtered active_flg; the per-row trigger did
-- not. It does now.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0137') THEN
    RAISE EXCEPTION 'migration 0137 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0136') THEN
    RAISE EXCEPTION 'migration 0136 must be applied first';
  END IF;
  -- EN-D5 is withdrawn. If somebody added it meanwhile, OD-26 says stop.
  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'hbh'
             AND indexname = 'uix_guardians_mobile_active') THEN
    RAISE EXCEPTION 'uix_guardians_mobile_active exists - OD-26 withdrew it; a shared phone is legitimate';
  END IF;
END
$guard$;

-- =====================================================================
-- OD-26
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.find_guardian_matches(p_center_id integer, p_mobile text)
RETURNS TABLE (result text, guardian_id integer, full_name_ar text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_mobile   text;
  l_cc       text;
  l_n        integer;
  l_accounts integer;
BEGIN
  SELECT c.country_code INTO l_cc FROM hbh.centers c WHERE c.center_id = p_center_id;

  BEGIN
    l_mobile := hbh.canonical_mobile(p_mobile, l_cc);
  EXCEPTION WHEN SQLSTATE 'HB170' OR SQLSTATE 'HB173' THEN
    l_mobile := NULL;
  END;

  IF l_mobile IS NULL THEN
    RETURN QUERY SELECT 'NONE'::text, NULL::integer, NULL::text;
    RETURN;
  END IF;

  SELECT count(*), count(*) FILTER (WHERE g.user_id IS NOT NULL)
    INTO l_n, l_accounts
  FROM hbh.guardians g
  WHERE g.center_id = p_center_id AND g.mobile = l_mobile AND g.active_flg;

  IF l_n = 0 THEN
    RETURN QUERY SELECT 'NONE'::text, NULL::integer, NULL::text;
  ELSIF l_n = 1 THEN
    RETURN QUERY
      SELECT 'EXACT'::text, g.guardian_id, g.full_name_ar FROM hbh.guardians g
      WHERE g.center_id = p_center_id AND g.mobile = l_mobile AND g.active_flg;
  ELSIF l_accounts = 1 THEN
    -- OD-26: the number signs in as its account holder, so that is the
    -- guardian it identifies.
    RETURN QUERY
      SELECT 'EXACT'::text, g.guardian_id, g.full_name_ar FROM hbh.guardians g
      WHERE g.center_id = p_center_id AND g.mobile = l_mobile AND g.active_flg
        AND g.user_id IS NOT NULL;
  ELSE
    -- No account among them, or more than one (which OD-26 says should
    -- not happen): a person decides, not this function.
    RETURN QUERY
      SELECT 'AMBIGUOUS'::text, g.guardian_id, g.full_name_ar FROM hbh.guardians g
      WHERE g.center_id = p_center_id AND g.mobile = l_mobile AND g.active_flg
      ORDER BY g.user_id IS NULL, g.guardian_id;
  END IF;
END
$$;

-- =====================================================================
-- OD-31
-- =====================================================================
INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar) VALUES
  (NULL, 'PACKAGE_DEPOSIT_PCT', '50', 'NUMBER',
   'نسبة مبلغ التفعيل حين يكون PACKAGE_ACTIVATION_KIND = DEPOSIT (OD-31). يقرؤه تفعيل الاشتراك.'),
  (NULL, 'PACKAGE_ACTIVATION_KIND', 'FULL', 'STRING',
   'FULL = يُفعَّل الاشتراك بالسداد الكامل · DEPOSIT = ببلوغ نسبة PACKAGE_DEPOSIT_PCT (OD-28). يُغيَّر من شاشة الإعدادات.')
ON CONFLICT (center_id, param_code) DO NOTHING;

-- =====================================================================
-- 0133's per-row trigger, now blind to retired guardians
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.trg_completeness_guardian()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  -- A retired guardian is nobody's record to complete. Computing it
  -- wrote a second, meaningless audit row on every retirement.
  IF NOT NEW.active_flg THEN
    RETURN NULL;
  END IF;
  PERFORM hbh.recompute_completeness(NEW.guardian_id);
  RETURN NULL;
END
$$;

-- =====================================================================
-- THE PROOF
-- =====================================================================
DO $verify$
DECLARE
  l_before bigint;
  l_after  bigint;
  l_gid    integer;
  l_uid    integer;
  l_res    text;
  l_center integer;
BEGIN
  SELECT center_id INTO l_center FROM hbh.centers WHERE code = 'HBH';

  -- OD-26: two guardians on one number, one of them with an account.
  -- Built inside a savepoint and rolled back - no fixture survives.
  BEGIN
    INSERT INTO hbh.users (center_id, username, full_name_ar, user_type, mobile, status)
    VALUES (l_center, 'zz0137.parent', 'فحص 0137', 'GUARDIAN', '+201099990137', 'ACTIVE')
    RETURNING user_id INTO l_uid;

    INSERT INTO hbh.guardians (center_id, full_name_ar, mobile)
    VALUES (l_center, 'الأب فحص 0137', '+201099990137');
    INSERT INTO hbh.guardians (center_id, full_name_ar, mobile, user_id)
    VALUES (l_center, 'الأم فحص 0137', '+201099990137', l_uid)
    RETURNING guardian_id INTO l_gid;

    SELECT m.result INTO l_res FROM hbh.find_guardian_matches(l_center, '01099990137') m LIMIT 1;
    IF l_res IS DISTINCT FROM 'EXACT' THEN
      RAISE EXCEPTION 'OD-26: a shared number with one account holder should be EXACT, got %', l_res;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM hbh.find_guardian_matches(l_center, '01099990137') m
                   WHERE m.guardian_id = l_gid) THEN
      RAISE EXCEPTION 'OD-26: EXACT did not pick the account holder';
    END IF;

    RAISE EXCEPTION 'rollback the probe' USING ERRCODE = 'HB999';
  EXCEPTION WHEN sqlstate 'HB999' THEN NULL;
  END;

  -- The 0133 fix: retiring an active guardian writes ONE audit row.
  BEGIN
    INSERT INTO hbh.guardians (center_id, full_name_ar, mobile)
    VALUES (l_center, 'تقاعد فحص 0137', '+201099990138')
    RETURNING guardian_id INTO l_gid;

    SELECT count(*) INTO l_before FROM hbh.audit_log
    WHERE table_name = 'guardians' AND row_pk = l_gid::text;

    UPDATE hbh.guardians SET active_flg = false, deleted_at = now() WHERE guardian_id = l_gid;

    SELECT count(*) INTO l_after FROM hbh.audit_log
    WHERE table_name = 'guardians' AND row_pk = l_gid::text;

    IF l_after - l_before <> 1 THEN
      RAISE EXCEPTION 'retiring a guardian wrote % audit rows - expected exactly one', l_after - l_before;
    END IF;

    RAISE EXCEPTION 'rollback the probe' USING ERRCODE = 'HB999';
  EXCEPTION WHEN sqlstate 'HB999' THEN NULL;
  END;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0137');
