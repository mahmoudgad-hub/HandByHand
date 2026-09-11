-- =====================================================================
-- Hand By Hand (new) - migration 0006 DOWN
--
-- Development convenience only.
-- View and tables before functions: a policy - and a view - depends on
-- the functions it calls, and the whole file runs in one transaction,
-- so a function dropped too early takes the entire teardown with it and
-- silently leaves the old definitions in place.
-- =====================================================================

DROP VIEW  IF EXISTS hbh.v_goal_progress;

DROP TABLE IF EXISTS hbh.progress_reports;
DROP TABLE IF EXISTS hbh.session_notes;
DROP TABLE IF EXISTS hbh.goal_measurements;
DROP TABLE IF EXISTS hbh.plan_goals;
DROP TABLE IF EXISTS hbh.treatment_plans;

DROP FUNCTION IF EXISTS hbh.publish_report(integer);
DROP FUNCTION IF EXISTS hbh.publish_session_note(integer);
DROP FUNCTION IF EXISTS hbh.write_session_note(integer, text);
DROP FUNCTION IF EXISTS hbh.can_edit_session(integer);
DROP FUNCTION IF EXISTS hbh.trg_report_guard();
DROP FUNCTION IF EXISTS hbh.trg_note_publish_guard();
DROP FUNCTION IF EXISTS hbh.trg_note_born_internal();
DROP FUNCTION IF EXISTS hbh.trg_plan_status();
DROP FUNCTION IF EXISTS hbh.legal_plan_transition(text, text);


DELETE FROM hbh.schema_migrations WHERE version = '0006';
