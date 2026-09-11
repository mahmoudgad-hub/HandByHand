-- Reverses 0105. The trigger goes first: dropping the function while the
-- trigger still points at it fails, and the whole migration is one
-- transaction, so nothing would be dropped at all.
DROP TRIGGER IF EXISTS trg_users_revoke_sessions ON hbh.users;
DROP FUNCTION IF EXISTS hbh.trg_revoke_sessions_on_offboard();

DELETE FROM hbh.schema_migrations WHERE version = '0105';
