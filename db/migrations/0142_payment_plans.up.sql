-- =====================================================================
-- Hand By Hand (new) - migration 0142: payment plans, layer A (OD-33)
--
-- An invoice is paid on a SCHEDULE the centre configures, not on a rule
-- written in code. A plan is a template (FULL, or DEPOSIT_PERCENT with
-- instalments after the deposit); issuing an invoice copies the plan
-- into rows of invoice_installments, and payments settle those rows in
-- order. 11-FEAT §15, and §17.4 for the schedule override.
--
-- WHAT IS HERE (layer A, agreed with Business analysis 2026-09-12)
--
--   PP-D1  payment_plans                  the template
--   PP-D2  payment_plan_installments      what follows the deposit
--   PP-D3  invoice_installments           the invoice's own schedule,
--          + its state machine and history
--   PP-D4  invoices.payment_plan_id, child_packages.payment_plan_id
--   PP-01  issue_invoice v2               generates the schedule
--   PP-02  payments settle instalments IN SEQ ORDER
--   PP-04  override_installment_schedule  (§17.4 - inside the table)
--   PP-D5  BILLING.SCHEDULE_OVERRIDE      in db/seed/0002_rbac.sql
--
--   PP-03  the CALENDAR half: run_maintenance marks DAYS_AFTER_ISSUE
--          instalments DUE on their date and OVERDUE after
--          due_date + INSTALLMENT_GRACE_DAYS (a global NUMBER, 0 - no
--          grace until the owner says otherwise; OD-18)
--   PP-05  INSTALLMENT_DUE / INSTALLMENT_OVERDUE to the family and
--          STAFF_INSTALLMENT_OVERDUE to the centre, once per instalment
--
-- WHAT IS NOT (layer B, with packages): the AFTER_SESSIONS trigger on
-- child_package_services, and activating a subscription when seq 1 is
-- paid. AFTER_SESSIONS is accepted as a DEFINITION here and its
-- instalment stays PENDING, un-notified, until layer B exists - which is
-- correct, not a gap (11-FEAT §17.5, OD-38).
--
-- ---------------------------------------------------------------------
-- THE API GOES FIRST. New SQLSTATEs, each one meaning:
--
--   HB265  a payment plan cannot move between these two statuses  409
--   HB266  the plan's status does not allow this change or use     409
--          (editing a template that is no longer DRAFT; issuing on,
--          or making default, a plan that is not ACTIVE; retiring the
--          default)
--   HB267  the plan is not complete enough to become ACTIVE         422
--          (FULL with instalment rows, DEPOSIT with none, or
--          percentages past 100 minus the deposit)
--   HB268  the plan's fixed amounts exceed this invoice's total     422
--   HB269  an instalment cannot move between these two statuses    500
--          (only this schema moves them; reaching it is our defect)
--   HB270  overriding a schedule needs BILLING.SCHEDULE_OVERRIDE    403
--   HB271  a schedule override needs a reason                       422
--   HB272  the new schedule does not add up to what is still owed   422
--   HB273  a schedule entry is malformed                            400
--
-- A plan chosen at issue that does not exist, is soft-deleted, or is
-- another centre's is HB051 'no such payment plan %' - one answer, as
-- 0140 made it for services.
--
-- ---------------------------------------------------------------------
-- DECISIONS TAKEN HERE, SENT TO BUSINESS ANALYSIS, REVERSIBLE BEFORE USE
--
-- 1. CANCELLED is a fifth instalment status. An invoice that is
--    cancelled would otherwise leave its unpaid instalments DUE, and
--    the future maintenance pass would mark them OVERDUE and notify a
--    family about an invoice that no longer exists.
-- 2. SUPERSEDED is a sixth (§17.4): an override replaces unpaid rows
--    rather than editing them, so the schedule the family was first
--    given stays readable.
-- 3. The LAST instalment carries the remainder - whatever the deposit,
--    percentages and fixed amounts leave, to the piastre - so the rows
--    always add up to the total. Fixed amounts that exceed the total
--    are refused (HB268), never trimmed silently.
-- 4. Re-issuing an issued invoice is refused with HB050. v1 let it pass
--    as a no-op; v2 would have generated a second schedule.
-- 5. Invoices issued before this migration get NO schedule. A schedule
--    the family never saw is not written for them after the fact.
-- 6. "Today" is the centre's local date (centers.time_zone), computed
--    from now() - never CURRENT_DATE, which is the server's.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0142') THEN
    RAISE EXCEPTION 'migration 0142 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0141') THEN
    RAISE EXCEPTION 'migration 0141 must be applied first';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'hbh' AND p.prosrc ~ 'HB26[5-9]|HB27[0-3]') THEN
    RAISE EXCEPTION 'a live function already raises one of HB265-HB273 - renumber before applying';
  END IF;
  IF to_regclass('hbh.payment_plans') IS NOT NULL THEN
    RAISE EXCEPTION 'hbh.payment_plans already exists - somebody built this elsewhere';
  END IF;
END
$guard$;

-- =====================================================================
-- PP-D1 · payment_plans
-- =====================================================================
CREATE TABLE hbh.payment_plans (
  plan_id        integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  center_id      integer NOT NULL REFERENCES hbh.centers (center_id),
  code           text    NOT NULL,
  name_ar        text    NOT NULL,
  kind           text    NOT NULL,
  deposit_pct    numeric(5,2),
  status         text    NOT NULL DEFAULT 'DRAFT',
  is_default_flg boolean NOT NULL DEFAULT false,
  active_flg     boolean NOT NULL DEFAULT true,
  deleted_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at     timestamptz,
  updated_by     text,
  CONSTRAINT ck_pplan_kind   CHECK (kind IN ('FULL', 'DEPOSIT_PERCENT')),
  CONSTRAINT ck_pplan_status CHECK (status IN ('DRAFT', 'ACTIVE', 'RETIRED')),
  -- FULL has no deposit; a deposit of 0 or 100 is FULL wearing a costume.
  CONSTRAINT ck_pplan_deposit CHECK (
    (kind = 'FULL' AND deposit_pct IS NULL)
    OR (kind = 'DEPOSIT_PERCENT' AND deposit_pct > 0 AND deposit_pct < 100))
);

CREATE UNIQUE INDEX uix_pplan_code ON hbh.payment_plans (center_id, code) WHERE active_flg;
-- PP-AC-07: two defaults for one centre are refused by name.
CREATE UNIQUE INDEX uix_payment_plans_default ON hbh.payment_plans (center_id) WHERE is_default_flg;

CREATE TABLE hbh.payment_plan_installments (
  plan_installment_id integer  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  center_id           integer  NOT NULL REFERENCES hbh.centers (center_id),
  plan_id             integer  NOT NULL REFERENCES hbh.payment_plans (plan_id),
  seq                 smallint NOT NULL,
  amount_kind         text     NOT NULL,
  amount_value        numeric(12,2) NOT NULL,
  due_kind            text     NOT NULL,
  due_value           integer  NOT NULL,
  active_flg          boolean  NOT NULL DEFAULT true,
  deleted_at          timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  created_by          text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at          timestamptz,
  updated_by          text,
  CONSTRAINT ck_ppi_seq         CHECK (seq >= 1),
  CONSTRAINT ck_ppi_amount_kind CHECK (amount_kind IN ('AMOUNT', 'PERCENT')),
  CONSTRAINT ck_ppi_amount      CHECK (amount_value > 0 AND (amount_kind = 'AMOUNT' OR amount_value <= 100)),
  CONSTRAINT ck_ppi_due_kind    CHECK (due_kind IN ('DAYS_AFTER_ISSUE', 'AFTER_SESSIONS')),
  CONSTRAINT ck_ppi_due_value   CHECK (due_value >= 0 AND (due_kind = 'DAYS_AFTER_ISSUE' OR due_value >= 1))
);

CREATE UNIQUE INDEX uix_ppi_seq  ON hbh.payment_plan_installments (plan_id, seq) WHERE active_flg;
CREATE INDEX ix_ppi_center       ON hbh.payment_plan_installments (center_id);

-- The row's centre is its plan's centre. A template row pointing at
-- another centre's plan would be read by one centre and govern another.
CREATE OR REPLACE FUNCTION hbh.trg_ppi_center()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  SELECT p.center_id INTO NEW.center_id FROM hbh.payment_plans p WHERE p.plan_id = NEW.plan_id;
  RETURN NEW;
END
$$;

CREATE TRIGGER trg_ppi_center
  BEFORE INSERT OR UPDATE OF plan_id, center_id ON hbh.payment_plan_installments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_ppi_center();

-- ---------------------------------------------------------------------
-- The plan's state machine
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.legal_payment_plan_transition(p_from text, p_to text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_from IS DISTINCT FROM p_to AND (p_from, p_to) IN (
    ('DRAFT',  'ACTIVE'),
    ('DRAFT',  'RETIRED'),
    ('ACTIVE', 'RETIRED')
  )
$$;

-- Is this plan complete enough to issue on? One place answers it, and
-- both activation and issue_invoice ask it.
CREATE OR REPLACE FUNCTION hbh.payment_plan_problem(p_plan_id integer)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_plan hbh.payment_plans%ROWTYPE;
  l_rows integer;
  l_pct  numeric;
BEGIN
  SELECT * INTO l_plan FROM hbh.payment_plans WHERE plan_id = p_plan_id;
  SELECT count(*), coalesce(sum(amount_value) FILTER (WHERE amount_kind = 'PERCENT'), 0)
    INTO l_rows, l_pct
  FROM hbh.payment_plan_installments
  WHERE plan_id = p_plan_id AND active_flg;

  IF l_plan.kind = 'FULL' AND l_rows > 0 THEN
    RETURN 'a FULL plan is paid at once and cannot carry instalments';
  ELSIF l_plan.kind = 'DEPOSIT_PERCENT' AND l_rows = 0 THEN
    RETURN 'a deposit plan needs at least one instalment after the deposit';
  ELSIF l_plan.kind = 'DEPOSIT_PERCENT' AND l_pct > 100 - l_plan.deposit_pct THEN
    RETURN format('instalment percentages (%s) exceed 100 minus the deposit (%s)',
                  l_pct, 100 - l_plan.deposit_pct);
  END IF;
  RETURN NULL;
END
$$;

CREATE OR REPLACE FUNCTION hbh.trg_payment_plan_rules()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_problem text;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.status IS DISTINCT FROM OLD.status
       AND NOT hbh.legal_payment_plan_transition(OLD.status, NEW.status) THEN
      RAISE EXCEPTION 'payment plan % cannot go from % to %', OLD.plan_id, OLD.status, NEW.status
        USING ERRCODE = 'HB265';
    END IF;
    -- A template in use is frozen: an invoice issued yesterday and one
    -- issued today on "the same plan" must mean the same thing.
    IF OLD.status <> 'DRAFT'
       AND (NEW.kind, NEW.deposit_pct, NEW.center_id) IS DISTINCT FROM
           (OLD.kind, OLD.deposit_pct, OLD.center_id) THEN
      RAISE EXCEPTION 'payment plan % is % - its terms can no longer change', OLD.plan_id, OLD.status
        USING ERRCODE = 'HB266';
    END IF;
    IF OLD.is_default_flg AND NEW.status = 'RETIRED' THEN
      RAISE EXCEPTION 'payment plan % is the default - choose another default before retiring it', OLD.plan_id
        USING ERRCODE = 'HB266';
    END IF;
  END IF;

  IF NEW.is_default_flg AND (NEW.status <> 'ACTIVE' OR NOT NEW.active_flg) THEN
    RAISE EXCEPTION 'only an active plan can be the default' USING ERRCODE = 'HB266';
  END IF;

  IF NEW.status = 'ACTIVE' AND (TG_OP = 'INSERT' OR OLD.status <> 'ACTIVE') THEN
    -- On INSERT the plan has no rows yet, so only FULL can be born ACTIVE.
    IF TG_OP = 'INSERT' AND NEW.kind <> 'FULL' THEN
      RAISE EXCEPTION 'a deposit plan is created as DRAFT, given its instalments, then activated'
        USING ERRCODE = 'HB267';
    END IF;
    IF TG_OP = 'UPDATE' THEN
      l_problem := hbh.payment_plan_problem(NEW.plan_id);
      IF l_problem IS NOT NULL THEN
        RAISE EXCEPTION 'payment plan % cannot be activated: %', NEW.plan_id, l_problem
          USING ERRCODE = 'HB267';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER trg_payment_plans_rules
  BEFORE INSERT OR UPDATE ON hbh.payment_plans
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_payment_plan_rules();

CREATE OR REPLACE FUNCTION hbh.trg_ppi_frozen()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_status text;
BEGIN
  SELECT p.status INTO l_status FROM hbh.payment_plans p
  WHERE p.plan_id = coalesce(NEW.plan_id, OLD.plan_id);
  IF l_status IS DISTINCT FROM 'DRAFT' THEN
    RAISE EXCEPTION 'payment plan % is % - its instalments can no longer change',
                    coalesce(NEW.plan_id, OLD.plan_id), l_status
      USING ERRCODE = 'HB266';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER trg_ppi_frozen
  BEFORE INSERT OR UPDATE OR DELETE ON hbh.payment_plan_installments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_ppi_frozen();

CREATE TRIGGER trg_pplan_touch BEFORE UPDATE ON hbh.payment_plans
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_pplan_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.payment_plans
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('plan_id');
CREATE TRIGGER trg_ppi_touch BEFORE UPDATE ON hbh.payment_plan_installments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_ppi_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.payment_plan_installments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('plan_installment_id');

-- ---------------------------------------------------------------------
-- Access. Money, not catalogue: BILLING.VIEW reads (reception picks a
-- plan when selling), BILLING.MANAGE writes. No DELETE grant anywhere.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.payment_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.payment_plan_installments ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_pplan_select ON hbh.payment_plans FOR SELECT TO hbh_app
  USING ((SELECT hbh.current_center_id() IS NOT NULL)
         AND center_id = (SELECT hbh.current_center_id())
         AND active_flg
         AND ((SELECT hbh.has_permission('BILLING.VIEW')) OR (SELECT hbh.has_permission('BILLING.MANAGE'))));
CREATE POLICY p_pplan_insert ON hbh.payment_plans FOR INSERT TO hbh_app
  WITH CHECK ((SELECT hbh.current_center_id() IS NOT NULL)
              AND center_id = (SELECT hbh.current_center_id())
              AND (SELECT hbh.has_permission('BILLING.MANAGE')));
CREATE POLICY p_pplan_update ON hbh.payment_plans FOR UPDATE TO hbh_app
  USING ((SELECT hbh.current_center_id() IS NOT NULL)
         AND center_id = (SELECT hbh.current_center_id())
         AND (SELECT hbh.has_permission('BILLING.MANAGE')))
  WITH CHECK (center_id = (SELECT hbh.current_center_id()));

CREATE POLICY p_ppi_select ON hbh.payment_plan_installments FOR SELECT TO hbh_app
  USING ((SELECT hbh.current_center_id() IS NOT NULL)
         AND center_id = (SELECT hbh.current_center_id())
         AND active_flg
         AND ((SELECT hbh.has_permission('BILLING.VIEW')) OR (SELECT hbh.has_permission('BILLING.MANAGE'))));
CREATE POLICY p_ppi_insert ON hbh.payment_plan_installments FOR INSERT TO hbh_app
  WITH CHECK ((SELECT hbh.current_center_id() IS NOT NULL)
              AND center_id = (SELECT hbh.current_center_id())
              AND (SELECT hbh.has_permission('BILLING.MANAGE')));
CREATE POLICY p_ppi_update ON hbh.payment_plan_installments FOR UPDATE TO hbh_app
  USING ((SELECT hbh.current_center_id() IS NOT NULL)
         AND center_id = (SELECT hbh.current_center_id())
         AND (SELECT hbh.has_permission('BILLING.MANAGE')))
  WITH CHECK (center_id = (SELECT hbh.current_center_id()));

GRANT SELECT, INSERT, UPDATE ON hbh.payment_plans TO hbh_app;
GRANT SELECT, INSERT, UPDATE ON hbh.payment_plan_installments TO hbh_app;
GRANT USAGE, SELECT ON SEQUENCE hbh.payment_plans_plan_id_seq TO hbh_app;
GRANT USAGE, SELECT ON SEQUENCE hbh.payment_plan_installments_plan_installment_id_seq TO hbh_app;

-- =====================================================================
-- PP-D4 · which plan an invoice and a subscription were sold on
-- =====================================================================
ALTER TABLE hbh.invoices
  ADD COLUMN payment_plan_id              integer REFERENCES hbh.payment_plans (plan_id),
  ADD COLUMN schedule_override_reason_ar  text,
  ADD COLUMN schedule_overridden_by       integer REFERENCES hbh.users (user_id),
  ADD COLUMN schedule_overridden_at       timestamptz;
CREATE INDEX ix_inv_payment_plan    ON hbh.invoices (payment_plan_id);
CREATE INDEX ix_inv_schedule_by     ON hbh.invoices (schedule_overridden_by);

ALTER TABLE hbh.child_packages
  ADD COLUMN payment_plan_id integer REFERENCES hbh.payment_plans (plan_id);
CREATE INDEX ix_cpkg_payment_plan ON hbh.child_packages (payment_plan_id);

-- =====================================================================
-- PP-D3 · invoice_installments
-- =====================================================================
CREATE TABLE hbh.invoice_installments (
  installment_id     integer  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  center_id          integer  NOT NULL REFERENCES hbh.centers (center_id),
  invoice_id         integer  NOT NULL REFERENCES hbh.invoices (invoice_id),
  seq                smallint NOT NULL,
  amount             numeric(12,2) NOT NULL,
  due_date           date,
  due_after_sessions smallint,
  status             text     NOT NULL,
  paid_at            timestamptz,
  active_flg         boolean  NOT NULL DEFAULT true,
  deleted_at         timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  created_by         text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at         timestamptz,
  updated_by         text,
  CONSTRAINT ck_inst_seq    CHECK (seq >= 1),
  CONSTRAINT ck_inst_amount CHECK (amount > 0),
  CONSTRAINT ck_inst_due    CHECK (num_nonnulls(due_date, due_after_sessions) = 1),
  CONSTRAINT ck_inst_after  CHECK (due_after_sessions IS NULL OR due_after_sessions >= 1),
  CONSTRAINT ck_inst_status CHECK (status IN ('PENDING', 'DUE', 'PAID', 'OVERDUE', 'CANCELLED', 'SUPERSEDED')),
  CONSTRAINT ck_inst_paid   CHECK ((status = 'PAID') = (paid_at IS NOT NULL))
);

CREATE UNIQUE INDEX uix_inst_seq ON hbh.invoice_installments (invoice_id, seq) WHERE active_flg;
CREATE INDEX ix_inst_center      ON hbh.invoice_installments (center_id);
CREATE INDEX ix_inst_open        ON hbh.invoice_installments (center_id, status, due_date)
  WHERE active_flg AND status IN ('PENDING', 'DUE', 'OVERDUE');

CREATE OR REPLACE FUNCTION hbh.legal_installment_transition(p_from text, p_to text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_from IS DISTINCT FROM p_to AND (p_from, p_to) IN (
    ('PENDING', 'DUE'),
    ('PENDING', 'PAID'),
    ('DUE',     'PAID'),
    ('DUE',     'OVERDUE'),
    ('OVERDUE', 'PAID'),
    -- Money leaving: payments are INSERT-only for hbh_app, but the owner
    -- can deactivate one, and the schedule must follow the money back
    -- rather than refuse the correction.
    ('PAID',    'PENDING'),
    ('PAID',    'DUE'),
    ('PENDING', 'CANCELLED'), ('DUE', 'CANCELLED'), ('OVERDUE', 'CANCELLED'),
    ('PENDING', 'SUPERSEDED'), ('DUE', 'SUPERSEDED'), ('OVERDUE', 'SUPERSEDED')
  )
$$;

CREATE TABLE hbh.invoice_installment_status_history (
  history_id     bigint  GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  center_id      integer NOT NULL REFERENCES hbh.centers (center_id),
  installment_id integer NOT NULL REFERENCES hbh.invoice_installments (installment_id),
  from_status    text,
  to_status      text    NOT NULL,
  reason         text,
  changed_by     text        NOT NULL DEFAULT hbh.current_app_user(),
  changed_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_iish_installment ON hbh.invoice_installment_status_history (installment_id);
CREATE INDEX ix_iish_center      ON hbh.invoice_installment_status_history (center_id);

CREATE TRIGGER trg_iish_append_only
  BEFORE UPDATE OR DELETE ON hbh.invoice_installment_status_history
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_append_only();

INSERT INTO hbh.convention_exemptions (table_name, rule_code, reason) VALUES
  ('invoice_installment_status_history', 'AUDIT_COLUMNS',
   'An append-only record of one transition. changed_by and changed_at are its attribution; a row here is never edited.'),
  ('invoice_installment_status_history', 'SOFT_DELETE',
   'Append-only by trigger. A flag that hid a transition would be a way to rewrite what a family was asked to pay and when.');

CREATE OR REPLACE FUNCTION hbh.trg_installment_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status
     AND NOT hbh.legal_installment_transition(OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'instalment % cannot go from % to %', OLD.installment_id, OLD.status, NEW.status
      USING ERRCODE = 'HB269';
  END IF;
  IF TG_OP = 'UPDATE' AND (NEW.invoice_id, NEW.seq, NEW.amount, NEW.center_id,
                           NEW.due_date, NEW.due_after_sessions)
                          IS DISTINCT FROM (OLD.invoice_id, OLD.seq, OLD.amount, OLD.center_id,
                                            OLD.due_date, OLD.due_after_sessions) THEN
    -- An instalment's amount and due date are what the family was told.
    -- Changing either is a new schedule (override_installment_schedule),
    -- not an edit.
    RAISE EXCEPTION 'instalment % cannot be rewritten - supersede it', OLD.installment_id
      USING ERRCODE = 'HB269';
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER trg_inst_status
  BEFORE UPDATE ON hbh.invoice_installments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_installment_status();

CREATE OR REPLACE FUNCTION hbh.trg_installment_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO hbh.invoice_installment_status_history (center_id, installment_id, from_status, to_status)
    VALUES (NEW.center_id, NEW.installment_id, NULL, NEW.status);
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO hbh.invoice_installment_status_history (center_id, installment_id, from_status, to_status)
    VALUES (NEW.center_id, NEW.installment_id, OLD.status, NEW.status);
  END IF;
  RETURN NULL;
END
$$;

CREATE TRIGGER trg_inst_history
  AFTER INSERT OR UPDATE ON hbh.invoice_installments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_installment_history();

CREATE TRIGGER trg_inst_touch BEFORE UPDATE ON hbh.invoice_installments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_inst_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.invoice_installments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('installment_id');

-- ---------------------------------------------------------------------
-- The sum rule. Checked at COMMIT, not per row: a schedule is written
-- several rows at a time and is only whole at the end. Raised as 23514
-- with the constraint's name, because a violation is not the caller's
-- mistake - every writer of this table is in this schema.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.check_installments_total(p_invoice_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_inv hbh.invoices%ROWTYPE;
  l_n   integer;
  l_sum numeric;
BEGIN
  SELECT * INTO l_inv FROM hbh.invoices WHERE invoice_id = p_invoice_id;
  IF NOT FOUND OR l_inv.status IN ('DRAFT', 'CANCELLED') THEN
    RETURN;
  END IF;
  SELECT count(*), coalesce(sum(amount), 0) INTO l_n, l_sum
  FROM hbh.invoice_installments
  WHERE invoice_id = p_invoice_id AND active_flg AND status NOT IN ('SUPERSEDED', 'CANCELLED');
  -- An invoice from before 0142 has no schedule, and that is allowed.
  IF l_n > 0 AND l_sum <> l_inv.total_amt THEN
    RAISE EXCEPTION 'the instalments of invoice % add up to %, and its total is %',
                    p_invoice_id, l_sum, l_inv.total_amt
      USING ERRCODE = '23514', CONSTRAINT = 'ck_invoice_installments_total';
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION hbh.trg_installments_total()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  PERFORM hbh.check_installments_total(NEW.invoice_id);
  RETURN NULL;
END
$$;

CREATE CONSTRAINT TRIGGER trg_inst_total
  AFTER INSERT OR UPDATE ON hbh.invoice_installments
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_installments_total();

-- And from the other side: an issued invoice whose total moved.
CREATE CONSTRAINT TRIGGER trg_inv_installments_total
  AFTER UPDATE OF total_amt, status ON hbh.invoices
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_installments_total();

-- ---------------------------------------------------------------------
-- Visible to whoever can see the invoice, on the invoice's own terms.
-- No write grant: only issue_invoice, the payment trigger and the
-- override write here.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.invoice_installments ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.invoice_installment_status_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_inst_select ON hbh.invoice_installments FOR SELECT TO hbh_app
  USING ((SELECT hbh.current_center_id() IS NOT NULL)
         AND center_id = (SELECT hbh.current_center_id())
         AND active_flg
         AND EXISTS (SELECT 1 FROM hbh.invoices i
                     WHERE i.invoice_id = invoice_installments.invoice_id
                       AND hbh.can_access_child(i.child_id)
                       AND ((SELECT hbh.has_permission('BILLING.VIEW')) OR i.status <> 'DRAFT')));

CREATE POLICY p_iish_select ON hbh.invoice_installment_status_history FOR SELECT TO hbh_app
  USING ((SELECT hbh.current_center_id() IS NOT NULL)
         AND center_id = (SELECT hbh.current_center_id())
         AND EXISTS (SELECT 1 FROM hbh.invoice_installments x
                     WHERE x.installment_id = invoice_installment_status_history.installment_id));

GRANT SELECT ON hbh.invoice_installments TO hbh_app;
GRANT SELECT ON hbh.invoice_installment_status_history TO hbh_app;
GRANT USAGE, SELECT ON SEQUENCE hbh.invoice_installments_installment_id_seq TO hbh_app;
GRANT USAGE, SELECT ON SEQUENCE hbh.invoice_installment_status_history_history_id_seq TO hbh_app;

-- =====================================================================
-- The centre's today, and where money lands
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.center_today(p_center_id integer)
RETURNS date
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT (now() AT TIME ZONE c.time_zone)::date FROM hbh.centers c WHERE c.center_id = p_center_id
$$;

-- The status an UNPAID instalment should have, from its date alone.
-- OVERDUE is not produced here: when a DUE instalment becomes late is
-- PP-03's question, still open.
CREATE OR REPLACE FUNCTION hbh.installment_unpaid_status(p_due_date date, p_today date)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN p_due_date IS NOT NULL AND p_due_date <= p_today THEN 'DUE' ELSE 'PENDING' END
$$;

-- PP-02. Payments settle instalments in seq order: the money paid so far
-- covers seq 1, then seq 2, and so on; an instalment is PAID when the
-- running total reaches its end. Derived from invoices.paid_amt every
-- time, never incremented - so a deactivated payment walks it back.
-- Internal: no grant. Called by the payment trigger and the override.
CREATE OR REPLACE FUNCTION hbh.settle_installments(p_invoice_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_paid  numeric;
  l_today date;
  l_run   numeric := 0;
  r       record;
  l_want  text;
BEGIN
  SELECT i.paid_amt, hbh.center_today(i.center_id) INTO l_paid, l_today
  FROM hbh.invoices i WHERE i.invoice_id = p_invoice_id;
  IF NOT FOUND THEN RETURN; END IF;

  FOR r IN
    SELECT x.installment_id, x.amount, x.status, x.due_date
    FROM   hbh.invoice_installments x
    WHERE  x.invoice_id = p_invoice_id AND x.active_flg
      AND  x.status NOT IN ('SUPERSEDED', 'CANCELLED')
    ORDER  BY x.seq
    FOR UPDATE
  LOOP
    l_run := l_run + r.amount;
    IF l_run <= l_paid THEN
      l_want := 'PAID';
    ELSIF r.status = 'PAID' THEN
      l_want := hbh.installment_unpaid_status(r.due_date, l_today);
    ELSE
      l_want := r.status;     -- unpaid stays as the calendar left it
    END IF;

    IF l_want IS DISTINCT FROM r.status THEN
      UPDATE hbh.invoice_installments
         SET status  = l_want,
             paid_at = CASE WHEN l_want = 'PAID' THEN now() END
       WHERE installment_id = r.installment_id;
    END IF;
  END LOOP;
END
$$;

CREATE OR REPLACE FUNCTION hbh.trg_payment_recalc()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  PERFORM hbh.recalc_invoice(coalesce(NEW.invoice_id, OLD.invoice_id));
  -- 0142: and the schedule follows the money, in seq order.
  PERFORM hbh.settle_installments(coalesce(NEW.invoice_id, OLD.invoice_id));
  RETURN NULL;
END
$$;

-- A cancelled invoice's unpaid instalments are cancelled with it.
CREATE OR REPLACE FUNCTION hbh.trg_invoice_cancel_installments()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  UPDATE hbh.invoice_installments
     SET status = 'CANCELLED'
   WHERE invoice_id = NEW.invoice_id AND active_flg
     AND status IN ('PENDING', 'DUE', 'OVERDUE');
  RETURN NULL;
END
$$;

CREATE TRIGGER trg_inv_cancel_installments
  AFTER UPDATE OF status ON hbh.invoices
  FOR EACH ROW WHEN (NEW.status = 'CANCELLED' AND OLD.status IS DISTINCT FROM 'CANCELLED')
  EXECUTE FUNCTION hbh.trg_invoice_cancel_installments();

-- =====================================================================
-- PP-01 · issue_invoice v2
--
-- Rebuilt from pg_get_functiondef, not from 0008: the live body carries
-- assert_same_center (0101), which the original did not. Its order is
-- kept exactly - read, same centre, permission - so no caller sees a
-- different refusal for a case it already reached.
-- =====================================================================
DROP FUNCTION hbh.issue_invoice(integer);

CREATE FUNCTION hbh.issue_invoice(p_invoice_id integer, p_payment_plan_id integer DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_inv     hbh.invoices%ROWTYPE;
  l_plan    hbh.payment_plans%ROWTYPE;
  l_plan_id integer;
  l_today   date;
  l_total   numeric(12,2);
  l_left    numeric(12,2);
  l_amt     numeric(12,2);
  l_due     date;
  l_after   smallint;
  l_seq     smallint := 1;
  l_n       integer;
  l_i       integer := 0;
  r         record;
BEGIN
  SELECT * INTO l_inv FROM hbh.invoices WHERE invoice_id = p_invoice_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such invoice %', p_invoice_id USING ERRCODE = 'HB051';
  END IF;

  PERFORM hbh.assert_same_center('invoice', p_invoice_id, l_inv.center_id);

  IF NOT hbh.has_permission('BILLING.MANAGE') THEN
    RAISE EXCEPTION 'issuing an invoice needs BILLING.MANAGE' USING ERRCODE = 'HB052';
  END IF;

  -- NEW: v1 let a second issue pass as a no-op. v2 would write a second
  -- schedule, so the state is asked now rather than assumed.
  IF l_inv.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'invoice % is % - it has already been issued or closed', p_invoice_id, l_inv.status
      USING ERRCODE = 'HB050';
  END IF;

  -- Which plan: the one asked for, else the one the draft was prepared
  -- on, else the centre's default. A plan that is not this centre's, or
  -- not there, is one answer.
  l_plan_id := coalesce(p_payment_plan_id, l_inv.payment_plan_id);
  IF l_plan_id IS NOT NULL THEN
    SELECT * INTO l_plan FROM hbh.payment_plans p
    WHERE p.plan_id = l_plan_id AND p.center_id = l_inv.center_id AND p.active_flg;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'no such payment plan %', l_plan_id USING ERRCODE = 'HB051';
    END IF;
    IF l_plan.status <> 'ACTIVE' THEN
      RAISE EXCEPTION 'payment plan % is % - only an active plan can be issued on', l_plan_id, l_plan.status
        USING ERRCODE = 'HB266';
    END IF;
  ELSE
    SELECT * INTO l_plan FROM hbh.payment_plans p
    WHERE p.center_id = l_inv.center_id AND p.is_default_flg AND p.active_flg AND p.status = 'ACTIVE';
    l_plan_id := l_plan.plan_id;      -- NULL when the centre has no default
  END IF;

  UPDATE hbh.invoices SET status = 'ISSUED', payment_plan_id = l_plan_id
   WHERE invoice_id = p_invoice_id;
  PERFORM hbh.recalc_invoice(p_invoice_id);

  SELECT total_amt INTO l_total FROM hbh.invoices WHERE invoice_id = p_invoice_id;
  IF l_total <= 0 THEN
    RETURN;                           -- nothing to schedule
  END IF;

  l_today := hbh.center_today(l_inv.center_id);
  l_left  := l_total;

  -- No plan, or FULL: one instalment, due when the invoice says.
  IF l_plan_id IS NULL OR l_plan.kind = 'FULL' THEN
    l_due := greatest(coalesce(l_inv.due_date, l_today), l_today);
    INSERT INTO hbh.invoice_installments (center_id, invoice_id, seq, amount, due_date, status)
    VALUES (l_inv.center_id, p_invoice_id, 1, l_total, l_due,
            hbh.installment_unpaid_status(l_due, l_today));
    RETURN;
  END IF;

  -- A plan in use may not be incomplete - activation checked it, and a
  -- plan is frozen once active, but the question is cheap to ask twice.
  IF hbh.payment_plan_problem(l_plan_id) IS NOT NULL THEN
    RAISE EXCEPTION 'payment plan % cannot be issued on: %', l_plan_id, hbh.payment_plan_problem(l_plan_id)
      USING ERRCODE = 'HB267';
  END IF;

  -- seq 1: the deposit, due at once.
  l_amt := round(l_total * l_plan.deposit_pct / 100, 2);
  INSERT INTO hbh.invoice_installments (center_id, invoice_id, seq, amount, due_date, status)
  VALUES (l_inv.center_id, p_invoice_id, 1, l_amt, l_today, 'DUE');
  l_left := l_left - l_amt;

  SELECT count(*) INTO l_n FROM hbh.payment_plan_installments
  WHERE plan_id = l_plan_id AND active_flg;

  FOR r IN
    SELECT * FROM hbh.payment_plan_installments
    WHERE plan_id = l_plan_id AND active_flg
    ORDER BY seq
  LOOP
    l_i   := l_i + 1;
    l_seq := l_seq + 1;
    l_amt := CASE r.amount_kind WHEN 'AMOUNT' THEN r.amount_value
                                ELSE round(l_total * r.amount_value / 100, 2) END;
    IF l_i = l_n THEN
      l_amt := l_left;                -- the last carries the remainder
    END IF;
    IF l_amt <= 0 OR l_amt > l_left THEN
      RAISE EXCEPTION 'payment plan % asks for more than invoice % totals (%)', l_plan_id, p_invoice_id, l_total
        USING ERRCODE = 'HB268';
    END IF;

    IF r.due_kind = 'DAYS_AFTER_ISSUE' THEN
      l_due := l_today + r.due_value; l_after := NULL;
    ELSE
      l_due := NULL; l_after := r.due_value;
    END IF;

    INSERT INTO hbh.invoice_installments (center_id, invoice_id, seq, amount, due_date, due_after_sessions, status)
    VALUES (l_inv.center_id, p_invoice_id, l_seq, l_amt, l_due, l_after,
            hbh.installment_unpaid_status(l_due, l_today));
    l_left := l_left - l_amt;
  END LOOP;
END
$$;

GRANT EXECUTE ON FUNCTION hbh.issue_invoice(integer, integer) TO hbh_app;

-- =====================================================================
-- PP-04 · override_installment_schedule (§17.4)
--
-- p_schedule: [{"amount": 500, "due_date": "2026-10-01"},
--              {"amount": 500, "due_after_sessions": 6}, ...]
--
-- Every unpaid instalment becomes SUPERSEDED; the entries become new
-- instalments after the highest seq; their sum must be exactly what is
-- still owed on the schedule (total minus the PAID instalments). PAID
-- rows are never touched. The reason, the person and the moment are
-- stamped on the invoice, and every row change is in the history.
--
-- Order: permission, then the row, then its state, then the input.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.override_installment_schedule(
  p_invoice_id integer, p_schedule jsonb, p_reason text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_center integer := hbh.current_center_id();
  l_inv    hbh.invoices%ROWTYPE;
  l_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  l_owed   numeric(12,2);
  l_sum    numeric(12,2) := 0;
  l_seq    smallint;
  l_today  date;
  l_amt    numeric(12,2);
  l_due    date;
  l_after  smallint;
  e        jsonb;
  l_n      integer := 0;
BEGIN
  IF l_center IS NULL OR NOT hbh.has_permission('BILLING.SCHEDULE_OVERRIDE') THEN
    RAISE EXCEPTION 'overriding a payment schedule needs BILLING.SCHEDULE_OVERRIDE' USING ERRCODE = 'HB270';
  END IF;

  SELECT * INTO l_inv FROM hbh.invoices i
  WHERE i.invoice_id = p_invoice_id AND i.center_id = l_center AND i.active_flg
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such invoice %', p_invoice_id USING ERRCODE = 'HB051';
  END IF;

  IF l_inv.status NOT IN ('ISSUED', 'PARTIALLY_PAID') THEN
    RAISE EXCEPTION 'invoice % is % - only an open invoice has a schedule to override', p_invoice_id, l_inv.status
      USING ERRCODE = 'HB050';
  END IF;

  IF l_reason IS NULL THEN
    RAISE EXCEPTION 'overriding a payment schedule needs a reason' USING ERRCODE = 'HB271';
  END IF;

  IF p_schedule IS NULL OR jsonb_typeof(p_schedule) <> 'array' OR jsonb_array_length(p_schedule) = 0 THEN
    RAISE EXCEPTION 'the new schedule must be a non-empty list of instalments' USING ERRCODE = 'HB273';
  END IF;

  -- Validate every entry and total them BEFORE writing anything: this
  -- function either changes the schedule or refuses, never half of each.
  l_today := hbh.center_today(l_center);
  -- Each question is its own IF: SQL does not promise to evaluate an OR
  -- left to right, so a cast placed after its type check in one
  -- expression can still run first and raise 22P02 instead of HB273.
  FOR e IN SELECT * FROM jsonb_array_elements(p_schedule) LOOP
    l_n := l_n + 1;
    IF jsonb_typeof(e) IS DISTINCT FROM 'object'
       OR jsonb_typeof(e -> 'amount') IS DISTINCT FROM 'number' THEN
      RAISE EXCEPTION 'schedule entry % needs a numeric amount', l_n USING ERRCODE = 'HB273';
    END IF;
    IF (e ->> 'amount')::numeric <= 0 OR (e ->> 'amount')::numeric >= 10000000000 THEN
      RAISE EXCEPTION 'schedule entry % needs an amount above zero that fits an invoice', l_n USING ERRCODE = 'HB273';
    END IF;
    IF (e ? 'due_date') = (e ? 'due_after_sessions') THEN
      RAISE EXCEPTION 'schedule entry % needs exactly one of due_date or due_after_sessions', l_n
        USING ERRCODE = 'HB273';
    END IF;
    IF e ? 'due_after_sessions' THEN
      IF jsonb_typeof(e -> 'due_after_sessions') IS DISTINCT FROM 'number' THEN
        RAISE EXCEPTION 'schedule entry % needs a whole number of sessions', l_n USING ERRCODE = 'HB273';
      END IF;
      IF (e ->> 'due_after_sessions')::numeric < 1
         OR (e ->> 'due_after_sessions')::numeric > 32767
         OR (e ->> 'due_after_sessions')::numeric <> trunc((e ->> 'due_after_sessions')::numeric) THEN
        RAISE EXCEPTION 'schedule entry % needs a whole number of sessions from 1', l_n USING ERRCODE = 'HB273';
      END IF;
    ELSE
      IF jsonb_typeof(e -> 'due_date') IS DISTINCT FROM 'string'
         OR (e ->> 'due_date') !~ '^\d{4}-\d{2}-\d{2}$' THEN
        RAISE EXCEPTION 'schedule entry % needs due_date as YYYY-MM-DD', l_n USING ERRCODE = 'HB273';
      END IF;
      BEGIN
        l_due := (e ->> 'due_date')::date;
      EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
        RAISE EXCEPTION 'schedule entry % has no such date', l_n USING ERRCODE = 'HB273';
      END;
    END IF;
    IF round((e ->> 'amount')::numeric, 2) <= 0 THEN
      RAISE EXCEPTION 'schedule entry % rounds to nothing', l_n USING ERRCODE = 'HB273';
    END IF;
    l_sum := l_sum + round((e ->> 'amount')::numeric, 2);
  END LOOP;

  SELECT l_inv.total_amt - coalesce(sum(x.amount) FILTER (WHERE x.status = 'PAID'), 0),
         coalesce(max(x.seq), 0)
    INTO l_owed, l_seq
  FROM hbh.invoice_installments x
  WHERE x.invoice_id = p_invoice_id AND x.active_flg;

  IF l_sum <> l_owed THEN
    RAISE EXCEPTION 'the new schedule adds up to %, and % is still owed on invoice %', l_sum, l_owed, p_invoice_id
      USING ERRCODE = 'HB272';
  END IF;

  -- Write.
  UPDATE hbh.invoice_installments
     SET status = 'SUPERSEDED'
   WHERE invoice_id = p_invoice_id AND active_flg
     AND status IN ('PENDING', 'DUE', 'OVERDUE');

  FOR e IN SELECT * FROM jsonb_array_elements(p_schedule) LOOP
    l_seq := l_seq + 1;
    l_amt := round((e ->> 'amount')::numeric, 2);
    IF e ? 'due_date' THEN
      l_due := (e ->> 'due_date')::date; l_after := NULL;
    ELSE
      l_due := NULL; l_after := (e ->> 'due_after_sessions')::smallint;
    END IF;
    INSERT INTO hbh.invoice_installments (center_id, invoice_id, seq, amount, due_date, due_after_sessions, status)
    VALUES (l_center, p_invoice_id, l_seq, l_amt, l_due, l_after,
            hbh.installment_unpaid_status(l_due, l_today));
  END LOOP;

  UPDATE hbh.invoices
     SET schedule_override_reason_ar = l_reason,
         schedule_overridden_by      = hbh.current_user_id(),
         schedule_overridden_at      = now()
   WHERE invoice_id = p_invoice_id;

  -- Money already paid beyond the PAID rows lands on the new rows.
  PERFORM hbh.settle_installments(p_invoice_id);
  RETURN l_n;
END
$$;

GRANT EXECUTE ON FUNCTION hbh.override_installment_schedule(integer, jsonb, text) TO hbh_app;

-- =====================================================================
-- PP-03 (calendar) and PP-05 · the clock moves instalments
-- =====================================================================
INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar) VALUES
  (NULL, 'INSTALLMENT_GRACE_DAYS', '0', 'NUMBER',
   'أيام بعد تاريخ استحقاق القسط قبل أن يُعلَّم متأخّرًا (OD-33 · 11 §17.5). صفر = متأخّر من اليوم التالي للاستحقاق.')
ON CONFLICT (center_id, param_code) DO NOTHING;

ALTER TABLE hbh.notifications DROP CONSTRAINT ck_ntf_kind;
ALTER TABLE hbh.notifications ADD CONSTRAINT ck_ntf_kind CHECK (kind_code IN (
  -- to the family
  'REPORT_PUBLISHED', 'NOTE_PUBLISHED', 'REQUEST_DECIDED', 'INVOICE_ISSUED',
  'APPOINTMENT_CANCELLED', 'SESSION_STARTED', 'ASSESSMENT_PUBLISHED',
  'APPOINTMENT_BOOKED', 'APPOINTMENT_RESCHEDULED', 'APPOINTMENT_REMINDER',
  'INSTALLMENT_DUE', 'INSTALLMENT_OVERDUE',
  -- to the centre's own people
  'STAFF_CHILD_ASSIGNED', 'STAFF_APPOINTMENT_BOOKED', 'STAFF_APPOINTMENT_CANCELLED',
  'STAFF_ENROLMENT_NEW', 'STAFF_REQUEST_NEW', 'STAFF_PLAN_APPROVED',
  'STAFF_INSTALLMENT_OVERDUE'
));

-- Internal: no grant. Called by run_maintenance, which has no identity -
-- so every centre-scoped question here is asked of the instalment's own
-- centre, never of current_center_id(). notify_role would be wrong for
-- exactly that reason: with no identity it addresses the role in EVERY
-- centre.
--
-- Once per instalment: a notice is written on the transition, and each
-- transition happens once. An instalment that was never seen DUE (the
-- job did not run on its date) goes PENDING -> DUE -> OVERDUE in one
-- pass, as two statements, and the family is told once - that it is late.
CREATE OR REPLACE FUNCTION hbh.mark_installment_dues()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  r        record;
  l_today  date;
  l_grace  integer;
  l_late   boolean;
  l_body   text;
  l_staff  integer[];
  l_n      integer := 0;
BEGIN
  FOR r IN
    SELECT x.installment_id, x.center_id, x.status, x.due_date, x.amount, x.seq,
           i.invoice_id, i.invoice_no, i.child_id, i.currency_code
    FROM   hbh.invoice_installments x
    JOIN   hbh.invoices i ON i.invoice_id = x.invoice_id
    WHERE  x.active_flg AND x.status IN ('PENDING', 'DUE') AND x.due_date IS NOT NULL
      AND  i.active_flg AND i.status IN ('ISSUED', 'PARTIALLY_PAID')
    ORDER  BY x.center_id, x.invoice_id, x.seq
    FOR UPDATE OF x
  LOOP
    l_today := hbh.center_today(r.center_id);
    IF r.due_date > l_today THEN
      CONTINUE;
    END IF;
    l_grace := greatest(coalesce(hbh.param(r.center_id, 'INSTALLMENT_GRACE_DAYS', '0')::integer, 0), 0);
    l_late  := l_today > r.due_date + l_grace;
    l_body  := r.invoice_no || ' — ' || r.amount::text || ' ' || r.currency_code
               || ' — ' || to_char(r.due_date, 'YYYY-MM-DD');

    IF r.status = 'PENDING' THEN
      UPDATE hbh.invoice_installments SET status = 'DUE' WHERE installment_id = r.installment_id;
      l_n := l_n + 1;
      IF NOT l_late THEN
        PERFORM hbh.notify_guardians(r.child_id, 'INSTALLMENT_DUE', 'قسط مستحقّ',
                                     l_body, 'INVOICE', r.invoice_id);
      END IF;
    END IF;

    IF l_late THEN
      UPDATE hbh.invoice_installments SET status = 'OVERDUE' WHERE installment_id = r.installment_id;
      l_n := l_n + 1;
      PERFORM hbh.notify_guardians(r.child_id, 'INSTALLMENT_OVERDUE', 'قسط متأخّر',
                                   l_body, 'INVOICE', r.invoice_id);

      -- Who in THIS centre handles money: staff whose roles carry
      -- BILLING.MANAGE. Not a role code - a centre that renames or adds
      -- roles still reaches the right people.
      SELECT array_agg(DISTINCT u.user_id) INTO l_staff
      FROM   hbh.users u
      JOIN   hbh.user_roles ur       ON ur.user_id = u.user_id AND ur.active_flg
      JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id AND rp.active_flg
      JOIN   hbh.permissions p       ON p.permission_id = rp.permission_id
                                    AND p.code = 'BILLING.MANAGE' AND p.active_flg
      WHERE  u.center_id = r.center_id AND u.active_flg AND u.user_type = 'STAFF';

      IF l_staff IS NOT NULL THEN
        PERFORM hbh.notify_staff(l_staff, 'STAFF_INSTALLMENT_OVERDUE', 'قسط متأخّر: ' || l_body,
                                 r.child_id, 'INVOICE', r.invoice_id);
      END IF;
    END IF;
  END LOOP;
  RETURN l_n;
END
$$;

-- run_maintenance, rebuilt from pg_get_functiondef with one task added.
CREATE OR REPLACE FUNCTION hbh.run_maintenance()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'hbh', 'pg_catalog'
AS $function$
DECLARE
  l_run      bigint;
  l_expired  integer := 0;
  l_streams  integer := 0;
  l_purged   integer := 0;
  l_archived integer := 0;
  l_offers   integer := 0;
  l_remind   integer := 0;
  l_reaped   integer := 0;
  l_dues     integer := 0;
  l_keep     integer;
  l_detail   text    := '';
BEGIN
  INSERT INTO hbh.maintenance_runs DEFAULT VALUES RETURNING run_id INTO l_run;

  -- Each task in its own handler. One failing task must not stop the
  -- others, and must not vanish either.
  BEGIN
    l_expired := hbh.expire_packages();
  EXCEPTION WHEN OTHERS THEN
    l_detail := l_detail || 'expire_packages: ' || SQLSTATE || ' ' || SQLERRM || '; ';
  END;

  BEGIN
    UPDATE hbh.stream_tokens t
       SET revoked_at = now()
     WHERE t.revoked_at IS NULL
       AND t.expires_at > now()
       AND EXISTS (SELECT 1 FROM hbh.therapy_sessions s
                   WHERE s.session_id = t.session_id AND s.status <> 'IN_PROGRESS');
    GET DIAGNOSTICS l_streams = ROW_COUNT;

    UPDATE hbh.stream_views v
       SET ended_at = now()
     WHERE v.ended_at IS NULL
       AND EXISTS (SELECT 1 FROM hbh.therapy_sessions s
                   WHERE s.session_id = v.session_id AND s.status <> 'IN_PROGRESS');
  EXCEPTION WHEN OTHERS THEN
    l_detail := l_detail || 'stream cleanup: ' || SQLSTATE || ' ' || SQLERRM || '; ';
  END;

  BEGIN
    l_offers := hbh.release_expired_offers();
  EXCEPTION WHEN OTHERS THEN
    l_detail := l_detail || 'waiting offers: ' || SQLSTATE || ' ' || SQLERRM || '; ';
  END;

  -- Telemetry is deleted; the clinical audit trail is MOVED.
  BEGIN
    l_keep := hbh.param(NULL, 'REQUEST_LOG_RETENTION_DAYS', '30')::integer;
    IF l_keep > 0 THEN
      DELETE FROM hbh.request_log
       WHERE occurred_at < now() - make_interval(days => l_keep);
      GET DIAGNOSTICS l_purged = ROW_COUNT;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    l_detail := l_detail || 'request_log purge: ' || SQLSTATE || ' ' || SQLERRM || '; ';
  END;

  BEGIN
    l_archived := hbh.archive_audit();
  EXCEPTION WHEN OTHERS THEN
    l_detail := l_detail || 'audit archive: ' || SQLSTATE || ' ' || SQLERRM || '; ';
  END;

  -- ADDED BY 0094. Both of these work by the CLOCK rather than by an
  -- event, which is the whole reason they live here: run_maintenance is
  -- the only thing in this schema that does.
  BEGIN
    l_remind := hbh.queue_appointment_reminders();
  EXCEPTION WHEN OTHERS THEN
    l_detail := l_detail || 'appointment reminders: ' || SQLSTATE || ' ' || SQLERRM || '; ';
  END;

  BEGIN
    l_reaped := hbh.reap_stuck_sms();
  EXCEPTION WHEN OTHERS THEN
    l_detail := l_detail || 'sms reaper: ' || SQLSTATE || ' ' || SQLERRM || '; ';
  END;

  -- ADDED BY 0142. Instalments fall due and fall late by the calendar.
  BEGIN
    l_dues := hbh.mark_installment_dues();
  EXCEPTION WHEN OTHERS THEN
    l_detail := l_detail || 'instalment dues: ' || SQLSTATE || ' ' || SQLERRM || '; ';
  END;

  UPDATE hbh.maintenance_runs
     SET finished_at      = now(),
         packages_expired = l_expired,
         streams_closed   = l_streams,
         detail = nullif(l_detail
                    || CASE WHEN l_purged   > 0 THEN 'request_log purged: '  || l_purged   || '; ' ELSE '' END
                    || CASE WHEN l_archived > 0 THEN 'audit archived: '      || l_archived || '; ' ELSE '' END
                    || CASE WHEN l_offers   > 0 THEN 'offers released: '     || l_offers   || '; ' ELSE '' END
                    || CASE WHEN l_remind   > 0 THEN 'reminders queued: '    || l_remind   || '; ' ELSE '' END
                    || CASE WHEN l_reaped   > 0 THEN 'sms reclaimed: '       || l_reaped   || '; ' ELSE '' END
                    || CASE WHEN l_dues     > 0 THEN 'instalment moves: '    || l_dues     || '; ' ELSE '' END, '')
   WHERE run_id = l_run;

  RETURN l_run;
END
$function$;

-- =====================================================================
-- THE PROOF - structural. The behaviour (PP-AC-01..05, 07) is proved in
-- a rolled-back transaction before this file is placed, and then in the
-- acceptance suite; what can go wrong HERE is a piece that did not land.
-- =====================================================================
DO $verify$
BEGIN
  IF (SELECT count(*) FROM pg_proc WHERE proname = 'issue_invoice' AND pronamespace = 'hbh'::regnamespace) <> 1 THEN
    RAISE EXCEPTION 'issue_invoice must exist exactly once - the one-argument version is gone';
  END IF;
  IF NOT has_function_privilege('hbh_app', 'hbh.issue_invoice(integer, integer)', 'EXECUTE')
     OR NOT has_function_privilege('hbh_app', 'hbh.override_installment_schedule(integer, jsonb, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'hbh_app lost EXECUTE on issue_invoice or override_installment_schedule';
  END IF;
  IF has_function_privilege('hbh_app', 'hbh.settle_installments(integer)', 'EXECUTE')
     AND EXISTS (SELECT 1 FROM information_schema.routine_privileges
                 WHERE routine_name = 'settle_installments' AND grantee = 'hbh_app') THEN
    RAISE EXCEPTION 'settle_installments is internal and must carry no grant';
  END IF;
  IF has_table_privilege('hbh_app', 'hbh.invoice_installments', 'INSERT')
     OR has_table_privilege('hbh_app', 'hbh.invoice_installments', 'UPDATE') THEN
    RAISE EXCEPTION 'hbh_app may not write instalments directly';
  END IF;
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'hbh.trg_payment_recalc()'::regprocedure) !~ 'settle_installments' THEN
    RAISE EXCEPTION 'payments do not settle instalments';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'hbh' AND indexname = 'uix_payment_plans_default') THEN
    RAISE EXCEPTION 'the one-default index is missing';
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0142');
