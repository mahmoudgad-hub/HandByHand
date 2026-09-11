-- =====================================================================
-- 0053 down - remove the identity format rules.
--
-- Reverting here restores the asymmetry this migration was written to
-- end: MOBILE_PATTERN goes back to being read on the two OTP endpoints
-- and nowhere else, so the console can again record a number the sign-in
-- door will refuse. Rows created while this is reverted are not
-- revalidated when it is applied again - the trigger only checks a value
-- as it is written.
--
-- Triggers first, then the function they name.
-- =====================================================================

DROP TRIGGER IF EXISTS trg_children_identity_format ON hbh.children;
DROP TRIGGER IF EXISTS trg_guardians_identity_format ON hbh.guardians;
DROP FUNCTION IF EXISTS hbh.guard_identity_format();

DELETE FROM hbh.schema_migrations WHERE version = '0053';
