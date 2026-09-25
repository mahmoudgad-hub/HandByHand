-- =====================================================================
-- 0163 down - PUBLIC can run them again. Every function goes back to the
-- entry it had, including the five internal helpers, because "what it was
-- before" is the only thing a down file may assert.
-- =====================================================================

GRANT EXECUTE ON FUNCTION hbh.archive_user(p_user_id integer, p_restore boolean) TO PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.can_edit_therapist(p_therapist_id integer) TO PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.create_invoice(p_child_id integer, p_guardian_id integer, p_due_date date, p_note_ar text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.create_user(p_username text, p_full_name_ar text, p_user_type text, p_mobile text, p_branch_id integer) TO PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.current_user_is_staff() TO PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.issue_invoice(p_invoice_id integer, p_payment_plan_id integer) TO PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.override_installment_schedule(p_invoice_id integer, p_schedule jsonb, p_reason text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.publish_therapist_profile(p_therapist_id integer) TO PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.record_therapist_consent(p_therapist_id integer, p_text_version text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.remove_invoice_line(p_line_id integer) TO PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.set_user_roles(p_user_id integer, p_role_codes text[]) TO PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.update_therapist_profile(p_therapist_id integer, p_bio_ar text, p_practice_since_year smallint, p_age_from_mon smallint, p_age_to_mon smallint, p_clear text[]) TO PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.update_user(p_user_id integer, p_full_name_ar text, p_mobile text, p_status text, p_clear_mobile boolean) TO PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.withdraw_therapist_consent(p_therapist_id integer) TO PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.center_today(p_center_id integer) TO PUBLIC;   -- internal: no grant to hbh_app
GRANT EXECUTE ON FUNCTION hbh.check_installments_total(p_invoice_id integer) TO PUBLIC;   -- internal: no grant to hbh_app
GRANT EXECUTE ON FUNCTION hbh.mark_installment_dues() TO PUBLIC;   -- internal: no grant to hbh_app
GRANT EXECUTE ON FUNCTION hbh.payment_plan_problem(p_plan_id integer) TO PUBLIC;   -- internal: no grant to hbh_app
GRANT EXECUTE ON FUNCTION hbh.settle_installments(p_invoice_id integer) TO PUBLIC;   -- internal: no grant to hbh_app

DELETE FROM hbh.schema_migrations WHERE version = '0163';
