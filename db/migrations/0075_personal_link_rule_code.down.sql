-- =====================================================================
-- 0075 down - the register forgets the rule code again.
--
-- Any exemption already filed under NO_PERSONAL_LINK is removed first.
-- Leaving it would make the CHECK constraint below unaddable and the
-- whole revert fail on a row nobody is looking at - and a down file
-- that cannot run is a down file that does not exist.
--
-- Removing an exemption re-exposes whatever it covered to the p00
-- check. That is correct: the rule it was excused from is being taken
-- out of the register in the same breath, so the check has no way to
-- pass it either. Reverting this leaves p00 red for every table the
-- rule catches, which is the honest state of a schema that has dropped
-- the rule but kept the columns.
-- =====================================================================

DELETE FROM hbh.convention_exemptions WHERE rule_code = 'NO_PERSONAL_LINK';

ALTER TABLE hbh.convention_exemptions
  DROP CONSTRAINT IF EXISTS ck_convention_exemptions_rule;

ALTER TABLE hbh.convention_exemptions
  ADD CONSTRAINT ck_convention_exemptions_rule
  CHECK (rule_code = ANY (ARRAY[
    'AUDIT_COLUMNS',
    'SOFT_DELETE',
    'NO_RECORDING'
  ]));

DELETE FROM hbh.schema_migrations WHERE version = '0075';
