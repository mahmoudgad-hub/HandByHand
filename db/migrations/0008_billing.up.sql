-- =====================================================================
-- Hand By Hand (new) - migration 0008: packages, invoices, payments.
--
-- Money is the part of the system a family will check line by line, so
-- the rules here are about numbers nobody can type by hand.
--
-- 1. A TOTAL IS DERIVED, NEVER ENTERED.
--    subtotal, tax and total are written by a trigger from the lines,
--    and paid_amt by a trigger from the payments. There is no path,
--    through the API or a direct UPDATE, that writes a total which does
--    not follow from the rows underneath it.
--
-- 2. TAX IS COUNTRY-NEUTRAL.
--    tax_rate and tax_amt, and a default rate read from sys_params.
--    No ZATCA, no e-invoice payload, no assumption that the rate is
--    anything in particular - Egypt starts at zero until the accountant
--    says otherwise, and a second country changes a parameter.
--
-- 3. A PACKAGE BALANCE CANNOT GO NEGATIVE.
--    Enforced by a CHECK on the row and a row lock in the function, and
--    every movement leaves an append-only ledger entry carrying the
--    balance after it. A family asking "where did my twelve sessions
--    go" gets twelve answers, not a number.
--
-- 4. A SETTLED INVOICE IS FINISHED.
--    Lines cannot be added to or changed on a paid or cancelled
--    invoice, and the amounts on it cannot be edited.
--
-- Error classes added here:
--   HB050  illegal invoice status transition
--   HB051  the package has no session left to consume
--   HB052  a settled invoice cannot be changed
--   HB053  the payment is larger than the amount outstanding
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0008') THEN
    RAISE EXCEPTION 'migration 0008 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0007') THEN
    RAISE EXCEPTION 'migration 0007 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- PACKAGES
-- =====================================================================
CREATE TABLE hbh.service_packages (
  package_id    integer      GENERATED ALWAYS AS IDENTITY,
  center_id     integer      NOT NULL,
  service_id    integer      NOT NULL,
  code          text         NOT NULL,
  name_ar       text         NOT NULL,
  sessions_cnt  smallint     NOT NULL,
  price_amt     numeric(12,2) NOT NULL,
  validity_days smallint     NOT NULL DEFAULT 180,
  active_flg    boolean      NOT NULL DEFAULT true,
  deleted_at    timestamptz,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    text         NOT NULL DEFAULT hbh.current_app_user(),
  updated_at    timestamptz,
  updated_by    text,
  CONSTRAINT pk_service_packages PRIMARY KEY (package_id),
  CONSTRAINT fk_pkg_center  FOREIGN KEY (center_id)  REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_pkg_service FOREIGN KEY (service_id) REFERENCES hbh.services (service_id),
  CONSTRAINT uq_pkg_code UNIQUE (center_id, code),
  CONSTRAINT ck_pkg_sessions CHECK (sessions_cnt BETWEEN 1 AND 200),
  CONSTRAINT ck_pkg_price    CHECK (price_amt >= 0),
  CONSTRAINT ck_pkg_validity CHECK (validity_days BETWEEN 1 AND 1095)
);

CREATE INDEX ix_pkg_center  ON hbh.service_packages (center_id);
CREATE INDEX ix_pkg_service ON hbh.service_packages (service_id);

CREATE TABLE hbh.child_packages (
  child_package_id integer      GENERATED ALWAYS AS IDENTITY,
  center_id        integer      NOT NULL,
  branch_id        integer,
  child_id         integer      NOT NULL,
  package_id       integer      NOT NULL,
  purchased_on     date         NOT NULL DEFAULT current_date,
  expires_on       date         NOT NULL,
  sessions_total   smallint     NOT NULL,
  sessions_used    smallint     NOT NULL DEFAULT 0,
  price_amt        numeric(12,2) NOT NULL,
  status           text         NOT NULL DEFAULT 'ACTIVE',
  active_flg       boolean      NOT NULL DEFAULT true,
  deleted_at       timestamptz,
  created_at       timestamptz  NOT NULL DEFAULT now(),
  created_by       text         NOT NULL DEFAULT hbh.current_app_user(),
  updated_at       timestamptz,
  updated_by       text,
  CONSTRAINT pk_child_packages PRIMARY KEY (child_package_id),
  CONSTRAINT fk_cpkg_center  FOREIGN KEY (center_id)  REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_cpkg_branch  FOREIGN KEY (branch_id)  REFERENCES hbh.branches (branch_id),
  CONSTRAINT fk_cpkg_child   FOREIGN KEY (child_id)   REFERENCES hbh.children (child_id),
  CONSTRAINT fk_cpkg_package FOREIGN KEY (package_id) REFERENCES hbh.service_packages (package_id),
  CONSTRAINT ck_cpkg_status CHECK (status IN ('ACTIVE','EXHAUSTED','EXPIRED','CANCELLED')),
  CONSTRAINT ck_cpkg_window CHECK (expires_on >= purchased_on),
  -- The balance cannot go negative, and it is stated on the row rather
  -- than left to the function that maintains it.
  CONSTRAINT ck_cpkg_used   CHECK (sessions_used BETWEEN 0 AND sessions_total),
  CONSTRAINT ck_cpkg_price  CHECK (price_amt >= 0)
);

CREATE INDEX ix_cpkg_center  ON hbh.child_packages (center_id);
CREATE INDEX ix_cpkg_branch  ON hbh.child_packages (branch_id);
CREATE INDEX ix_cpkg_child   ON hbh.child_packages (child_id, purchased_on DESC);
CREATE INDEX ix_cpkg_package ON hbh.child_packages (package_id);
CREATE INDEX ix_cpkg_live    ON hbh.child_packages (child_id) WHERE status = 'ACTIVE';

-- Append-only. A family asking where twelve sessions went gets twelve
-- rows, each naming the session that consumed one.
CREATE TABLE hbh.package_ledger (
  ledger_id        bigint      GENERATED ALWAYS AS IDENTITY,
  center_id        integer     NOT NULL,
  child_package_id integer     NOT NULL,
  session_id       integer,
  delta            smallint    NOT NULL,
  balance_after    smallint    NOT NULL,
  reason           text        NOT NULL,
  changed_by       text        NOT NULL DEFAULT hbh.current_app_user(),
  changed_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pk_package_ledger PRIMARY KEY (ledger_id),
  CONSTRAINT fk_led_center  FOREIGN KEY (center_id)        REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_led_package FOREIGN KEY (child_package_id) REFERENCES hbh.child_packages (child_package_id),
  CONSTRAINT fk_led_session FOREIGN KEY (session_id)       REFERENCES hbh.therapy_sessions (session_id),
  CONSTRAINT ck_led_delta   CHECK (delta <> 0),
  CONSTRAINT ck_led_balance CHECK (balance_after >= 0),
  CONSTRAINT ck_led_reason  CHECK (reason IN ('PURCHASE','SESSION','REFUND','ADJUSTMENT','EXPIRY'))
);

CREATE INDEX ix_led_center  ON hbh.package_ledger (center_id);
CREATE INDEX ix_led_package ON hbh.package_ledger (child_package_id, changed_at DESC);
CREATE INDEX ix_led_session ON hbh.package_ledger (session_id);

CREATE TRIGGER trg_led_append_only
  BEFORE UPDATE OR DELETE ON hbh.package_ledger
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_append_only();

-- =====================================================================
-- INVOICES
-- =====================================================================
CREATE TABLE hbh.invoices (
  invoice_id    integer      GENERATED ALWAYS AS IDENTITY,
  center_id     integer      NOT NULL,
  branch_id     integer,
  invoice_no    text         NOT NULL,
  child_id      integer      NOT NULL,
  guardian_id   integer,
  issue_date    date         NOT NULL DEFAULT current_date,
  due_date      date,
  currency_code char(3)      NOT NULL,
  subtotal_amt  numeric(12,2) NOT NULL DEFAULT 0,
  tax_rate      numeric(5,4)  NOT NULL DEFAULT 0,
  tax_amt       numeric(12,2) NOT NULL DEFAULT 0,
  total_amt     numeric(12,2) NOT NULL DEFAULT 0,
  paid_amt      numeric(12,2) NOT NULL DEFAULT 0,
  status        text         NOT NULL DEFAULT 'DRAFT',
  note_ar       text,
  -- Country-neutral hooks. Nothing writes them yet, and no e-invoicing
  -- regime is assumed - Egypt has none of the Saudi one.
  einv_ref      text,
  einv_status   text,
  active_flg    boolean      NOT NULL DEFAULT true,
  deleted_at    timestamptz,
  created_at    timestamptz  NOT NULL DEFAULT now(),
  created_by    text         NOT NULL DEFAULT hbh.current_app_user(),
  updated_at    timestamptz,
  updated_by    text,
  CONSTRAINT pk_invoices PRIMARY KEY (invoice_id),
  CONSTRAINT fk_inv_center   FOREIGN KEY (center_id)   REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_inv_branch   FOREIGN KEY (branch_id)   REFERENCES hbh.branches (branch_id),
  CONSTRAINT fk_inv_child    FOREIGN KEY (child_id)    REFERENCES hbh.children (child_id),
  CONSTRAINT fk_inv_guardian FOREIGN KEY (guardian_id) REFERENCES hbh.guardians (guardian_id),
  CONSTRAINT uq_inv_no UNIQUE (center_id, invoice_no),
  CONSTRAINT ck_inv_status CHECK (status IN ('DRAFT','ISSUED','PARTIALLY_PAID','PAID','CANCELLED')),
  CONSTRAINT ck_inv_amounts CHECK (subtotal_amt >= 0 AND tax_amt >= 0 AND total_amt >= 0 AND paid_amt >= 0),
  CONSTRAINT ck_inv_rate    CHECK (tax_rate BETWEEN 0 AND 1),
  CONSTRAINT ck_inv_total   CHECK (total_amt = subtotal_amt + tax_amt),
  CONSTRAINT ck_inv_paid    CHECK (paid_amt <= total_amt),
  CONSTRAINT ck_inv_due     CHECK (due_date IS NULL OR due_date >= issue_date)
);

CREATE INDEX ix_inv_center   ON hbh.invoices (center_id, issue_date DESC);
CREATE INDEX ix_inv_branch   ON hbh.invoices (branch_id);
CREATE INDEX ix_inv_child    ON hbh.invoices (child_id, issue_date DESC);
CREATE INDEX ix_inv_guardian ON hbh.invoices (guardian_id);
CREATE INDEX ix_inv_open     ON hbh.invoices (center_id, due_date)
  WHERE status IN ('ISSUED','PARTIALLY_PAID');

CREATE TABLE hbh.invoice_lines (
  line_id          integer      GENERATED ALWAYS AS IDENTITY,
  center_id        integer      NOT NULL,
  invoice_id       integer      NOT NULL,
  description_ar   text         NOT NULL,
  service_id       integer,
  child_package_id integer,
  session_id       integer,
  qty              numeric(8,2)  NOT NULL DEFAULT 1,
  unit_amt         numeric(12,2) NOT NULL,
  line_amt         numeric(12,2) NOT NULL,
  sort_order       integer      NOT NULL DEFAULT 100,
  active_flg       boolean      NOT NULL DEFAULT true,
  deleted_at       timestamptz,
  created_at       timestamptz  NOT NULL DEFAULT now(),
  created_by       text         NOT NULL DEFAULT hbh.current_app_user(),
  updated_at       timestamptz,
  updated_by       text,
  CONSTRAINT pk_invoice_lines PRIMARY KEY (line_id),
  CONSTRAINT fk_line_center  FOREIGN KEY (center_id)        REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_line_invoice FOREIGN KEY (invoice_id)       REFERENCES hbh.invoices (invoice_id),
  CONSTRAINT fk_line_service FOREIGN KEY (service_id)       REFERENCES hbh.services (service_id),
  CONSTRAINT fk_line_package FOREIGN KEY (child_package_id) REFERENCES hbh.child_packages (child_package_id),
  CONSTRAINT fk_line_session FOREIGN KEY (session_id)       REFERENCES hbh.therapy_sessions (session_id),
  CONSTRAINT ck_line_qty  CHECK (qty > 0),
  CONSTRAINT ck_line_unit CHECK (unit_amt >= 0),
  -- The line total follows from the line. It is not a third number
  -- somebody may disagree with.
  CONSTRAINT ck_line_amt  CHECK (line_amt = round(qty * unit_amt, 2))
);

CREATE INDEX ix_line_center  ON hbh.invoice_lines (center_id);
CREATE INDEX ix_line_invoice ON hbh.invoice_lines (invoice_id, sort_order);
CREATE INDEX ix_line_service ON hbh.invoice_lines (service_id);
CREATE INDEX ix_line_package ON hbh.invoice_lines (child_package_id);
CREATE INDEX ix_line_session ON hbh.invoice_lines (session_id);

CREATE TABLE hbh.payments (
  payment_id   integer      GENERATED ALWAYS AS IDENTITY,
  center_id    integer      NOT NULL,
  branch_id    integer,
  invoice_id   integer      NOT NULL,
  amount       numeric(12,2) NOT NULL,
  method_code  text         NOT NULL DEFAULT 'CASH',
  paid_at      timestamptz  NOT NULL DEFAULT now(),
  reference    text,
  received_by  integer,
  note_ar      text,
  active_flg   boolean      NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz  NOT NULL DEFAULT now(),
  created_by   text         NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,
  CONSTRAINT pk_payments PRIMARY KEY (payment_id),
  CONSTRAINT fk_pay_center   FOREIGN KEY (center_id)   REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_pay_branch   FOREIGN KEY (branch_id)   REFERENCES hbh.branches (branch_id),
  CONSTRAINT fk_pay_invoice  FOREIGN KEY (invoice_id)  REFERENCES hbh.invoices (invoice_id),
  CONSTRAINT fk_pay_receiver FOREIGN KEY (received_by) REFERENCES hbh.users (user_id),
  CONSTRAINT ck_pay_amount CHECK (amount > 0),
  CONSTRAINT ck_pay_method CHECK (method_code IN ('CASH','CARD','TRANSFER','WALLET','OTHER'))
);

CREATE INDEX ix_pay_center   ON hbh.payments (center_id, paid_at DESC);
CREATE INDEX ix_pay_branch   ON hbh.payments (branch_id);
CREATE INDEX ix_pay_invoice  ON hbh.payments (invoice_id, paid_at DESC);
CREATE INDEX ix_pay_receiver ON hbh.payments (received_by);

-- =====================================================================
-- DERIVED AMOUNTS
--
-- One function owns every number on the invoice header. Nothing else
-- writes them, and the guard below refuses any attempt to.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.recalc_invoice(p_invoice_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_sub  numeric(12,2);
  l_paid numeric(12,2);
  l_rate numeric(5,4);
  l_tax  numeric(12,2);
  l_tot  numeric(12,2);
  l_old  text;
  l_new  text;
BEGIN
  SELECT status, tax_rate INTO l_old, l_rate FROM hbh.invoices WHERE invoice_id = p_invoice_id;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT coalesce(sum(line_amt), 0) INTO l_sub
  FROM   hbh.invoice_lines WHERE invoice_id = p_invoice_id AND active_flg;

  SELECT coalesce(sum(amount), 0) INTO l_paid
  FROM   hbh.payments WHERE invoice_id = p_invoice_id AND active_flg;

  l_tax := round(l_sub * l_rate, 2);
  l_tot := l_sub + l_tax;

  -- The status follows the money, except that DRAFT and CANCELLED are
  -- decisions a person made and the arithmetic does not overrule them.
  l_new := CASE
             WHEN l_old IN ('DRAFT','CANCELLED') THEN l_old
             WHEN l_paid >= l_tot AND l_tot > 0  THEN 'PAID'
             WHEN l_paid > 0                     THEN 'PARTIALLY_PAID'
             ELSE 'ISSUED'
           END;

  UPDATE hbh.invoices
     SET subtotal_amt = l_sub,
         tax_amt      = l_tax,
         total_amt    = l_tot,
         paid_amt     = l_paid,
         status       = l_new
   WHERE invoice_id = p_invoice_id;
END
$$;

-- A settled invoice is finished. The guard lets recalc_invoice write
-- the derived columns while the invoice is still open, and refuses a
-- change to any of them once it is paid or cancelled.
CREATE OR REPLACE FUNCTION hbh.trg_invoice_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status IN ('PAID','CANCELLED')
     AND (NEW.subtotal_amt, NEW.tax_amt, NEW.total_amt, NEW.tax_rate,
          NEW.child_id, NEW.issue_date, NEW.currency_code)
         IS DISTINCT FROM
         (OLD.subtotal_amt, OLD.tax_amt, OLD.total_amt, OLD.tax_rate,
          OLD.child_id, OLD.issue_date, OLD.currency_code) THEN
    RAISE EXCEPTION 'invoice % is % and its amounts cannot be changed', OLD.invoice_id, OLD.status
      USING ERRCODE = 'HB052';
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION hbh.legal_invoice_transition(p_from text, p_to text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_from IS DISTINCT FROM p_to AND (p_from, p_to) IN (
    ('DRAFT',          'ISSUED'),
    ('DRAFT',          'CANCELLED'),
    ('ISSUED',         'PARTIALLY_PAID'),
    ('ISSUED',         'PAID'),
    ('ISSUED',         'CANCELLED'),
    ('PARTIALLY_PAID', 'PAID'),
    ('PARTIALLY_PAID', 'CANCELLED')
  )
$$;

CREATE OR REPLACE FUNCTION hbh.trg_invoice_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT hbh.legal_invoice_transition(OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'invoice % cannot go from % to %', OLD.invoice_id, OLD.status, NEW.status
      USING ERRCODE = 'HB050';
  END IF;
  RETURN NEW;
END
$$;

-- Lines may not be touched once the invoice is settled.
CREATE OR REPLACE FUNCTION hbh.trg_line_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  l_inv integer := coalesce(NEW.invoice_id, OLD.invoice_id);
  l_st  text;
BEGIN
  SELECT status INTO l_st FROM hbh.invoices WHERE invoice_id = l_inv;
  IF l_st IN ('PAID','CANCELLED') THEN
    RAISE EXCEPTION 'invoice % is % - its lines cannot be changed', l_inv, l_st
      USING ERRCODE = 'HB052';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END
$$;

CREATE OR REPLACE FUNCTION hbh.trg_line_recalc()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM hbh.recalc_invoice(coalesce(NEW.invoice_id, OLD.invoice_id));
  RETURN NULL;
END
$$;

-- A payment larger than what is left is a data-entry mistake, not an
-- overpayment to be silently absorbed.
CREATE OR REPLACE FUNCTION hbh.trg_payment_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  l_tot  numeric(12,2);
  l_paid numeric(12,2);
  l_st   text;
BEGIN
  SELECT total_amt, paid_amt, status INTO l_tot, l_paid, l_st
  FROM hbh.invoices WHERE invoice_id = NEW.invoice_id;

  IF l_st = 'CANCELLED' THEN
    RAISE EXCEPTION 'invoice % is cancelled and cannot take a payment', NEW.invoice_id
      USING ERRCODE = 'HB052';
  END IF;
  IF l_st = 'DRAFT' THEN
    RAISE EXCEPTION 'invoice % is still a draft and cannot take a payment', NEW.invoice_id
      USING ERRCODE = 'HB052';
  END IF;
  IF NEW.amount > (l_tot - l_paid) THEN
    RAISE EXCEPTION 'payment % exceeds the % outstanding on invoice %',
                    NEW.amount, (l_tot - l_paid), NEW.invoice_id
      USING ERRCODE = 'HB053';
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION hbh.trg_payment_recalc()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM hbh.recalc_invoice(coalesce(NEW.invoice_id, OLD.invoice_id));
  RETURN NULL;
END
$$;

-- =====================================================================
-- PACKAGES: BUYING AND SPENDING
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.sell_package(
  p_child_id   integer,
  p_package_id integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_pkg   hbh.service_packages%ROWTYPE;
  l_child hbh.children%ROWTYPE;
  l_id    integer;
BEGIN
  IF NOT hbh.has_permission('BILLING.MANAGE') THEN
    RAISE EXCEPTION 'selling a package needs BILLING.MANAGE' USING ERRCODE = 'HB052';
  END IF;

  SELECT * INTO l_pkg   FROM hbh.service_packages WHERE package_id = p_package_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such package %', p_package_id USING ERRCODE = 'HB051';
  END IF;
  SELECT * INTO l_child FROM hbh.children WHERE child_id = p_child_id;

  INSERT INTO hbh.child_packages (center_id, branch_id, child_id, package_id, expires_on,
                                  sessions_total, price_amt)
  VALUES (l_child.center_id, l_child.branch_id, p_child_id, p_package_id,
          current_date + l_pkg.validity_days, l_pkg.sessions_cnt, l_pkg.price_amt)
  RETURNING child_package_id INTO l_id;

  INSERT INTO hbh.package_ledger (center_id, child_package_id, delta, balance_after, reason)
  VALUES (l_child.center_id, l_id, l_pkg.sessions_cnt, l_pkg.sessions_cnt, 'PURCHASE');

  RETURN l_id;
END
$$;

CREATE OR REPLACE FUNCTION hbh.consume_package_session(
  p_child_package_id integer,
  p_session_id       integer DEFAULT NULL)
RETURNS smallint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_cp   hbh.child_packages%ROWTYPE;
  l_left smallint;
BEGIN
  -- FOR UPDATE, because two receptionists closing two sessions at once
  -- must not both see the last remaining session.
  SELECT * INTO l_cp FROM hbh.child_packages
  WHERE child_package_id = p_child_package_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such package balance %', p_child_package_id USING ERRCODE = 'HB051';
  END IF;

  -- Note what this branch does NOT do: it does not mark the package
  -- EXPIRED on its way out.
  --
  -- It used to, and the acceptance suite caught it. An UPDATE followed
  -- by a RAISE in the same function loses the UPDATE - the exception
  -- unwinds the transaction and takes the status change with it. This
  -- is the same shape as the attempt counter in verify_otp (D-1), and
  -- the same rule applies: a function either changes state or refuses,
  -- never both.
  --
  -- Marking expired packages is therefore its own idempotent call,
  -- hbh.expire_packages, which changes state and raises nothing.
  IF l_cp.expires_on < current_date THEN
    RAISE EXCEPTION 'package % expired on %', p_child_package_id, l_cp.expires_on
      USING ERRCODE = 'HB051';
  END IF;

  IF l_cp.status <> 'ACTIVE' OR l_cp.sessions_used >= l_cp.sessions_total THEN
    RAISE EXCEPTION 'package % has no session left (% of %)',
                    p_child_package_id, l_cp.sessions_used, l_cp.sessions_total
      USING ERRCODE = 'HB051';
  END IF;

  l_left := l_cp.sessions_total - l_cp.sessions_used - 1;

  UPDATE hbh.child_packages
     SET sessions_used = l_cp.sessions_used + 1,
         status = CASE WHEN l_left = 0 THEN 'EXHAUSTED' ELSE status END
   WHERE child_package_id = p_child_package_id;

  INSERT INTO hbh.package_ledger (center_id, child_package_id, session_id, delta, balance_after, reason)
  VALUES (l_cp.center_id, p_child_package_id, p_session_id, -1, l_left, 'SESSION');

  RETURN l_left;
END
$$;

-- Marks every package whose validity has run out, and writes the
-- forfeited balance into the ledger so a family asking "what happened
-- to my four remaining sessions" gets a row that says so.
--
-- It changes state and raises nothing, which is what lets the change
-- survive. Idempotent, so an automation may call it on any schedule.
CREATE OR REPLACE FUNCTION hbh.expire_packages(p_center_id integer DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_row hbh.child_packages%ROWTYPE;
  l_n   integer := 0;
BEGIN
  FOR l_row IN
    SELECT * FROM hbh.child_packages
    WHERE  status = 'ACTIVE'
    AND    expires_on < current_date
    AND    (p_center_id IS NULL OR center_id = p_center_id)
    FOR UPDATE
  LOOP
    UPDATE hbh.child_packages SET status = 'EXPIRED'
     WHERE child_package_id = l_row.child_package_id;

    IF l_row.sessions_total > l_row.sessions_used THEN
      INSERT INTO hbh.package_ledger (center_id, child_package_id, delta, balance_after, reason)
      VALUES (l_row.center_id, l_row.child_package_id,
              -(l_row.sessions_total - l_row.sessions_used), 0, 'EXPIRY');
    END IF;

    l_n := l_n + 1;
  END LOOP;

  RETURN l_n;
END
$$;

CREATE OR REPLACE FUNCTION hbh.issue_invoice(p_invoice_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF NOT hbh.has_permission('BILLING.MANAGE') THEN
    RAISE EXCEPTION 'issuing an invoice needs BILLING.MANAGE' USING ERRCODE = 'HB052';
  END IF;
  UPDATE hbh.invoices SET status = 'ISSUED' WHERE invoice_id = p_invoice_id;
  PERFORM hbh.recalc_invoice(p_invoice_id);
END
$$;

-- =====================================================================
-- TRIGGERS
-- =====================================================================
CREATE TRIGGER trg_pkg_touch   BEFORE UPDATE ON hbh.service_packages FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_cpkg_touch  BEFORE UPDATE ON hbh.child_packages   FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_inv_touch   BEFORE UPDATE ON hbh.invoices         FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_line_touch  BEFORE UPDATE ON hbh.invoice_lines    FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_pay_touch   BEFORE UPDATE ON hbh.payments         FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

-- Order matters: the status machine runs first, then the settled guard.
CREATE TRIGGER trg_inv_status BEFORE UPDATE ON hbh.invoices FOR EACH ROW EXECUTE FUNCTION hbh.trg_invoice_status();
CREATE TRIGGER trg_inv_guard  BEFORE UPDATE ON hbh.invoices FOR EACH ROW EXECUTE FUNCTION hbh.trg_invoice_guard();

CREATE TRIGGER trg_line_guard   BEFORE INSERT OR UPDATE OR DELETE ON hbh.invoice_lines FOR EACH ROW EXECUTE FUNCTION hbh.trg_line_guard();
CREATE TRIGGER trg_line_recalc  AFTER  INSERT OR UPDATE OR DELETE ON hbh.invoice_lines FOR EACH ROW EXECUTE FUNCTION hbh.trg_line_recalc();

CREATE TRIGGER trg_pay_guard    BEFORE INSERT ON hbh.payments FOR EACH ROW EXECUTE FUNCTION hbh.trg_payment_guard();
CREATE TRIGGER trg_pay_recalc   AFTER  INSERT OR UPDATE OR DELETE ON hbh.payments FOR EACH ROW EXECUTE FUNCTION hbh.trg_payment_recalc();

CREATE TRIGGER trg_cpkg_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.child_packages FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('child_package_id');
CREATE TRIGGER trg_inv_audit  AFTER INSERT OR UPDATE OR DELETE ON hbh.invoices       FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('invoice_id');
CREATE TRIGGER trg_pay_audit  AFTER INSERT OR UPDATE OR DELETE ON hbh.payments       FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('payment_id');

-- =====================================================================
-- ROW LEVEL SECURITY
-- =====================================================================
ALTER TABLE hbh.service_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.child_packages   ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.package_ledger   ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.invoices         ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.invoice_lines    ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.payments         ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_pkg_select ON hbh.service_packages
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg);

CREATE POLICY p_cpkg_select ON hbh.child_packages
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg AND hbh.can_access_child(child_id));

CREATE POLICY p_led_select ON hbh.package_ledger
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND EXISTS (
    SELECT 1 FROM hbh.child_packages cp
    WHERE cp.child_package_id = hbh.package_ledger.child_package_id
      AND hbh.can_access_child(cp.child_id)));

-- A draft invoice is a working document. The family sees it when it is
-- issued, not while somebody is still typing it.
CREATE POLICY p_inv_select ON hbh.invoices
  FOR SELECT TO hbh_app
  USING (
    center_id = hbh.current_center_id() AND active_flg
    AND hbh.can_access_child(child_id)
    AND (hbh.has_permission('BILLING.VIEW') OR status <> 'DRAFT')
  );

CREATE POLICY p_line_select ON hbh.invoice_lines
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg AND EXISTS (
    SELECT 1 FROM hbh.invoices i
    WHERE i.invoice_id = hbh.invoice_lines.invoice_id
      AND hbh.can_access_child(i.child_id)
      AND (hbh.has_permission('BILLING.VIEW') OR i.status <> 'DRAFT')));

CREATE POLICY p_pay_select ON hbh.payments
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg AND EXISTS (
    SELECT 1 FROM hbh.invoices i
    WHERE i.invoice_id = hbh.payments.invoice_id
      AND hbh.can_access_child(i.child_id)));

-- =====================================================================
-- A FAMILY-FACING BALANCE
-- =====================================================================
CREATE VIEW hbh.v_child_balance
WITH (security_invoker = true)
AS
SELECT i.child_id,
       i.center_id,
       i.currency_code,
       count(*) FILTER (WHERE i.status IN ('ISSUED','PARTIALLY_PAID'))       AS open_invoice_cnt,
       coalesce(sum(i.total_amt - i.paid_amt)
                FILTER (WHERE i.status IN ('ISSUED','PARTIALLY_PAID')), 0)   AS outstanding_amt,
       coalesce(sum(i.total_amt) FILTER (WHERE i.status <> 'CANCELLED'), 0)  AS invoiced_amt,
       coalesce(sum(i.paid_amt)  FILTER (WHERE i.status <> 'CANCELLED'), 0)  AS paid_amt
FROM   hbh.invoices i
WHERE  i.active_flg
GROUP  BY i.child_id, i.center_id, i.currency_code;

COMMENT ON VIEW hbh.v_child_balance IS
  'What a family owes. security_invoker=true so the caller''s policies apply.';

-- =====================================================================
-- GRANTS
-- =====================================================================
GRANT SELECT ON hbh.service_packages, hbh.child_packages, hbh.package_ledger,
                hbh.invoices, hbh.invoice_lines, hbh.payments, hbh.v_child_balance
  TO hbh_app;

REVOKE ALL ON FUNCTION hbh.sell_package(integer, integer)                FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.consume_package_session(integer, integer)     FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.expire_packages(integer)                    FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.issue_invoice(integer)                        FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.recalc_invoice(integer)                       FROM PUBLIC;

GRANT EXECUTE ON FUNCTION hbh.sell_package(integer, integer)             TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.consume_package_session(integer, integer)  TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.expire_packages(integer)                 TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.issue_invoice(integer)                     TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.legal_invoice_transition(text, text)       TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.convention_exemptions (table_name, rule_code, reason) VALUES
  ('package_ledger', 'AUDIT_COLUMNS',
   'An append-only movement record. changed_by and changed_at are its attribution, and a row here is never edited so an update trail would always be empty.'),
  ('package_ledger', 'SOFT_DELETE',
   'Append-only by trigger. A hidden movement is a session a family paid for that the balance no longer explains.');

INSERT INTO hbh.schema_migrations (version) VALUES ('0008');
