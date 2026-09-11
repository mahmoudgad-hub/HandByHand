-- =====================================================================
-- 0066 - the third handle on the same door
--
-- 0064 put hbh.guard_last_admin on role_permissions and user_roles: the
-- system may not be left with nobody holding USER.MANAGE, because
-- USER.MANAGE is what grants permissions and no screen could restore it.
--
-- It missed hbh.users, and the guard's own query is why the miss
-- matters. It counts holders like this:
--
--   WHERE u.active_flg AND u.status = 'ACTIVE'
--
-- so an administrator who is SUSPENDED or archived stops counting - and
-- both of those are ordinary edits on the user screen. Suspend the last
-- administrator, or archive them, and the door locks exactly as it would
-- have from the role side. The rule was right and it was only watching
-- two of the three ways in.
--
-- The same function, a third trigger. Deferred like the others: a
-- transaction that suspends one administrator and activates another is
-- a legitimate handover, and a per-row check would refuse it halfway.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE CONSTRAINT TRIGGER trg_users_last_admin
  AFTER UPDATE OR DELETE ON hbh.users
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION hbh.guard_last_admin();

INSERT INTO hbh.schema_migrations (version) VALUES ('0066');
