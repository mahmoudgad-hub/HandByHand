-- =====================================================================
-- Hand By Hand (new) - migration 0135: the price is data with a date
-- (PR-D1 · PR-D2 · PR-D3 · PR-01, OD-16 · OD-17)
--
-- OD-17: a price lives in the database with an effective date, and
-- every financial change is permissioned and audited. OD-16: a package
-- is not compulsory - each service has a billing model and two prices,
-- and the single-session price comes FROM THE DATABASE, not from a
-- receptionist's keyboard.
--
-- ---------------------------------------------------------------------
-- THIS MIGRATION CHANGES NO BEHAVIOUR, AND THAT IS DELIBERATE
--
-- Everything here is additive: a new table, new columns whose defaults
-- are today's behaviour, and a lookup nothing calls yet. The migration
-- that DOES change a live path - add_invoice_line reading the price - is
-- 0136, and it is separate because it has a hazard this one does not:
-- the API passes unit_amt on every call, coalescing an empty value to 0,
-- so the database cannot tell "the caller typed 0" from "the caller
-- typed nothing". Tightening that before the API sends an explicit
-- signal breaks reception. Keeping the two migrations apart keeps the
-- safe half from waiting on the risky one.
--
-- ---------------------------------------------------------------------
-- WHY tstzrange AND NOT A DATE RANGE
--
-- "The same tool as appointments" (doc 11 §4): hbh.appointments already
-- refuses overlap with EXCLUDE USING gist over a tstzrange. A price
-- effective "from 1 October" is entered as that instant in the centre's
-- zone and stored in UTC, which is the rule for every instant in this
-- schema - and it means current_price compares an instant with an
-- instant, with no local-date conversion to get wrong at midnight.
--
-- ---------------------------------------------------------------------
-- current_price HAS NO GRANT, AND RETURNS RATHER THAN RAISES
--
-- It is the lookup add_invoice_line uses (0136). Screens read prices
-- through RLS on the table instead - scoped to the caller's centre - so
-- there is no function anybody can hand another centre's service_id to.
-- And a lookup returns NULL for "no current price"; it is the WRITE
-- that decides whether no price is acceptable, and refuses with HB257
-- when it is not. A lookup that raised would force every caller to
-- catch an exception to ask a question.
--
-- Error classes added here (grepped free):
--   HB257  no current price for this service and kind (raised in 0136)
--   HB260  not permitted to edit prices, or not this centre's service
-- =====================================================================

DO $guard$
DECLARE l_code text;
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0135') THEN
    RAISE EXCEPTION 'migration 0135 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0134') THEN
    RAISE EXCEPTION 'migration 0134 must be applied first';
  END IF;
  FOREACH l_code IN ARRAY ARRAY['HB257', 'HB260'] LOOP
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'hbh' AND p.prosrc LIKE '%' || l_code || '%') THEN
      RAISE EXCEPTION '% is already raised by some function - grep and pick another', l_code;
    END IF;
  END LOOP;
END
$guard$;

-- =====================================================================
-- PR-D2 · the billing model and the parent's three permissions
--
-- Defaults are TODAY: both a package and a single session are allowed,
-- and a parent changes nothing directly (they ask, through
-- parent_requests, which stays available whatever these say).
-- =====================================================================
ALTER TABLE hbh.services
  ADD COLUMN billing_model                 text    NOT NULL DEFAULT 'PACKAGE_AND_SINGLE_SESSION',
  ADD COLUMN allow_parent_self_booking_flg boolean NOT NULL DEFAULT false,
  ADD COLUMN allow_parent_reschedule_flg   boolean NOT NULL DEFAULT false,
  ADD COLUMN allow_parent_cancel_flg       boolean NOT NULL DEFAULT false;

ALTER TABLE hbh.services
  ADD CONSTRAINT ck_services_billing_model
  CHECK (billing_model IN ('PACKAGE_ONLY', 'SINGLE_SESSION_ONLY', 'PACKAGE_AND_SINGLE_SESSION'));

-- OD-06: online consultation is the one service a parent books directly.
UPDATE hbh.services SET allow_parent_self_booking_flg = true WHERE kind_code = 'CONSULT';

-- =====================================================================
-- PR-D3 · the catalogue price beside the charged one
--
-- list_amt makes a discount a NUMBER on the line rather than a guess
-- somebody reconstructs later. Both nullable: a free-text line has no
-- catalogue price, and the three lines already issued predate one.
-- =====================================================================
ALTER TABLE hbh.invoice_lines
  ADD COLUMN list_amt           numeric(12,2),
  ADD COLUMN override_reason_ar text;

ALTER TABLE hbh.invoice_lines
  ADD CONSTRAINT ck_ilines_list_amt CHECK (list_amt IS NULL OR list_amt >= 0),
  -- A reason without a price to override is a note in the wrong column.
  ADD CONSTRAINT ck_ilines_override_reason
  CHECK (override_reason_ar IS NULL OR btrim(override_reason_ar) <> '');

-- =====================================================================
-- PR-D1 · the price list
-- =====================================================================
CREATE TABLE hbh.service_prices (
  price_id       integer       GENERATED ALWAYS AS IDENTITY,
  center_id      integer       NOT NULL,
  service_id     integer       NOT NULL,
  price_kind     text          NOT NULL,
  amount         numeric(12,2) NOT NULL,
  currency_code  text          NOT NULL,
  effective_from timestamptz   NOT NULL,
  effective_to   timestamptz,
  active_flg     boolean       NOT NULL DEFAULT true,
  deleted_at     timestamptz,
  created_at     timestamptz   NOT NULL DEFAULT now(),
  created_by     text          NOT NULL DEFAULT hbh.current_app_user(),
  updated_at     timestamptz,
  updated_by     text,
  CONSTRAINT pk_service_prices PRIMARY KEY (price_id),
  CONSTRAINT fk_sprice_center  FOREIGN KEY (center_id)  REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_sprice_service FOREIGN KEY (service_id) REFERENCES hbh.services (service_id),
  CONSTRAINT ck_sprice_kind    CHECK (price_kind IN ('PACKAGE', 'SINGLE')),
  CONSTRAINT ck_sprice_amount  CHECK (amount >= 0),
  CONSTRAINT ck_sprice_window  CHECK (effective_to IS NULL OR effective_to > effective_from),
  -- Two live prices of the same kind for the same service may not both be
  -- in force at any instant. The same tool that stops two appointments
  -- sharing a therapist.
  CONSTRAINT ex_sprice_overlap EXCLUDE USING gist (
    service_id WITH =,
    price_kind WITH =,
    tstzrange(effective_from, effective_to, '[)') WITH &&
  ) WHERE (active_flg)
);

CREATE INDEX ix_sprice_center  ON hbh.service_prices (center_id);
CREATE INDEX ix_sprice_service ON hbh.service_prices (service_id, price_kind, effective_from DESC);

CREATE TRIGGER trg_sprice_touch
  BEFORE UPDATE ON hbh.service_prices
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

-- OD-17: every financial change audited.
CREATE TRIGGER trg_sprice_audit
  AFTER INSERT OR UPDATE OR DELETE ON hbh.service_prices
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit();

ALTER TABLE hbh.service_prices ENABLE ROW LEVEL SECURITY;

-- Read by anyone in the centre - the portal shows prices, and the public
-- site publishes them. Scoped to the caller's centre so no screen reads
-- another's.
CREATE POLICY p_sprice_select ON hbh.service_prices
  FOR SELECT TO hbh_app
  USING ((SELECT hbh.current_center_id() IS NOT NULL)
         AND center_id = (SELECT hbh.current_center_id())
         AND active_flg);

-- No write policy and no INSERT/UPDATE grant: prices change only through
-- set_service_price, which checks BILLING.PRICE_EDIT and closes the
-- previous price in the same statement. A raw INSERT could open a second
-- price without closing the first, and the EXCLUDE would then refuse it
-- with a message about ranges instead of about prices.
GRANT SELECT ON hbh.service_prices TO hbh_app;

-- =====================================================================
-- PR-01 · reading and setting a price
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.current_price(
  p_service_id integer,
  p_kind       text,
  p_at         timestamptz DEFAULT now())
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT sp.amount
  FROM   hbh.service_prices sp
  WHERE  sp.service_id = p_service_id
    AND  sp.price_kind = p_kind
    AND  sp.active_flg
    AND  sp.effective_from <= p_at
    AND  (sp.effective_to IS NULL OR sp.effective_to > p_at)
  -- The EXCLUDE guarantees at most one, so LIMIT 1 changes nothing; it is
  -- here so that a future relaxation of that constraint degrades to
  -- "the latest" rather than to a multi-row error inside an invoice.
  ORDER  BY sp.effective_from DESC
  LIMIT  1
$$;

COMMENT ON FUNCTION hbh.current_price(integer, text, timestamptz) IS
  'The price in force for a service and kind at an instant, or NULL. Internal - no grant; screens read service_prices through RLS. Returns rather than raises: the write decides whether no price is acceptable.';

CREATE OR REPLACE FUNCTION hbh.set_service_price(
  p_service_id     integer,
  p_kind           text,
  p_amount         numeric,
  p_effective_from timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_center   integer := hbh.current_center_id();
  l_svc      hbh.services%ROWTYPE;
  l_currency text;
  l_next     timestamptz;
  l_id       integer;
BEGIN
  IF l_center IS NULL OR NOT hbh.has_permission('BILLING.PRICE_EDIT') THEN
    RAISE EXCEPTION 'editing a price needs BILLING.PRICE_EDIT' USING ERRCODE = 'HB260';
  END IF;

  -- Read the row, is it mine, then act.
  SELECT * INTO l_svc FROM hbh.services s
  WHERE s.service_id = p_service_id AND s.center_id = l_center AND s.active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'service % is not this centre''s', p_service_id USING ERRCODE = 'HB260';
  END IF;

  IF p_kind NOT IN ('PACKAGE', 'SINGLE') THEN
    RAISE EXCEPTION 'unknown price kind %', p_kind USING ERRCODE = 'HB260';
  END IF;

  SELECT c.currency_code INTO l_currency FROM hbh.centers c WHERE c.center_id = l_center;

  -- A price already scheduled AFTER this one bounds it, so setting a
  -- price between two others does not overlap the later one.
  SELECT min(sp.effective_from) INTO l_next
  FROM   hbh.service_prices sp
  WHERE  sp.service_id = p_service_id AND sp.price_kind = p_kind AND sp.active_flg
    AND  sp.effective_from > p_effective_from;

  -- And the price in force at that instant ends where this one begins.
  -- History is kept - the old row is closed, not rewritten, so an
  -- invoice issued under it still reads back the price it was issued at.
  UPDATE hbh.service_prices sp
     SET effective_to = p_effective_from
   WHERE sp.service_id = p_service_id AND sp.price_kind = p_kind AND sp.active_flg
     AND sp.effective_from < p_effective_from
     AND (sp.effective_to IS NULL OR sp.effective_to > p_effective_from);

  INSERT INTO hbh.service_prices (center_id, service_id, price_kind, amount, currency_code,
                                  effective_from, effective_to)
  VALUES (l_center, p_service_id, p_kind, p_amount, l_currency, p_effective_from, l_next)
  RETURNING price_id INTO l_id;

  RETURN l_id;
END
$$;

COMMENT ON FUNCTION hbh.set_service_price(integer, text, numeric, timestamptz) IS
  'Sets a price from an instant, closing the one in force and bounded by any already scheduled after it. BILLING.PRICE_EDIT, this centre''s services only. PR-01.';

REVOKE ALL ON FUNCTION hbh.current_price(integer, text, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.set_service_price(integer, text, numeric, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.set_service_price(integer, text, numeric, timestamptz) TO hbh_app;

-- The p00 convention on sequences, satisfied up front this time.
GRANT USAGE, SELECT ON SEQUENCE hbh.service_prices_price_id_seq TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0135');
