-- =====================================================================
-- 0039 down - hand the API role its INSERT on the audit trail back.
--
-- Reverting this REOPENS the hole 0039 closed: the role the API
-- connects as can again write an audit row naming any centre, any
-- actor, any table and any action. Nothing in the service needs that -
-- both audit paths run as the owner - so the only reason to run this
-- is to get back to the exact shape the schema had before 0039.
--
-- The policy is recreated with the same name and the same WITH CHECK
-- (true) it carried in 0001, so a database reverted to here is the one
-- that existed before, not a third variant of it.
-- =====================================================================

GRANT INSERT ON hbh.audit_log TO hbh_app;

CREATE POLICY p_audit_log_insert ON hbh.audit_log
  FOR INSERT TO hbh_app
  WITH CHECK (true);

COMMENT ON TABLE hbh.audit_log IS NULL;

DELETE FROM hbh.schema_migrations WHERE version = '0039';
