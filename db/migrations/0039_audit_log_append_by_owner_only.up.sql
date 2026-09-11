-- =====================================================================
-- 0039 - the audit trail stops accepting writes from the API role
--
-- WHAT WAS WRONG
-- hbh_app held INSERT on hbh.audit_log, and the policy that let it
-- through was p_audit_log_insert ... WITH CHECK (true) - not one
-- condition. The role the API connects as could therefore write an
-- audit row naming any centre, any actor, any table and any action.
--
-- WHAT IT WAS NOT
-- It was never an erasure. hbh_app holds no SELECT, no UPDATE and no
-- DELETE here, and trg_audit_log_append_only refuses modification even
-- to the owner. The genuine rows always survived. What was possible was
-- POLLUTION: false entries sitting beside true ones, indistinguishable
-- to whoever reads the trail afterwards.
--
-- WHY THAT MATTERS MORE THAN IT SOUNDS
-- This table is the evidence. It is where sensitive READS are recorded,
-- because triggers cannot see a SELECT - so if a read is not written
-- here it is written nowhere. A trail that any foothold in the API
-- layer can write into is weaker than it looks on the day somebody
-- reads it in an investigation.
--
-- AND THE GRANT WAS NEVER NEEDED
-- Both paths that write this table run as the OWNER, not as hbh_app:
--
--   * change records  - hbh.trg_audit() is SECURITY DEFINER;
--   * attempt records - hbh.audit_attempt() reaches its own connection
--                       through dblink and lands as the owner there.
--
-- The Go service never inserts into this table directly; every audit
-- record it writes goes through hbh.audit_attempt (api/internal/audit).
-- Both were exercised with the grant already revoked before this
-- migration was written, and both still wrote their row.
--
-- This is the same least-privilege line the schema already draws around
-- otp_codes, auth_sessions and number_series, each of which hbh_app is
-- refused by name and each of which has a check saying so. The audit
-- trail is now on that list, and p00 asserts it for every future
-- migration rather than this one alone.
-- =====================================================================

-- Order matters only for readability - either alone would close the
-- hole, and both are removed so neither can be read later as the one
-- that was meant to stay.
DROP POLICY IF EXISTS p_audit_log_insert ON hbh.audit_log;

REVOKE INSERT ON hbh.audit_log FROM hbh_app;

-- RLS stays enabled with no policy at all for hbh_app, which is how
-- the other forbidden tables are shaped here: the deny is total and it
-- does not depend on a policy expression being read correctly.
COMMENT ON TABLE hbh.audit_log IS
  'Append-only evidence. Written ONLY by the owner: hbh.trg_audit (SECURITY DEFINER) for changes, hbh.audit_attempt (dblink) for attempts. hbh_app holds no privilege here - see 0039.';

INSERT INTO hbh.schema_migrations (version) VALUES ('0039');
