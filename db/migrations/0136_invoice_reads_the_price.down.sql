-- Hand By Hand (new) - migration 0136 DOWN. Development only.
DROP TRIGGER IF EXISTS trg_appointments_billing_model ON hbh.appointments;
DROP TRIGGER IF EXISTS trg_child_packages_billing_model ON hbh.child_packages;
DROP FUNCTION IF EXISTS hbh.trg_billing_model_appointment();
DROP FUNCTION IF EXISTS hbh.trg_billing_model_package();
DROP FUNCTION IF EXISTS hbh.add_invoice_line(integer, text, numeric, numeric, integer, integer, text);
-- The six-argument version, exactly as it was, so the API keeps billing.
CREATE FUNCTION hbh.add_invoice_line(p_invoice_id integer, p_description_ar text,
  p_qty numeric DEFAULT 1, p_unit_amt numeric DEFAULT 0,
  p_service_id integer DEFAULT NULL, p_sort_order integer DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = hbh, pg_catalog AS $f$
DECLARE l_inv hbh.invoices%ROWTYPE; l_id integer;
BEGIN
  IF NOT hbh.has_permission('BILLING.MANAGE') THEN
    RAISE EXCEPTION 'changing an invoice needs BILLING.MANAGE' USING ERRCODE = 'HB052';
  END IF;
  SELECT * INTO l_inv FROM hbh.invoices WHERE invoice_id = p_invoice_id
    AND center_id = hbh.current_center_id() AND active_flg FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'no such invoice %', p_invoice_id USING ERRCODE = 'HB051'; END IF;
  IF l_inv.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'invoice % is % - its amounts can no longer change', p_invoice_id, l_inv.status
      USING ERRCODE = 'HB050';
  END IF;
  INSERT INTO hbh.invoice_lines (center_id, invoice_id, description_ar, service_id, qty, unit_amt, line_amt, sort_order)
  VALUES (l_inv.center_id, p_invoice_id, p_description_ar, p_service_id, p_qty, p_unit_amt,
          round(p_qty * p_unit_amt, 2),
          coalesce(p_sort_order, (SELECT coalesce(max(sort_order), 0) + 10 FROM hbh.invoice_lines WHERE invoice_id = p_invoice_id)))
  RETURNING line_id INTO l_id;
  PERFORM hbh.recalc_invoice(p_invoice_id);
  RETURN l_id;
END $f$;
GRANT EXECUTE ON FUNCTION hbh.add_invoice_line(integer, text, numeric, numeric, integer, integer) TO hbh_app;
DELETE FROM hbh.sys_params WHERE param_code = 'INVOICE_REQUIRE_CATALOGUE_PRICE' AND center_id IS NULL;
DELETE FROM hbh.schema_migrations WHERE version = '0136';
