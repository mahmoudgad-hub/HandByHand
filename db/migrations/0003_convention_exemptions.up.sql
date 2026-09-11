-- =====================================================================
-- Hand By Hand (new) - migration 0003: the exemption register
--
-- Migration 0002 added two tables that do not carry the audit columns
-- or the soft-delete flag, and the conventions suite caught them - as
-- it should have. The question is what to do about it, and there are
-- only three answers:
--
--   1. Pad the tables with columns that mean nothing there. otp_codes
--      already has issued_at and consumed_at; created_at would be a
--      second issued_at and active_flg would be a worse consumed_at.
--      Dishonest, and it teaches the reader to ignore the convention.
--   2. Add the table names to the test file. The rule then lives in the
--      test instead of the schema, and every phase quietly edits the
--      rule it is supposed to be measured against.
--   3. Record the exemption HERE, next to the schema, with a reason
--      somebody has to write down.
--
-- This is the third. An exemption with no reason is rejected by the
-- suite, so the register cannot become a place to hide things.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0003') THEN
    RAISE EXCEPTION 'migration 0003 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0002') THEN
    RAISE EXCEPTION 'migration 0002 must be applied first';
  END IF;
END
$guard$;

CREATE TABLE hbh.convention_exemptions (
  exemption_id integer     GENERATED ALWAYS AS IDENTITY,
  table_name   text        NOT NULL,
  rule_code    text        NOT NULL,
  reason       text        NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  CONSTRAINT pk_convention_exemptions PRIMARY KEY (exemption_id),
  CONSTRAINT uq_convention_exemptions UNIQUE (table_name, rule_code),
  CONSTRAINT ck_convention_exemptions_rule CHECK (rule_code IN ('AUDIT_COLUMNS','SOFT_DELETE')),
  -- A reason of "n/a" is not a reason. Twenty characters is not a high
  -- bar; it is just high enough that nobody clears the rule by accident.
  CONSTRAINT ck_convention_exemptions_reason CHECK (length(btrim(reason)) >= 20)
);

COMMENT ON TABLE hbh.convention_exemptions IS
  'Tables deliberately outside a schema-wide convention, each with a written reason. Read by tests/db/p00_verify.sql.';

ALTER TABLE hbh.convention_exemptions ENABLE ROW LEVEL SECURITY;
-- No policy and no grant: this is schema metadata, and the API has no
-- business reading it.

INSERT INTO hbh.convention_exemptions (table_name, rule_code, reason) VALUES
  ('otp_codes', 'AUDIT_COLUMNS',
   'A credential record, not business data. issued_at and consumed_at ARE its lifecycle; created_at would duplicate issued_at and updated_by would name the system on every row.'),
  ('otp_codes', 'SOFT_DELETE',
   'A one-time code is consumed or it expires - consumed_at and expires_at carry that. A code that is merely deactivated is a code that still exists, which is the opposite of what single-use means.'),
  ('auth_sessions', 'AUDIT_COLUMNS',
   'A credential record, not business data. issued_at, last_seen_at and revoked_at ARE its lifecycle, and nobody edits a session row by hand.'),
  ('auth_sessions', 'SOFT_DELETE',
   'A session is revoked, not deactivated. revoked_at plus revoked_reason say who ended it and why, which active_flg cannot.'),
  ('audit_log', 'AUDIT_COLUMNS',
   'The audit log auditing itself is a loop. changed_by and changed_at are already the attribution the convention asks for.'),
  ('audit_log', 'SOFT_DELETE',
   'Append-only by trigger. A row here is never removed, so a flag that hides one would be a way to tamper with the record.'),
  ('convention_exemptions', 'AUDIT_COLUMNS',
   'Schema metadata, changed only by a migration. created_at and created_by are kept; an update trail on a register of exemptions has no reader.'),
  ('convention_exemptions', 'SOFT_DELETE',
   'An exemption is withdrawn by deleting it in a migration. A deactivated exemption still sitting in the table is exactly the ambiguity this register exists to remove.'),
  ('schema_migrations', 'AUDIT_COLUMNS',
   'The migration ledger. applied_at and applied_by are its audit columns under different names, and it predates the convention itself.'),
  ('schema_migrations', 'SOFT_DELETE',
   'A migration was applied or it was not. There is no third state, and a soft-deleted migration row would make the ledger lie.');

INSERT INTO hbh.schema_migrations (version) VALUES ('0003');
