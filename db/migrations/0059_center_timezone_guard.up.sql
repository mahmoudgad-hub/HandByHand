-- =====================================================================
-- 0059 - a centre's time zone must be a time zone
--
-- 0051 opened time_zone for writing and guarded currency and code. It
-- left the zone free, with the reasoning written out: every instant is
-- stored UTC and converted for display only, so changing the zone moves
-- what is SHOWN and nothing that is recorded. That is right about the
-- data and wrong about the string.
--
-- WHAT BREAKS. The value is not decoration - it is loaded by name:
--
--   api/internal/http/ops_handlers.go   time.LoadLocation(tzName)
--
-- and that call is how "today" is resolved for the diary. A zone Go
-- cannot load returns an error, the handler answers 500, and the
-- appointments and sessions screens stop opening. So an administrator
-- typing "Cairo" instead of "Africa/Cairo" into a settings box takes
-- the centre's diary down, and the screen that did it gives no hint:
-- the failure surfaces two screens away as a server error.
--
-- There is no CHECK constraint to write this as, because the set of
-- valid names is not a pattern - it is a table the engine ships,
-- pg_timezone_names, and it changes with the tzdata the server carries.
-- A regular expression over it would accept "Africa/Cairoo".
--
-- WHY THE GUARD AND NOT GO. Rule 2, and the same reason 0051 put the
-- currency rule here: the API is not the only way a row is written, and
-- a check in a handler is a second copy of a rule that the next writer
-- does not pass through.
--
-- ONLY WHEN IT CHANGES. A row whose zone predates this migration stays
-- editable in its other columns; the lookup runs when somebody actually
-- moves the value.
--
-- The function is replaced rather than the trigger recreated: the
-- trigger references it by name and keeps working. Same shape as 0052.
--
-- HB162 continues 0051/0052's group.
--
-- ORDER OF DEPLOYMENT: the API goes first, as in 0053 and 0058 - a
-- SQLSTATE the running binary does not recognise becomes a 500.
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

  -- The zone is loaded by name in Go to resolve "today" for the diary.
  -- pg_timezone_names is the engine's own list, so this accepts exactly
  -- what the server can actually resolve rather than what looks like a
  -- zone.
  IF NEW.time_zone IS DISTINCT FROM OLD.time_zone THEN
    IF NEW.time_zone IS NULL
       OR NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = NEW.time_zone) THEN
      RAISE EXCEPTION 'no such time zone %', NEW.time_zone
        USING ERRCODE = 'HB162',
              HINT = 'use an IANA name such as Africa/Cairo; pg_timezone_names is the list';
    END IF;
  END IF;

  RETURN NEW;
END
$fn$;

COMMENT ON FUNCTION hbh.guard_center_settings() IS
  'Guards a centre settings write: code is immutable (HB160), currency is frozen once money exists (HB161), and the time zone must be one the engine knows (HB162).';

INSERT INTO hbh.schema_migrations (version) VALUES ('0059');
