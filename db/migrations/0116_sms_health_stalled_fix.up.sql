-- =====================================================================
-- 0116 - v_sms_health.is_stalled answers false instead of nothing
--
-- NUMBER RESERVED BEFORE WRITING. 0106-0111 belong to another session in
-- this tree; 0112-0115 are mine and this corrects 0115.
--
-- NO NEW SQLSTATE, so the API does not have to go down first.
--
-- ---------------------------------------------------------------------
-- WHAT 0115 GOT WRONG
--
-- is_stalled was built as
--
--     sending is on  AND  oldest_due_at < now() - interval
--
-- and on an idle queue there is no oldest_due_at. min() over no rows is
-- NULL, NULL < anything is UNKNOWN, and true AND UNKNOWN is UNKNOWN - so
-- the column came back NULL for the state it is asked about most of the
-- time: nothing waiting, nothing wrong.
--
-- It is the three-valued-logic trap written up in CLAUDE.md, which this
-- project paid for in verify_otp - `hash <> NULL` being UNKNOWN rather
-- than false, so the "wrong code" branch was skipped and a NULL code
-- signed somebody in. The cost here is smaller and the shape is
-- identical: a column that decides something must not have a third
-- answer.
--
-- AND THE DAMAGE IS NOT ONLY COSMETIC. Every reader now has to carry the
-- third case. Go needs a *bool instead of a bool, a screen has to choose
-- what "unknown" looks like next to "healthy" and "stalled", and the
-- obvious `IF is_stalled THEN alert` is correct today and silently wrong
-- the first time somebody writes `IF NOT is_stalled THEN ok`. An empty
-- queue is not stalled. That is a fact, and the column now says it.
--
-- The coalesce wraps the WHOLE expression rather than the min(): a
-- default timestamp inside it would be a made-up fact about when
-- something was due, and the comparison would then be true or false for
-- a reason nobody could trace.
-- =====================================================================

\set ON_ERROR_STOP on

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0116') THEN
    RAISE EXCEPTION 'migration 0116 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0115') THEN
    RAISE EXCEPTION 'migration 0115 must be applied first';
  END IF;
END
$guard$;

CREATE OR REPLACE VIEW hbh.v_sms_health
WITH (security_invoker = true) AS
SELECT
  o.center_id,

  -- The switch, read as the claim reads it, so this column cannot
  -- disagree with what the worker is actually doing.
  lower(btrim(coalesce(hbh.param(NULL, 'SMS_SENDING_ENABLED', 'true'), 'true'))) = 'false'
    AS sending_paused,

  count(*) FILTER (WHERE o.status = 'PENDING')                            AS pending_cnt,
  count(*) FILTER (WHERE o.status = 'PENDING' AND o.next_attempt_at <= now()) AS due_now_cnt,

  -- NULL here is correct and is not the same case: it means nothing is
  -- due, and inventing a timestamp for that would be inventing a fact.
  min(o.next_attempt_at) FILTER (WHERE o.status = 'PENDING' AND o.next_attempt_at <= now())
                                                                          AS oldest_due_at,

  count(*) FILTER (WHERE o.status = 'SENDING')                            AS sending_cnt,
  count(*) FILTER (WHERE o.status = 'SENDING'
                     AND o.claimed_at < now() - make_interval(
                           mins => hbh.param(NULL, 'SMS_STUCK_MINUTES', '10')::integer))
                                                                          AS stuck_cnt,

  count(*) FILTER (WHERE o.status = 'DEAD'  AND o.failed_at > now() - interval '1 day') AS dead_24h_cnt,
  count(*) FILTER (WHERE o.status = 'SENT'  AND o.sent_at   > now() - interval '1 day') AS sent_24h_cnt,

  -- THE WORKER IS NOT DRAINING. Work has been due for longer than the
  -- reaper's own window and is still PENDING, and sending is not paused -
  -- so this is not somebody's decision, it is the loop being gone.
  --
  -- coalesce(..., false): an empty queue is not stalled, and this column
  -- has two answers, not three.
  coalesce(
    lower(btrim(coalesce(hbh.param(NULL, 'SMS_SENDING_ENABLED', 'true'), 'true'))) <> 'false'
    AND min(o.next_attempt_at) FILTER (WHERE o.status = 'PENDING' AND o.next_attempt_at <= now())
        < now() - make_interval(mins => hbh.param(NULL, 'SMS_STUCK_MINUTES', '10')::integer),
    false)
    AS is_stalled

FROM hbh.sms_outbox o
GROUP BY o.center_id;

COMMENT ON VIEW hbh.v_sms_health IS
  'Whether the outbox is being drained, and whether somebody turned it off. is_stalled means work has been due longer than SMS_STUCK_MINUTES while sending was enabled - which is what a stopped worker looks like from here, since it runs inside the API process and leaves no error behind when it goes. It is never NULL.';

GRANT SELECT ON hbh.v_sms_health TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0116');
