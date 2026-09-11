-- =====================================================================
-- 0116 down - is_stalled goes back to answering NULL on an idle queue
--
-- This restores a column with three answers. It is here because a down
-- that does not undo its up leaves a database nobody can reason about,
-- not because anybody should want this one.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE OR REPLACE VIEW hbh.v_sms_health
WITH (security_invoker = true) AS
SELECT
  o.center_id,
  lower(btrim(coalesce(hbh.param(NULL, 'SMS_SENDING_ENABLED', 'true'), 'true'))) = 'false'
    AS sending_paused,
  count(*) FILTER (WHERE o.status = 'PENDING')                            AS pending_cnt,
  count(*) FILTER (WHERE o.status = 'PENDING' AND o.next_attempt_at <= now()) AS due_now_cnt,
  min(o.next_attempt_at) FILTER (WHERE o.status = 'PENDING' AND o.next_attempt_at <= now())
                                                                          AS oldest_due_at,
  count(*) FILTER (WHERE o.status = 'SENDING')                            AS sending_cnt,
  count(*) FILTER (WHERE o.status = 'SENDING'
                     AND o.claimed_at < now() - make_interval(
                           mins => hbh.param(NULL, 'SMS_STUCK_MINUTES', '10')::integer))
                                                                          AS stuck_cnt,
  count(*) FILTER (WHERE o.status = 'DEAD'  AND o.failed_at > now() - interval '1 day') AS dead_24h_cnt,
  count(*) FILTER (WHERE o.status = 'SENT'  AND o.sent_at   > now() - interval '1 day') AS sent_24h_cnt,
  (lower(btrim(coalesce(hbh.param(NULL, 'SMS_SENDING_ENABLED', 'true'), 'true'))) <> 'false'
   AND min(o.next_attempt_at) FILTER (WHERE o.status = 'PENDING' AND o.next_attempt_at <= now())
       < now() - make_interval(mins => hbh.param(NULL, 'SMS_STUCK_MINUTES', '10')::integer))
    AS is_stalled
FROM hbh.sms_outbox o
GROUP BY o.center_id;

GRANT SELECT ON hbh.v_sms_health TO hbh_app;

DELETE FROM hbh.schema_migrations WHERE version = '0116';
