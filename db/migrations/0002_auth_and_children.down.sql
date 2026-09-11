-- =====================================================================
-- Hand By Hand (new) - migration 0002 DOWN
--
-- Development convenience only. Drops exactly what 0002 created and
-- leaves 0001 standing, so a phase can be rebuilt without rebuilding
-- the foundation under it.
-- =====================================================================

-- Tables BEFORE functions, and the order matters more than it looks.
--
-- A policy depends on the function it calls, so dropping
-- can_access_child while p_children_select still exists fails with
-- "other objects depend on it" - and because the whole down migration
-- runs in one transaction, NOTHING is dropped, the rebuild silently
-- reuses the old definitions, and a fix that was just written appears
-- not to work. Dropping the table takes its policies with it.
DROP TABLE IF EXISTS hbh.auth_sessions;
DROP TABLE IF EXISTS hbh.otp_codes;
DROP TABLE IF EXISTS hbh.guardian_children;
DROP TABLE IF EXISTS hbh.guardians;
DROP TABLE IF EXISTS hbh.children;
DROP TABLE IF EXISTS hbh.user_roles;
DROP TABLE IF EXISTS hbh.role_permissions;
DROP TABLE IF EXISTS hbh.roles;
DROP TABLE IF EXISTS hbh.permissions;
DROP TABLE IF EXISTS hbh.number_series;

DROP FUNCTION IF EXISTS hbh.audit_attempt(text, integer, text, text, inet);
DROP FUNCTION IF EXISTS hbh.revoke_auth_session(text, text);
DROP FUNCTION IF EXISTS hbh.resolve_auth_session(text);
DROP FUNCTION IF EXISTS hbh.create_auth_session(integer, text, inet, text);
DROP FUNCTION IF EXISTS hbh.verify_otp(text, text);
DROP FUNCTION IF EXISTS hbh.request_otp(text);
DROP FUNCTION IF EXISTS hbh.param(integer, text, text);
DROP FUNCTION IF EXISTS hbh.random_digits(integer);
DROP FUNCTION IF EXISTS hbh.can_access_child(integer);
DROP FUNCTION IF EXISTS hbh.has_permission(text);
DROP FUNCTION IF EXISTS hbh.current_user_id();
DROP FUNCTION IF EXISTS hbh.next_number(integer, text);

DELETE FROM hbh.schema_migrations WHERE version = '0002';
