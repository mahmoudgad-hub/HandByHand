-- =====================================================================
-- 0059 down - the guard goes back to 0052's version.
--
-- The function is restored rather than dropped: the trigger installed by
-- 0051 names it, and dropping it would leave the trigger pointing at
-- nothing and every settings write failing. Reverting removes the time
-- zone check and keeps the other two.
-- =====================================================================

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
    RAISE EXCEPTION 'centre code % is immutable', OLD.code
      USING ERRCODE = 'HB160',
            HINT = 'scripts and seeds match on it; renaming it breaks them silently';
  END IF;

  IF NEW.currency_code IS DISTINCT FROM OLD.currency_code THEN
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
END
$fn$;

DELETE FROM hbh.schema_migrations WHERE version = '0059';
