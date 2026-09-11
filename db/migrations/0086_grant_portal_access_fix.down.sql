-- Hand By Hand (new) - migration 0086 DOWN. Development only.
-- Deliberately does NOT restore 0085's version: it wrote an audit row
-- with an action ck_audit_log_action rejects, so every call raised
-- 23514. Rolling back to a function that cannot run is not a rollback.
DELETE FROM hbh.schema_migrations WHERE version = '0086';
