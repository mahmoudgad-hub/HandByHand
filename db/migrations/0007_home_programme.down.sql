-- =====================================================================
-- Hand By Hand (new) - migration 0007 DOWN
-- Development convenience only. View and tables before functions.
-- =====================================================================

DROP VIEW  IF EXISTS hbh.v_activity_adherence;

DROP TABLE IF EXISTS hbh.parent_requests;
DROP TABLE IF EXISTS hbh.activity_log;
DROP TABLE IF EXISTS hbh.child_activities;
DROP TABLE IF EXISTS hbh.activity_library;

DROP FUNCTION IF EXISTS hbh.decide_request(integer, text, text);
DROP FUNCTION IF EXISTS hbh.submit_request(integer, text, integer, text, timestamptz);
DROP FUNCTION IF EXISTS hbh.log_activity(integer, date, boolean, text);
DROP FUNCTION IF EXISTS hbh.trg_request_status();
DROP FUNCTION IF EXISTS hbh.legal_request_transition(text, text);

DELETE FROM hbh.schema_migrations WHERE version = '0007';
