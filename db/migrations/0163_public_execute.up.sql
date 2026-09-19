-- =====================================================================
-- Hand By Hand (new) - migration 0163: PUBLIC stops being able to run
-- what only hbh_app should run.
--
-- MEASURED, NOT SUSPECTED. In this schema today: 238 functions, 100 of
-- them executable by PUBLIC, 59 of those SECURITY DEFINER - and 19 of
-- THOSE are SECURITY DEFINER functions that do not return a trigger, i.e.
-- functions somebody can actually call.
--
-- HOW IT HAPPENED: a new function is executable by PUBLIC unless told
-- otherwise, and this schema has no default privileges. Every function
-- written with REVOKE ... FROM PUBLIC beside its GRANT is clean; the ones
-- written with only a GRANT carry an extra PUBLIC entry nobody meant. I
-- caught it once by hand, in 0154, on a function I was writing that day.
--
-- WHAT IT MEANS TODAY, said plainly rather than dramatically: the cluster
-- has two roles, hbh_owner and hbh_app, and hbh_app was the intended
-- caller of fourteen of these anyway. So there is no third party today.
-- The exposure is of two kinds and neither needs one:
--
--   * FIVE ARE INTERNAL and reachable by the API role only through
--     PUBLIC: center_today, check_installments_total, payment_plan_problem,
--     settle_installments and - the one that matters -
--     MARK_INSTALLMENT_DUES, the maintenance task that moves instalments
--     to DUE and OVERDUE across EVERY centre and notifies the families.
--     Nothing outside the schema calls any of them (grepped: zero
--     references in api/, web/, scripts/, deploy/). They are the same
--     shape 0150 closed for next_number and expire_packages.
--
--   * FOURTEEN carry a PUBLIC entry beside an explicit hbh_app grant -
--     create_user, set_user_roles, archive_user, issue_invoice and the
--     rest. Harmless while two roles exist, and a trap the day a third is
--     added: a read-only reporting login would inherit EXECUTE on all of
--     them without anybody writing a grant.
--
-- WHAT THIS DOES NOT TOUCH. Trigger functions keep their PUBLIC entry:
-- calling one directly raises 0A000 "trigger functions can only be called
-- as triggers", so there is nothing to take away. And functions that are
-- NOT SECURITY DEFINER run with the caller's own rights and their own RLS
-- - PUBLIC there is not a privilege, it is the caller's own reach.
--
-- hbh_app LOSES EXACTLY FIVE and keeps the other fourteen: the probe
-- captures its callable set before and after and diffs it, rather than
-- trusting the reasoning above.
-- =====================================================================

DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0162') THEN
    RAISE EXCEPTION 'migration 0162 must be applied first';
  END IF;
END
$guard$;

-- Fourteen that keep their explicit hbh_app grant and lose only PUBLIC.
REVOKE EXECUTE ON FUNCTION hbh.archive_user(p_user_id integer, p_restore boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hbh.can_edit_therapist(p_therapist_id integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hbh.create_invoice(p_child_id integer, p_guardian_id integer, p_due_date date, p_note_ar text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hbh.create_user(p_username text, p_full_name_ar text, p_user_type text, p_mobile text, p_branch_id integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hbh.current_user_is_staff() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hbh.issue_invoice(p_invoice_id integer, p_payment_plan_id integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hbh.override_installment_schedule(p_invoice_id integer, p_schedule jsonb, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hbh.publish_therapist_profile(p_therapist_id integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hbh.record_therapist_consent(p_therapist_id integer, p_text_version text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hbh.remove_invoice_line(p_line_id integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hbh.set_user_roles(p_user_id integer, p_role_codes text[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hbh.update_therapist_profile(p_therapist_id integer, p_bio_ar text, p_practice_since_year smallint, p_age_from_mon smallint, p_age_to_mon smallint, p_clear text[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hbh.update_user(p_user_id integer, p_full_name_ar text, p_mobile text, p_status text, p_clear_mobile boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION hbh.withdraw_therapist_consent(p_therapist_id integer) FROM PUBLIC;

-- Five internal helpers. No grant to hbh_app: every caller is another
-- SECURITY DEFINER function, which runs as the owner and keeps its reach -
-- the same treatment 0150 gave next_number and expire_packages.
REVOKE EXECUTE ON FUNCTION hbh.center_today(p_center_id integer) FROM PUBLIC;   -- internal: no grant to hbh_app
REVOKE EXECUTE ON FUNCTION hbh.check_installments_total(p_invoice_id integer) FROM PUBLIC;   -- internal: no grant to hbh_app
REVOKE EXECUTE ON FUNCTION hbh.mark_installment_dues() FROM PUBLIC;   -- internal: no grant to hbh_app
REVOKE EXECUTE ON FUNCTION hbh.payment_plan_problem(p_plan_id integer) FROM PUBLIC;   -- internal: no grant to hbh_app
REVOKE EXECUTE ON FUNCTION hbh.settle_installments(p_invoice_id integer) FROM PUBLIC;   -- internal: no grant to hbh_app

DO $verify$
DECLARE l_bad text;
BEGIN
  SELECT string_agg(q.proname, ', ' ORDER BY q.proname) INTO l_bad
  FROM  (SELECT p.proname, p.oid
         FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE  n.nspname = 'hbh' AND p.prokind = 'f'
           AND  p.prosecdef AND p.prorettype <> 'trigger'::regtype
         OFFSET 0) q
  WHERE has_function_privilege('public', q.oid, 'EXECUTE');
  IF l_bad IS NOT NULL THEN
    RAISE EXCEPTION '0163: PUBLIC can still execute: %', l_bad;
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0163');
