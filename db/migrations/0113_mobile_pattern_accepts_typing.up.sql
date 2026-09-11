-- =====================================================================
-- 0113 - MOBILE_PATTERN accepts what a person actually types
--
-- NUMBER RESERVED BEFORE WRITING. 0106-0111 belong to another session in
-- this tree; 0112 is mine and this corrects it.
--
-- NO NEW SQLSTATE, so the API does not have to go down first.
--
-- ---------------------------------------------------------------------
-- WHAT 0112 GOT WRONG
--
-- 0112 loosened MOBILE_PATTERN to accept the international form, and the
-- value it wrote was
--
--     ^(\+[1-9][0-9]{7,14}|00[1-9][0-9]{7,14}|0[0-9]{6,14})$
--
-- which is the shape of a number with NOTHING BETWEEN THE DIGITS. Then
-- the first Gulf guardian was typed the way a Gulf number is always
-- written - "+966 50 123 4567" - and was refused HB170, by a rule that
-- was supposed to have stopped refusing exactly that.
--
-- IT WAS INVISIBLE IN TESTING BECAUSE canonical_mobile STRIPS SPACES,
-- and every check written against canonical_mobile passed. The order is
-- what makes it matter, and 0112 documents that order itself:
-- trg_guardians_identity_format fires before trg_guardians_mobile_canon
-- (i < m, and BEFORE row triggers fire in name order). So the pattern
-- sees the RAW value - separators and all - and the canonicaliser never
-- gets to run. Testing the function proved the function; it could not
-- prove the pair.
--
-- ---------------------------------------------------------------------
-- WHY WIDEN THE PATTERN RATHER THAN REORDER THE TRIGGERS
--
-- Because of what this parameter is FOR, which 0112 spells out and then
-- did not follow through: it is WHAT A PERSON MAY TYPE. The API reads it
-- at the edge (auth_handlers.go) to answer a bad number without a round
-- trip, and at the edge the value has not been near a canonicaliser.
-- Reordering would hold the typed value to a shape only the database
-- produces, and the portal would refuse "01500000093" - every Egyptian
-- login in the country - while the database was perfectly happy with it.
--
-- What may be STORED is not this parameter's business and never was:
-- ck_guardians_mobile_e164 and its three siblings say that, and they are
-- checked after the canonicaliser has run.
--
-- So this pattern is a SIEVE, not a specification. It rejects a word, an
-- empty box and an absurd length - which is all an edge check can honestly
-- do - and hbh.canonical_mobile remains the thing that decides.
--
-- The class allows the Arabic-Indic digits an Arabic keyboard produces,
-- because canonical_mobile already translates them and a sieve that
-- refuses what the decider accepts is just a slower refusal.
-- =====================================================================

\set ON_ERROR_STOP on

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0113') THEN
    RAISE EXCEPTION 'migration 0113 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0112') THEN
    RAISE EXCEPTION 'migration 0112 must be applied first';
  END IF;
END
$guard$;

-- A leading + is optional, the first character after it must be a digit
-- so that "+ " and "-01500000093" are refused, and what follows may
-- carry the separators a person types. 6 to 24 of them after the first,
-- which is wide enough for the longest E.164 number written in groups
-- and narrow enough to reject a paragraph.
UPDATE hbh.sys_params
   SET param_value    = '^\+?[0-9٠-٩][0-9٠-٩\s().-]{5,24}$',
       description_ar = 'ما يجوز كتابته كرقم جوّال — يقبل المسافات والشرطات والأرقام العربية. شكل التخزين E.164 وتفرضه القاعدة',
       updated_at     = now(),
       updated_by     = hbh.current_app_user()
 WHERE param_code = 'MOBILE_PATTERN';

-- The sieve is only honest if the decider still refuses what it should.
-- These are the cases the wider class now lets through to
-- canonical_mobile, and every one of them has to come back refused.
DO $verify$
DECLARE
  bad text;
BEGIN
  FOREACH bad IN ARRAY ARRAY[
    '201500000093',   -- bare digits: ambiguous, never guessed at
    '+20215000000',   -- an Egyptian landline, not a mobile
    '+9665012345',    -- too short for Saudi Arabia
    '+99912345678'    -- no country in country_dial_codes
  ] LOOP
    BEGIN
      PERFORM hbh.canonical_mobile(bad, 'EG');
      RAISE EXCEPTION '0113: canonical_mobile accepted %, which the widened pattern now lets reach it', bad;
    EXCEPTION
      WHEN SQLSTATE 'HB170' OR SQLSTATE 'HB173' THEN
        NULL;  -- refused, which is the point
    END;
  END LOOP;

  IF hbh.canonical_mobile('+966 50 123 4567', 'EG') <> '+966501234567' THEN
    RAISE EXCEPTION '0113: the number that started this does not canonicalise';
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0113');
