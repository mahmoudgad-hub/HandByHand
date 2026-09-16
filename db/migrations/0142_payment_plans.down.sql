-- Hand By Hand (new) - migration 0142 down: payment plans, layer A.
-- issue_invoice and trg_payment_recalc return to their bodies from
-- immediately before 0142 (pg_get_functiondef). Schedules written while
-- 0142 was up are dropped with their table - they are derived rows, and
-- the invoices and payments they were derived from are untouched.

DROP TRIGGER IF EXISTS trg_inv_cancel_installments ON hbh.invoices;
DROP TRIGGER IF EXISTS trg_inv_installments_total ON hbh.invoices;

DROP FUNCTION hbh.override_installment_schedule(integer, jsonb, text);
DROP FUNCTION hbh.issue_invoice(integer, integer);

-- The clock task and its notices go first: run_maintenance names the
-- function, and three kinds leave the list only once nothing writes them.
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

  UPDATE hbh.maintenance_runs
     SET finished_at      = now(),
         packages_expired = l_expired,
         streams_closed   = l_streams,
         detail = nullif(l_detail
                    || CASE WHEN l_purged   > 0 THEN 'request_log purged: '  || l_purged   || '; ' ELSE '' END
                    || CASE WHEN l_archived > 0 THEN 'audit archived: '      || l_archived || '; ' ELSE '' END
                    || CASE WHEN l_offers   > 0 THEN 'offers released: '     || l_offers   || '; ' ELSE '' END
                    || CASE WHEN l_remind   > 0 THEN 'reminders queued: '    || l_remind   || '; ' ELSE '' END
                    || CASE WHEN l_reaped   > 0 THEN 'sms reclaimed: '       || l_reaped   || '; ' ELSE '' END, '')
   WHERE run_id = l_run;

  RETURN l_run;
END
$function$

;

DROP FUNCTION hbh.mark_installment_dues();
DELETE FROM hbh.sys_params WHERE param_code = 'INSTALLMENT_GRACE_DAYS';

-- ck_ntf_kind KEEPS the three instalment kinds on the way down. A CHECK
-- applies to every row, deleted or not, so narrowing it would fail on
-- the first notice already sent - and those notices are messages a
-- family or colleague really received; they are not ours to erase or
-- hide to make a down script pass. A wider list that nothing writes to
-- is harmless.

CREATE OR REPLACE FUNCTION hbh.issue_invoice(p_invoice_id integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'hbh', 'pg_catalog'
AS $function$
DECLARE l_inv hbh.invoices%ROWTYPE;
BEGIN
  SELECT * INTO l_inv FROM hbh.invoices WHERE invoice_id = p_invoice_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such invoice %', p_invoice_id USING ERRCODE = 'HB051';
  END IF;

  PERFORM hbh.assert_same_center('invoice', p_invoice_id, l_inv.center_id);

  IF NOT hbh.has_permission('BILLING.MANAGE') THEN
    RAISE EXCEPTION 'issuing an invoice needs BILLING.MANAGE' USING ERRCODE = 'HB052';
  END IF;

  UPDATE hbh.invoices SET status = 'ISSUED' WHERE invoice_id = p_invoice_id;
  PERFORM hbh.recalc_invoice(p_invoice_id);
END
$function$

;

GRANT EXECUTE ON FUNCTION hbh.issue_invoice(integer) TO hbh_app;

CREATE OR REPLACE FUNCTION hbh.trg_payment_recalc()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'hbh', 'pg_catalog'
AS $function$
BEGIN
  PERFORM hbh.recalc_invoice(coalesce(NEW.invoice_id, OLD.invoice_id));
  RETURN NULL;
END
$function$

;

DROP TABLE hbh.invoice_installment_status_history;
DROP TABLE hbh.invoice_installments;
DELETE FROM hbh.convention_exemptions WHERE table_name = 'invoice_installment_status_history';

ALTER TABLE hbh.child_packages DROP COLUMN payment_plan_id;
ALTER TABLE hbh.invoices
  DROP COLUMN payment_plan_id,
  DROP COLUMN schedule_override_reason_ar,
  DROP COLUMN schedule_overridden_by,
  DROP COLUMN schedule_overridden_at;

DROP TABLE hbh.payment_plan_installments;
DROP TABLE hbh.payment_plans;

DROP FUNCTION hbh.settle_installments(integer);
DROP FUNCTION hbh.trg_invoice_cancel_installments();
DROP FUNCTION hbh.trg_installments_total();
DROP FUNCTION hbh.check_installments_total(integer);
DROP FUNCTION hbh.trg_installment_history();
DROP FUNCTION hbh.trg_installment_status();
DROP FUNCTION hbh.legal_installment_transition(text, text);
DROP FUNCTION hbh.installment_unpaid_status(date, date);
DROP FUNCTION hbh.center_today(integer);
DROP FUNCTION hbh.trg_ppi_frozen();
DROP FUNCTION hbh.trg_payment_plan_rules();
DROP FUNCTION hbh.payment_plan_problem(integer);
DROP FUNCTION hbh.legal_payment_plan_transition(text, text);
DROP FUNCTION hbh.trg_ppi_center();

DELETE FROM hbh.role_permissions WHERE permission_id IN
  (SELECT permission_id FROM hbh.permissions WHERE code = 'BILLING.SCHEDULE_OVERRIDE');
DELETE FROM hbh.permissions WHERE code = 'BILLING.SCHEDULE_OVERRIDE';

DELETE FROM hbh.schema_migrations WHERE version = '0142';
