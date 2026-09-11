-- Down for 0052. Restores 0051's version of the function, defects and
-- all, because that is what "down" means - the schema as it was, not as
-- it should have been.
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
  IF NEW.code IS DISTINCT FROM OLD.code THEN
    RAISE EXCEPTION 'HB061: center code is immutable'
      USING HINT = 'scripts and seeds match on it; renaming it breaks them silently';
  END IF;

  IF NEW.currency_code IS DISTINCT FROM OLD.currency_code THEN
    SELECT EXISTS (
      SELECT 1 FROM hbh.invoices  WHERE center_id = OLD.center_id
      UNION ALL
      SELECT 1 FROM hbh.payments  WHERE center_id = OLD.center_id
    ) INTO has_money;

    IF has_money THEN
      RAISE EXCEPTION 'HB062: currency cannot change once amounts exist'
        USING HINT = 'nothing converts stored amounts; changing it relabels every past invoice';
    END IF;
  END IF;

  RETURN NEW;
END;
$fn$;

DELETE FROM hbh.schema_migrations WHERE version = '0052';
