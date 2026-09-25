-- =====================================================================
-- Hand By Hand (new) - migration 0134: 0131 missed two schema-wide
-- conventions, and p00 said so by name
--
--   shape | the E.164 check and the canonicaliser are on the same tables
--         | offenders: mobile_verifications has an E.164 check but no canonicaliser
--   shape | every sequence is usable by hbh_app
--         | offenders: mobile_verifications_verification_id_seq
--
-- Both are right, and neither is worth an exemption.
--
-- 1. THE CANONICALISER BELONGS ON THE TABLE, NOT ONLY IN THE FUNCTION.
--    request_mobile_verification canonicalises before it inserts, so no
--    raw mobile reaches ck_mver_mobile today. But that guarantee then
--    lives in ONE function, and the convention exists precisely so it
--    does not: the day a second writer appears - a repair script, a
--    phase-2 path - a raw number fails the CHECK with a message about a
--    pattern instead of being normalised. The rule is written where it
--    is enforced. Re-canonicalising an already-canonical value is a
--    no-op.
--
-- 2. THE SEQUENCE GRANT IS HARMLESS AND UNIFORM.
--    hbh_app holds no INSERT on the table, so USAGE on its sequence
--    cannot write a row. hbh.otp_codes is exactly this shape already -
--    sequence usable, table not insertable - and a checker that needs a
--    special case for one table is a checker somebody will eventually
--    special-case wrong.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0134') THEN
    RAISE EXCEPTION 'migration 0134 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0133') THEN
    RAISE EXCEPTION 'migration 0133 must be applied first';
  END IF;
END
$guard$;

CREATE TRIGGER trg_mver_mobile_canon
  BEFORE INSERT OR UPDATE ON hbh.mobile_verifications
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_canonical_mobile('mobile_e164');

GRANT USAGE, SELECT ON SEQUENCE hbh.mobile_verifications_verification_id_seq TO hbh_app;

-- The table itself stays ungranted. That is the part that matters.
DO $verify$
BEGIN
  IF has_table_privilege('hbh_app', 'hbh.mobile_verifications', 'INSERT') THEN
    RAISE EXCEPTION 'hbh_app can insert into mobile_verifications - the sequence grant was meant to be harmless, not a door';
  END IF;
  IF has_table_privilege('hbh_app', 'hbh.mobile_verifications', 'SELECT') THEN
    RAISE EXCEPTION 'hbh_app can read mobile_verifications - a table of number-plus-code-hash is not for any screen';
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0134');
