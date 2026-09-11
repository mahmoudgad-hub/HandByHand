-- =====================================================================
-- Hand By Hand (new) - migration 0009 DOWN
-- Development convenience only. Tables before functions.
-- =====================================================================

DROP TABLE IF EXISTS hbh.stream_views;
DROP TABLE IF EXISTS hbh.stream_tokens;
DROP TABLE IF EXISTS hbh.cameras;

DROP FUNCTION IF EXISTS hbh.close_session_streams(integer);
DROP FUNCTION IF EXISTS hbh.revoke_stream_token(text);
DROP FUNCTION IF EXISTS hbh.resolve_stream_token(text);
DROP FUNCTION IF EXISTS hbh.issue_stream_token(integer, inet);
DROP FUNCTION IF EXISTS hbh.can_view_live(integer);

DELETE FROM hbh.convention_exemptions WHERE table_name IN ('stream_tokens', 'stream_views');
DELETE FROM hbh.sys_params
 WHERE param_code IN ('MEDIA_GATEWAY_BASE_URL', 'MEDIA_GATEWAY_IS_TEMPORARY');

DELETE FROM hbh.schema_migrations WHERE version = '0009';
