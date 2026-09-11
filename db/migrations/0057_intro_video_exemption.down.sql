-- Down for 0057. Withdrawing the exemption makes the conventions suite
-- refuse the schema again while the intro_video columns exist, which is
-- correct: without the registered reason there is nothing saying why a
-- column named video is allowed to be there.
\set ON_ERROR_STOP on

DROP INDEX IF EXISTS hbh.ix_site_team_video_consent_by;

ALTER TABLE hbh.convention_exemptions
  DROP CONSTRAINT ck_convention_exemptions_rule;

ALTER TABLE hbh.convention_exemptions
  ADD CONSTRAINT ck_convention_exemptions_rule
    CHECK (rule_code IN ('AUDIT_COLUMNS', 'SOFT_DELETE'));

DELETE FROM hbh.convention_exemptions
WHERE table_name = 'site_team' AND rule_code = 'NO_RECORDING';

DELETE FROM hbh.schema_migrations WHERE version = '0057';
