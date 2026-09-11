-- =====================================================================
-- 0052 - correcting 0051's refusals so they can be told apart
--
-- TWO DEFECTS IN THE FUNCTION 0051 INSTALLED, both mine, and both of
-- the same family: a refusal that cannot be recognised is a refusal
-- that reaches the person as "something went wrong".
--
-- 1. NO ERRCODE. It raised with the code in the MESSAGE TEXT -
--    'HB061: center code is immutable' - and left the SQLSTATE at
--    plpgsql's default, P0001. But api/internal/store/pgerr.go reads
--    pgErr.Code, the SQLSTATE, and never the message. So both refusals
--    arrived as an unrecognised error, which that layer correctly turns
--    into a 500 with the cause in the log - and the manager is told the
--    server broke when in fact a rule refused them, on purpose, for a
--    reason worth reading.
--
-- 2. HB061 IS ALREADY TAKEN. It is "no such session, or it is not in
--    progress" for the live stream, and it is in pgerr.go under that
--    name. Had the ERRCODE been set, the console would have shown a
--    settings write the live view's wording. A number reused is worse
--    than a number missing: the second reading is confidently wrong.
--
-- HB156 was the highest code in the schema, so this group starts at
-- HB160 rather than filling the gap at HB062 - a group of its own is
-- easier to keep whole than a number squeezed between two others.
--
-- The function is replaced rather than the trigger recreated: the
-- trigger references it by name and keeps working.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION hbh.guard_center_settings()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  has_money boolean;
BEGIN
  -- `code` carries no UPDATE grant, so the API cannot reach this at all.
  -- It is refused here as well because the reason has nothing to do with
  -- who is asking: scripts and seeds outside this database match on the
  -- value, and a rename leaves them matching nothing - which is not an
  -- error anywhere, just an empty result reported as success.
  IF NEW.code IS DISTINCT FROM OLD.code THEN
    RAISE EXCEPTION 'centre code % is immutable', OLD.code
      USING ERRCODE = 'HB160',
            HINT = 'scripts and seeds match on it; renaming it breaks them silently';
  END IF;

  IF NEW.currency_code IS DISTINCT FROM OLD.currency_code THEN
    -- Read as the definer, so the answer is whether money EXISTS and not
    -- whether this caller may see it. A guardian's narrower view must
    -- not make the currency look free to change.
    SELECT EXISTS (
      SELECT 1 FROM hbh.invoices WHERE center_id = OLD.center_id
      UNION ALL
      SELECT 1 FROM hbh.payments WHERE center_id = OLD.center_id
    ) INTO has_money;

    IF has_money THEN
      RAISE EXCEPTION 'currency cannot change from % once amounts exist', OLD.currency_code
        USING ERRCODE = 'HB161',
              HINT = 'nothing converts stored amounts; changing it relabels every past invoice';
    END IF;
  END IF;

  RETURN NEW;
END;
$fn$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0052');
