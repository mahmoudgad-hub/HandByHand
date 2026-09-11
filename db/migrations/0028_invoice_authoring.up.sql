-- =====================================================================
-- Hand By Hand (new) - migration 0028: an invoice can be created
--
-- WHAT WAS MISSING, AND HOW IT WAS FOUND. The console session built the
-- billing screen against the API and reported that it had two actions -
-- issue and take payment - and no way to reach either: both work on an
-- invoice that ALREADY EXISTS, hbh.sell_package does not make one, and
-- nothing in the schema did. They had to INSERT by hand to finish
-- testing. A centre could therefore never bill anybody.
--
-- WHY THIS IS PL/pgSQL AND NOT THREE INSERTS IN Go.
--
-- Everything an invoice needs is a rule that already lives here:
--
--   * the number comes from hbh.next_number - a gapless series with a
--     year reset, and two receptionists creating invoices at the same
--     moment must not get the same number;
--   * the currency comes from the CENTRE row, never from the caller. A
--     client that could name the currency could bill a family in a
--     currency the centre does not use;
--   * the tax rate comes from hbh.param, so a change of rate is a row
--     and not a release - and it is captured ON the invoice at creation,
--     because a rate that moved last month must not silently restate an
--     invoice issued before it;
--   * the totals are COMPUTED by hbh.recalc_invoice and never sent. D-17.
--
-- An API that assembled the row itself would be a second copy of four
-- rules, and the copies would disagree - with the weaker one deciding.
--
-- WHAT THESE FUNCTIONS REFUSE.
--
--   HB050  the invoice is not a DRAFT. Amounts stop moving the moment a
--          family has been given a number to pay; a line added to an
--          issued invoice would change what they owe after the fact.
--   HB051  no such invoice, or not this caller's centre.
--   HB052  the caller does not hold BILLING.MANAGE.
--   HB054  the child is not one this caller may act for.
--
-- A NOTE ON HB054. The existing HB05x codes are all about the invoice;
-- this one is about the CHILD, and it is new rather than folded into
-- HB052 because the API already has to guess at HB052 - the schema uses
-- it for both "needs BILLING.MANAGE" and "this invoice can no longer
-- change", and that ambiguity costs the interface a precise message.
-- Adding a third meaning to it would make that worse.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0028') THEN
    RAISE EXCEPTION 'migration 0028 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0006') THEN
    RAISE EXCEPTION 'migration 0006 must be applied first';
  END IF;
END
$guard$;

-- How long a family has to pay. A parameter, not a constant: it is a
-- commercial decision the centre owns, and the next centre will have a
-- different one. NULL center_id makes it the default for every centre
-- until one overrides it with a row of its own.
INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar)
SELECT NULL, 'INVOICE_DUE_DAYS', '14', 'NUMBER', 'عدد الأيام حتى استحقاق الفاتورة'
WHERE NOT EXISTS (SELECT 1 FROM hbh.sys_params
                   WHERE param_code = 'INVOICE_DUE_DAYS' AND center_id IS NULL);

-- =====================================================================
-- CREATE
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.create_invoice(
  p_child_id    integer,
  p_guardian_id integer DEFAULT NULL,
  p_due_date    date    DEFAULT NULL,
  p_note_ar     text    DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_center   integer := hbh.current_center_id();
  l_child    hbh.children%ROWTYPE;
  l_currency char(3);
  l_rate     numeric(5,4);
  l_due      integer;
  l_no       text;
  l_id       integer;
BEGIN
  IF NOT hbh.has_permission('BILLING.MANAGE') THEN
    RAISE EXCEPTION 'creating an invoice needs BILLING.MANAGE' USING ERRCODE = 'HB052';
  END IF;

  -- can_access_child, not a centre check: it is the same gate every read
  -- of this child passes, so a caller who cannot see the child cannot
  -- bill them either.
  IF NOT hbh.can_access_child(p_child_id) THEN
    RAISE EXCEPTION 'child % is not visible to this caller', p_child_id
      USING ERRCODE = 'HB054';
  END IF;

  SELECT * INTO l_child FROM hbh.children WHERE child_id = p_child_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such child %', p_child_id USING ERRCODE = 'HB054';
  END IF;

  SELECT c.currency_code INTO l_currency FROM hbh.centers c WHERE c.center_id = l_center;
  l_rate := hbh.param(l_center, 'DEFAULT_TAX_RATE', '0')::numeric;
  l_due  := hbh.param(l_center, 'INVOICE_DUE_DAYS', '14')::integer;
  l_no   := hbh.next_number(l_center, 'INVOICE');

  INSERT INTO hbh.invoices (center_id, branch_id, invoice_no, child_id, guardian_id,
                            currency_code, tax_rate, due_date, note_ar, status)
  VALUES (l_center, l_child.branch_id, l_no, p_child_id,
          -- The guardian named, or the primary one on file. An invoice
          -- with no guardian has nobody to send it to.
          coalesce(p_guardian_id,
                   (SELECT gc.guardian_id FROM hbh.guardian_children gc
                     WHERE gc.child_id = p_child_id AND gc.active_flg
                     ORDER BY gc.is_primary_flg DESC, gc.guardian_id
                     LIMIT 1)),
          l_currency, l_rate,
          coalesce(p_due_date, current_date + l_due), p_note_ar, 'DRAFT')
  RETURNING invoice_id INTO l_id;

  RETURN l_id;
END
$$;

COMMENT ON FUNCTION hbh.create_invoice(integer, integer, date, text) IS
  'Opens a DRAFT invoice for a child. Number, currency and tax rate come from the centre, never from the caller (0028).';

-- =====================================================================
-- LINES
--
-- line_amt is computed here rather than accepted. A caller that sent
-- qty, unit_amt AND line_amt could send three numbers that do not agree,
-- and the invoice would then say something no arithmetic supports.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.add_invoice_line(
  p_invoice_id     integer,
  p_description_ar text,
  p_qty            numeric DEFAULT 1,
  p_unit_amt       numeric DEFAULT 0,
  p_service_id     integer DEFAULT NULL,
  p_sort_order     integer DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_inv hbh.invoices%ROWTYPE;
  l_id  integer;
BEGIN
  IF NOT hbh.has_permission('BILLING.MANAGE') THEN
    RAISE EXCEPTION 'changing an invoice needs BILLING.MANAGE' USING ERRCODE = 'HB052';
  END IF;

  SELECT * INTO l_inv FROM hbh.invoices
   WHERE invoice_id = p_invoice_id
     AND center_id = hbh.current_center_id()
     AND active_flg
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such invoice %', p_invoice_id USING ERRCODE = 'HB051';
  END IF;

  IF l_inv.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'invoice % is % - its amounts can no longer change', p_invoice_id, l_inv.status
      USING ERRCODE = 'HB050';
  END IF;

  INSERT INTO hbh.invoice_lines (center_id, invoice_id, description_ar, service_id,
                                 qty, unit_amt, line_amt, sort_order)
  VALUES (l_inv.center_id, p_invoice_id, p_description_ar, p_service_id,
          p_qty, p_unit_amt, round(p_qty * p_unit_amt, 2),
          coalesce(p_sort_order,
                   (SELECT coalesce(max(sort_order), 0) + 10 FROM hbh.invoice_lines
                     WHERE invoice_id = p_invoice_id)))
  RETURNING line_id INTO l_id;

  PERFORM hbh.recalc_invoice(p_invoice_id);
  RETURN l_id;
END
$$;

COMMENT ON FUNCTION hbh.add_invoice_line(integer, text, numeric, numeric, integer, integer) IS
  'Adds a line to a DRAFT invoice and recomputes the totals. line_amt is derived, never sent (0028).';

-- Removing a line is a SOFT delete, like everything else in this schema,
-- and it is refused once the invoice has left DRAFT for the same reason
-- adding one is: a family has already been told what they owe.
CREATE OR REPLACE FUNCTION hbh.remove_invoice_line(p_line_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_line hbh.invoice_lines%ROWTYPE;
  l_inv  hbh.invoices%ROWTYPE;
BEGIN
  IF NOT hbh.has_permission('BILLING.MANAGE') THEN
    RAISE EXCEPTION 'changing an invoice needs BILLING.MANAGE' USING ERRCODE = 'HB052';
  END IF;

  SELECT * INTO l_line FROM hbh.invoice_lines
   WHERE line_id = p_line_id AND center_id = hbh.current_center_id() AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such invoice line %', p_line_id USING ERRCODE = 'HB051';
  END IF;

  SELECT * INTO l_inv FROM hbh.invoices WHERE invoice_id = l_line.invoice_id FOR UPDATE;
  IF l_inv.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'invoice % is % - its amounts can no longer change', l_inv.invoice_id, l_inv.status
      USING ERRCODE = 'HB050';
  END IF;

  UPDATE hbh.invoice_lines
     SET active_flg = false, deleted_at = now()
   WHERE line_id = p_line_id;

  PERFORM hbh.recalc_invoice(l_line.invoice_id);
END
$$;

COMMENT ON FUNCTION hbh.remove_invoice_line(integer) IS
  'Soft-deletes a line from a DRAFT invoice and recomputes the totals (0028).';

GRANT EXECUTE ON FUNCTION hbh.create_invoice(integer, integer, date, text) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.add_invoice_line(integer, text, numeric, numeric, integer, integer) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.remove_invoice_line(integer) TO hbh_app;

-- The tables themselves stay closed. Every route into an invoice is one
-- of these functions, so there is no second way in that skips the
-- numbering, the currency or the recalculation.
DO $verify$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n
  FROM   information_schema.role_table_grants
  WHERE  grantee = 'hbh_app' AND table_schema = 'hbh'
  AND    table_name IN ('invoices','invoice_lines')
  AND    privilege_type IN ('INSERT','UPDATE','DELETE');
  IF n <> 0 THEN
    RAISE EXCEPTION 'the invoice tables were granted directly (% grant(s)) - the functions are the only way in', n;
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0028');
