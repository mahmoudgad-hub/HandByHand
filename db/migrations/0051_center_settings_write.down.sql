-- Down for 0051. The trigger goes before the function it calls, and the
-- policy before the grant it relies on - dropping in the other order
-- fails, and the whole migration is one transaction, so a failure here
-- rolls back everything and leaves the schema looking untouched.
\set ON_ERROR_STOP on

DROP TRIGGER IF EXISTS trg_guard_center_settings ON hbh.centers;
DROP FUNCTION IF EXISTS hbh.guard_center_settings();
DROP POLICY IF EXISTS p_centers_update ON hbh.centers;

REVOKE UPDATE (name_ar, name_en, country_code, currency_code,
               time_zone, weekend_days, updated_at, updated_by)
  ON hbh.centers FROM hbh_app;
