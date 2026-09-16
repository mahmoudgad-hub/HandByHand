-- Hand By Hand (new) - migration 0135 DOWN. Development only.
DROP FUNCTION IF EXISTS hbh.set_service_price(integer, text, numeric, timestamptz);
DROP FUNCTION IF EXISTS hbh.current_price(integer, text, timestamptz);
DROP TABLE IF EXISTS hbh.service_prices;
ALTER TABLE hbh.invoice_lines
  DROP CONSTRAINT IF EXISTS ck_ilines_override_reason,
  DROP CONSTRAINT IF EXISTS ck_ilines_list_amt;
ALTER TABLE hbh.invoice_lines DROP COLUMN IF EXISTS override_reason_ar, DROP COLUMN IF EXISTS list_amt;
ALTER TABLE hbh.services DROP CONSTRAINT IF EXISTS ck_services_billing_model;
ALTER TABLE hbh.services
  DROP COLUMN IF EXISTS allow_parent_cancel_flg,
  DROP COLUMN IF EXISTS allow_parent_reschedule_flg,
  DROP COLUMN IF EXISTS allow_parent_self_booking_flg,
  DROP COLUMN IF EXISTS billing_model;
DELETE FROM hbh.schema_migrations WHERE version = '0135';
