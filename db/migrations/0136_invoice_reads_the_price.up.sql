-- =====================================================================
-- Hand By Hand (new) - migration 0136: the invoice reads the price, and
-- a service may refuse a billing model (PR-02 · PR-03, OD-16)
--
-- Unlike 0135 this touches paths the API calls today, so the whole of it
-- is shaped by one fact, measured before a line was written:
--
--   api/internal/store/ops_write.go passes unit_amt on EVERY call, as
--   coalesce(nullif($4, '')::numeric, 0) - and passes service_id too.
--
-- So the database receives 0 whether reception typed 0 or typed nothing,
-- and cannot tell a free session from an empty field. Doc 11 §4 says
-- p_unit_amt "is not accepted from the caller when service_id is given".
-- Enforced today, that breaks every invoice line reception adds - three
-- are already live - and it breaks them with a refusal about a price
-- nobody tried to set. Doc 10 §9.1 is explicit that for new codes the
-- API lands first. This migration does not get to overrule that.
--
-- ---------------------------------------------------------------------
-- SO THE STRICTNESS IS A PARAMETER, OFF, AND OD-18 IS WHY THAT IS RIGHT
--
-- OD-18: every variable business policy is a parameter. Whether the
-- catalogue price is COMPULSORY is exactly such a policy, and it has a
-- natural moment to be switched on: once prices are loaded and the API
-- sends an explicit "no price given" instead of 0.
--
--   INVOICE_REQUIRE_CATALOGUE_PRICE = false  (today, the default)
--     A line with a service_id is charged p_unit_amt, as now - AND the
--     catalogue price is written beside it in list_amt. The discount the
--     owner wants visible IS visible from the first line after this
--     lands, without breaking one call.
--
--   INVOICE_REQUIRE_CATALOGUE_PRICE = true
--     A line with a service_id is charged the catalogue price, whatever
--     p_unit_amt says; no current price is HB257.
--
--   Either way, an explicit override - p_override_reason given - needs
--   BILLING.PRICE_OVERRIDE and charges p_unit_amt, with the reason kept.
--   Nothing calls that path yet, so it is new capability, not a change.
--
-- ---------------------------------------------------------------------
-- ONE FUNCTION, NOT TWO
--
-- A seventh parameter added with CREATE OR REPLACE creates a SECOND
-- OVERLOAD - the API's six-argument call would keep resolving to the old
-- one, and two functions would share a name (the confusion 0131 avoided
-- for record_verification_delivery). So the six-argument version is
-- dropped and the seven-argument one created with the new parameter
-- defaulted: the existing positional call binds to it unchanged.
-- pg_depend shows nothing depends on the old one.
--
-- ---------------------------------------------------------------------
-- AND A CROSS-TENANT GAP CLOSED ON THE WAY
--
-- The old body never checked that p_service_id was this centre's. Now
-- that it reads a price FROM that service, a foreign service_id would
-- read another centre's price onto this centre's invoice. Refused with
-- HB051 - "no such", which the API already translates - so closing it
-- asks nothing new of Go.
--
-- ---------------------------------------------------------------------
-- PR-03 IS A TRIGGER, AND THE REASON IS 0101
--
-- The billing model has to be enforced in sell_package and in single
-- booking. Rewriting either with CREATE OR REPLACE from a copy of its
-- body risks silently reverting whatever later migrations added - and
-- sell_package's body carries an "ADDED IN 0101" cross-tenant check that
-- a stale copy would drop. A BEFORE trigger on child_packages and on
-- appointments enforces the rule for every path, including
-- book_recurring and direct inserts, without touching either body.
--
-- The default billing model allows both, so this is a no-op until an
-- administrator restricts a service.
--
-- Error classes added here (grepped free; HB257 reserved in 0135):
--   HB257  no current catalogue price, in strict mode
--   HB258  a price override without BILLING.PRICE_OVERRIDE or a reason
--   HB259  this service's billing model does not allow it
-- =====================================================================

DO $guard$
DECLARE l_code text;
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0136') THEN
    RAISE EXCEPTION 'migration 0136 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0135') THEN
    RAISE EXCEPTION 'migration 0135 must be applied first';
  END IF;
  FOREACH l_code IN ARRAY ARRAY['HB258', 'HB259'] LOOP
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'hbh' AND p.prosrc LIKE '%' || l_code || '%') THEN
      RAISE EXCEPTION '% is already raised by some function - grep and pick another', l_code;
    END IF;
  END LOOP;
  -- The premise of "one function, not two".
  IF EXISTS (SELECT 1 FROM pg_depend d JOIN pg_proc p ON p.oid = d.refobjid
             JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'hbh' AND p.proname = 'add_invoice_line' AND d.deptype = 'n') THEN
    RAISE EXCEPTION 'something depends on add_invoice_line - dropping it is no longer safe';
  END IF;
END
$guard$;

INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar) VALUES
  (NULL, 'INVOICE_REQUIRE_CATALOGUE_PRICE', 'false', 'BOOLEAN',
   'هل سعر الكتالوج إلزامي لسطر فاتورة بخدمة؟ false = يُقبل السعر المُرسل كما اليوم ويُكتب سعر الكتالوج بجواره. true = يُفرض سعر الكتالوج. لا يُفعَّل قبل تحميل الأسعار وإرسال الواجهة "لا سعر" صريحًا بدل الصفر.')
ON CONFLICT (center_id, param_code) DO NOTHING;

-- =====================================================================
-- PR-02 · add_invoice_line v2
-- =====================================================================
DROP FUNCTION hbh.add_invoice_line(integer, text, numeric, numeric, integer, integer);

CREATE FUNCTION hbh.add_invoice_line(
  p_invoice_id      integer,
  p_description_ar  text,
  p_qty             numeric DEFAULT 1,
  p_unit_amt        numeric DEFAULT 0,
  p_service_id      integer DEFAULT NULL,
  p_sort_order      integer DEFAULT NULL,
  p_override_reason text    DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_inv    hbh.invoices%ROWTYPE;
  l_id     integer;
  l_list   numeric;
  l_unit   numeric;
  l_reason text := nullif(btrim(coalesce(p_override_reason, '')), '');
  l_strict boolean;
BEGIN
  -- Everything the old body did, in the order it did it.
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

  -- NEW: the service is this centre's, before a price is read from it.
  IF p_service_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM hbh.services s
                     WHERE s.service_id = p_service_id AND s.center_id = l_inv.center_id) THEN
    RAISE EXCEPTION 'no such service %', p_service_id USING ERRCODE = 'HB051';
  END IF;

  IF p_service_id IS NOT NULL THEN
    l_list := hbh.current_price(p_service_id, 'SINGLE');
  END IF;

  IF l_reason IS NOT NULL THEN
    -- An explicit override. New capability; nothing calls it yet.
    IF NOT hbh.has_permission('BILLING.PRICE_OVERRIDE') THEN
      RAISE EXCEPTION 'overriding a price needs BILLING.PRICE_OVERRIDE' USING ERRCODE = 'HB258';
    END IF;
    IF p_service_id IS NULL THEN
      -- A free-text line has no catalogue price to override; its amount
      -- is already whatever the caller says.
      RAISE EXCEPTION 'an override needs a service to override the price of' USING ERRCODE = 'HB258';
    END IF;
    l_unit := p_unit_amt;
  ELSIF p_service_id IS NOT NULL THEN
    l_strict := hbh.param(l_inv.center_id, 'INVOICE_REQUIRE_CATALOGUE_PRICE', 'false')::boolean;
    IF l_strict THEN
      IF l_list IS NULL THEN
        RAISE EXCEPTION 'service % has no current price', p_service_id USING ERRCODE = 'HB257';
      END IF;
      l_unit := l_list;
    ELSE
      -- Today's behaviour, unchanged - with the catalogue price now
      -- written beside it.
      l_unit := p_unit_amt;
    END IF;
  ELSE
    l_unit := p_unit_amt;   -- a free-text line, as always
  END IF;

  INSERT INTO hbh.invoice_lines (center_id, invoice_id, description_ar, service_id,
                                 qty, unit_amt, line_amt, sort_order,
                                 list_amt, override_reason_ar)
  VALUES (l_inv.center_id, p_invoice_id, p_description_ar, p_service_id,
          p_qty, l_unit, round(p_qty * l_unit, 2),
          coalesce(p_sort_order,
                   (SELECT coalesce(max(sort_order), 0) + 10 FROM hbh.invoice_lines
                     WHERE invoice_id = p_invoice_id)),
          l_list, l_reason)
  RETURNING line_id INTO l_id;

  PERFORM hbh.recalc_invoice(p_invoice_id);
  RETURN l_id;
END
$$;

COMMENT ON FUNCTION hbh.add_invoice_line(integer, text, numeric, numeric, integer, integer, text) IS
  'Adds a charge. With a service: list_amt records the catalogue price; INVOICE_REQUIRE_CATALOGUE_PRICE decides whether it is charged. An override needs BILLING.PRICE_OVERRIDE and a reason. PR-02.';

REVOKE ALL ON FUNCTION hbh.add_invoice_line(integer, text, numeric, numeric, integer, integer, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.add_invoice_line(integer, text, numeric, numeric, integer, integer, text) TO hbh_app;

-- =====================================================================
-- PR-03 · the billing model, enforced where the rows are written
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.trg_billing_model_package()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_model text;
BEGIN
  SELECT s.billing_model INTO l_model
  FROM   hbh.service_packages sp
  JOIN   hbh.services s ON s.service_id = sp.service_id
  WHERE  sp.package_id = NEW.package_id;

  IF l_model = 'SINGLE_SESSION_ONLY' THEN
    RAISE EXCEPTION 'this service is sold by the session only - it has no packages'
      USING ERRCODE = 'HB259';
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER trg_child_packages_billing_model
  BEFORE INSERT OR UPDATE OF package_id ON hbh.child_packages
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_billing_model_package();

CREATE OR REPLACE FUNCTION hbh.trg_billing_model_appointment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_model text;
BEGIN
  SELECT s.billing_model INTO l_model FROM hbh.services s WHERE s.service_id = NEW.service_id;

  IF l_model = 'PACKAGE_ONLY'
     AND NOT EXISTS (
       SELECT 1
       FROM   hbh.child_packages cp
       JOIN   hbh.service_packages sp ON sp.package_id = cp.package_id
       WHERE  cp.child_id = NEW.child_id
         AND  sp.service_id = NEW.service_id
         AND  cp.active_flg
         -- READ THIS BEFORE PK-03. Today the only usable status is
         -- ACTIVE. OD-28 has sell_package book the series on a
         -- PENDING_PAYMENT subscription BEFORE it is active; when that
         -- status is added, it MUST be added here too, or every package
         -- sale for a PACKAGE_ONLY service is refused by this trigger
         -- while booking its own sessions.
         AND  cp.status IN ('ACTIVE')) THEN
    RAISE EXCEPTION 'this service is sold by package only, and this beneficiary holds no package for it'
      USING ERRCODE = 'HB259';
  END IF;
  RETURN NEW;
END
$$;

-- Both doors, the lesson of 0090: a booking, and an edit that moves an
-- existing appointment onto a PACKAGE_ONLY service.
CREATE TRIGGER trg_appointments_billing_model
  BEFORE INSERT OR UPDATE OF service_id ON hbh.appointments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_billing_model_appointment();

-- =====================================================================
-- THE PROOF: one function now, callable the old way
-- =====================================================================
DO $verify$
BEGIN
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'hbh' AND p.proname = 'add_invoice_line') <> 1 THEN
    RAISE EXCEPTION 'add_invoice_line has more than one overload';
  END IF;
  IF NOT has_function_privilege('hbh_app',
       'hbh.add_invoice_line(integer, text, numeric, numeric, integer, integer, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'hbh_app lost EXECUTE on add_invoice_line - reception cannot bill';
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0136');
