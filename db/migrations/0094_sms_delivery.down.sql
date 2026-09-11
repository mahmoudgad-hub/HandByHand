-- =====================================================================
-- 0094 down - remove the delivery queue.
--
-- ORDER. The lesson written in CLAUDE.md: dropping a table takes its
-- policies and triggers with it, but a FUNCTION a surviving trigger
-- still calls cannot go first. So the triggers on tables that SURVIVE
-- (notifications, appointments) come down before their functions, and
-- sms_outbox itself takes its own trigger and policy with it.
--
-- run_maintenance is restored to the 0025 shape - the two tasks 0094
-- added are removed, everything else is carried back verbatim. Leaving
-- it calling queue_appointment_reminders after that function is gone
-- would put a permanent entry in maintenance_runs.detail on every pass.
-- =====================================================================

DROP TRIGGER IF EXISTS trg_ntf_enqueue_sms       ON hbh.notifications;
DROP TRIGGER IF EXISTS trg_appt_notify_confirmed ON hbh.appointments;

CREATE OR REPLACE FUNCTION hbh.run_maintenance()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_run      bigint;
  l_expired  integer := 0;
  l_streams  integer := 0;
  l_purged   integer := 0;
  l_archived integer := 0;
  l_offers   integer := 0;
  l_keep     integer;
  l_detail   text    := '';
BEGIN
  INSERT INTO hbh.maintenance_runs DEFAULT VALUES RETURNING run_id INTO l_run;

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

  UPDATE hbh.maintenance_runs
     SET finished_at      = now(),
         packages_expired = l_expired,
         streams_closed   = l_streams,
         detail = nullif(l_detail
                    || CASE WHEN l_purged   > 0 THEN 'request_log purged: '  || l_purged   || '; ' ELSE '' END
                    || CASE WHEN l_archived > 0 THEN 'audit archived: '      || l_archived || '; ' ELSE '' END
                    || CASE WHEN l_offers   > 0 THEN 'offers released: '     || l_offers   || '; ' ELSE '' END, '')
   WHERE run_id = l_run;

  RETURN l_run;
END
$$;

DROP VIEW IF EXISTS hbh.v_sms_delivery;

DROP FUNCTION IF EXISTS hbh.trg_sms_from_notification();
DROP FUNCTION IF EXISTS hbh.trg_notify_confirmed();
DROP FUNCTION IF EXISTS hbh.queue_appointment_reminders();
DROP FUNCTION IF EXISTS hbh.reap_stuck_sms();
DROP FUNCTION IF EXISTS hbh.record_sms_failed(bigint, text, text);
DROP FUNCTION IF EXISTS hbh.record_sms_sent(bigint, text, text);
DROP FUNCTION IF EXISTS hbh.claim_sms(integer, text);
DROP FUNCTION IF EXISTS hbh.assert_sms_worker();
DROP FUNCTION IF EXISTS hbh.enqueue_sms(integer, text, text, text, text, text, bigint, text);

-- Takes its policy, its trigger and its indexes with it.
DROP TABLE IF EXISTS hbh.sms_outbox;

DROP INDEX IF EXISTS hbh.uq_ntf_reminder;

-- The reminder rows themselves stay. They are a record that a family was
-- told something, and that does not become untrue because the mechanism
-- was withdrawn.

DELETE FROM hbh.sys_params
 WHERE center_id IS NULL
   AND param_code IN ('SMS_MAX_ATTEMPTS','SMS_RETRY_BASE_SECONDS','SMS_STUCK_MINUTES','SMS_TEMPLATE_OTP');

DELETE FROM hbh.convention_exemptions
 WHERE table_name = 'sms_outbox' AND rule_code = 'SOFT_DELETE';

DELETE FROM hbh.schema_migrations WHERE version = '0094';
