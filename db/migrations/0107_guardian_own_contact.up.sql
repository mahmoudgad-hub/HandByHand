-- =====================================================================
-- 0107 — THE TWO FIELDS A PARENT OWNS
--
-- NUMBER RESERVED BEFORE WRITING. 0101-0104 and 0106 belong to other
-- sessions in this tree and were applied while this was written; 0100
-- and 0105 are mine. Two files on one number is a migration that
-- vanishes without a word.
--
-- NO NEW SQLSTATE. It raises HB051, which ops_handlers.go already maps
-- to 404, so the API does not have to go down first.
--
-- ---------------------------------------------------------------------
-- WHAT A PARENT MAY CHANGE, AND WHY IT IS TWO FIELDS AND NOT SIX
--
-- Today a guardian may READ their row and change nothing on it: the
-- UPDATE policy asks for GUARDIAN.MANAGE, which no parent holds. The
-- portal says as much in its own header - a name or a number is changed
-- at reception, against identity documents, not from a phone.
--
-- That is right for identity and wrong for everything else, and the line
-- between them is not a matter of taste:
--
--   mobile        NO. It IS the login. The one-time code goes to it, so
--                 a parent who can change it from a signed-in phone can
--                 move the account to a new number - and so can anybody
--                 holding an unlocked phone for thirty seconds. This is
--                 the single most dangerous field in the table.
--   full_name_ar  NO. It is checked against a document at reception, and
--                 it is the name on clinical records and invoices.
--   national_id   NO, for the same reason and more so.
--   relationship  NO, but only for now: it is a claim about who this
--                 person is to a child, and whether it may be self-
--                 asserted is a product decision nobody has made.
--
--   email         YES. It is not an identity here - nothing authenticates
--                 with it - and the worst a mistake costs is that the
--                 centre's mail stops arriving, which the parent notices
--                 and fixes.
--   city          YES. Descriptive, and theirs.
--
-- AN ALTERNATIVE PHONE IS NOT HERE BECAUSE THERE IS NO COLUMN FOR ONE.
-- Adding one is a real decision, not a migration: it needs a place on
-- reception's screen too, or it is a number the centre stores and never
-- calls. Same for "preferences" - the schema has no such concept at all.
--
-- ---------------------------------------------------------------------
-- WHY A FUNCTION AND NOT A POLICY
--
-- An UPDATE policy can say WHICH ROWS, never WHICH COLUMNS. A policy of
-- `user_id = hbh.current_user_id()` would let a parent PATCH their own
-- mobile through the generic resource route - the exact field the list
-- above calls the most dangerous in the table. The function takes two
-- arguments and there is no third to send.
--
-- It RAISES rather than updating nothing when there is no guardian row.
-- A write that matches zero rows and reports success is the trap this
-- project has already paid for once.
-- =====================================================================

CREATE OR REPLACE FUNCTION hbh.update_own_guardian_contact(
  p_email text,
  p_city  text)
RETURNS TABLE (email text, city text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_guardian_id integer;
BEGIN
  -- Identity fails closed, and loudly. This is a write: silence would be
  -- indistinguishable from success.
  SELECT g.guardian_id INTO l_guardian_id
  FROM   hbh.guardians g
  WHERE  g.user_id = hbh.current_user_id()
    AND  g.active_flg;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no guardian record for the signed-in account'
      USING ERRCODE = 'HB051';
  END IF;

  -- Empty means "clear it", not "leave it". The screen sends the whole
  -- field either way, so an empty box must be able to empty the column -
  -- otherwise a parent can add an address and never remove one.
  UPDATE hbh.guardians g
     SET email = nullif(btrim(coalesce(p_email, '')), ''),
         city  = nullif(btrim(coalesce(p_city,  '')), '')
   WHERE g.guardian_id = l_guardian_id;

  RETURN QUERY
    SELECT g.email, g.city FROM hbh.guardians g
    WHERE  g.guardian_id = l_guardian_id;
END
$fn$;

COMMENT ON FUNCTION hbh.update_own_guardian_contact(text, text) IS
  'Lets a signed-in guardian change their own email and city, and nothing else. The mobile is the login and the name is checked against a document, so neither is an argument here - a column-restricting policy does not exist, but a two-argument function does.';

REVOKE ALL ON FUNCTION hbh.update_own_guardian_contact(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.update_own_guardian_contact(text, text) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0107');
