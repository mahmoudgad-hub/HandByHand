-- =====================================================================
-- 0115 - the outbox has an off switch, and somewhere that says it is off
--
-- NUMBER RESERVED BEFORE WRITING. 0106-0111 belong to another session in
-- this tree; 0112-0114 are mine.
--
-- NO NEW SQLSTATE, so the API does not have to go down first.
--
-- ---------------------------------------------------------------------
-- WHY
--
-- docs/architect/03-online-consultation.md lists six rules a puller must
-- follow. Five of them were already true of hbh.claim_sms and the Go
-- worker above it: SKIP LOCKED so two instances cannot take one row, an
-- attempt ceiling, a failure recorded with its class, exponential
-- backoff, and a reaper for rows left SENDING. The sixth was not:
--
--   "مفتاح إيقاف - أوّل عطل عند المزوّد لا يجب أن يحتاج إصدارًا جديدًا"
--
-- There are SMS_WORKER_SECONDS and SMS_WORKER_BATCH in the environment,
-- and both need the process restarted. On the morning a gateway starts
-- accepting messages and delivering none, or billing for each of five
-- retries, the only way to stop it is a redeploy - which is the thing
-- that rule exists to make unnecessary.
--
-- ---------------------------------------------------------------------
-- WHAT IT DOES NOT STOP, AND THAT IS ON PURPOSE
--
-- A LOGIN CODE. The OTP does not go through this queue at all: the
-- handler calls the sender inside the request that asked for it, because
-- a code has a fifteen-minute life and a parent watching a screen, and
-- record_otp_delivery writes the row AFTERWARDS as evidence. So this
-- switch stops NOTIFICATIONS - reminders, confirmations, the message
-- saying a report was published - and never stops anybody signing in.
--
-- That is the right way round. A provider fault that made sending
-- pointless would, with a switch over the login path too, lock every
-- family out of the portal to save the centre some money on texts.
--
-- ---------------------------------------------------------------------
-- WHY THE SWITCH IS GLOBAL AND NOT PER CENTRE
--
-- Every other parameter in this schema is per centre with a global
-- default, and this one deliberately is not. The thing being switched
-- off is the PROVIDER, and the provider is a property of the deployment:
-- one gateway, one account, one set of credentials in the environment. A
-- per-centre switch would be a knob that reads as if it did something it
-- cannot do.
--
-- It also keeps the claim cheap. Read per row, hbh.param would be called
-- once for every candidate the index walks, on a loop that runs every
-- five seconds - and while sending was paused it would walk the entire
-- backlog each time to find nothing. Read once, a paused queue costs one
-- parameter lookup and returns.
--
-- ---------------------------------------------------------------------
-- NOTHING IS LOST WHILE IT IS OFF
--
-- The rows are not claimed, so they are not marked SENDING, no attempt
-- is counted against SMS_MAX_ATTEMPTS, and next_attempt_at is untouched.
-- They sit PENDING and drain in order when the switch goes back. A
-- design that marked them failed instead would burn the ceiling on an
-- outage that was never the message's fault.
--
-- ---------------------------------------------------------------------
-- AND A SWITCH NOBODY CAN SEE IS A TRAP
--
-- Turned off and forgotten, this is a centre whose families quietly stop
-- being told anything - the same shape as "a cleanup that swallows its
-- failure", which is written in CLAUDE.md because it cost a cycle here.
-- v_sms_health, below, says whether sending is paused and how much is
-- waiting, next to the backup and maintenance health the operations
-- screen already reads.
--
-- IT ALSO ANSWERS A QUESTION NOTHING COULD ANSWER BEFORE: is the worker
-- running at all? It lives in the API process, and if that goroutine
-- stops the queue simply stops draining, with no error anywhere. A
-- backlog that has been DUE for longer than the reaper's own window is
-- what that looks like from the database, and is_stalled is it.
-- =====================================================================

\set ON_ERROR_STOP on

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0115') THEN
    RAISE EXCEPTION 'migration 0115 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0094') THEN
    RAISE EXCEPTION 'migration 0094 must be applied first';
  END IF;
END
$guard$;

-- ---------------------------------------------------------------------
-- The switch itself.
--
-- IT IS SEEDED HERE AND NOT IN db/seed/, FOLLOWING 0094. The other four
-- SMS parameters are inserted by the migration that built the outbox,
-- not by the reference seed, and a knob that lives somewhere else from
-- its four siblings is a knob nobody finds. The rule about seeds is
-- about statements that READ a table the seed fills; this reads nothing.
--
-- NOT ADDED TO THE editable_flg LIST in db/seed/0001_reference.sql, and
-- that is a decision rather than an oversight. The comment there draws
-- the line at parameters a screen may move, and this one silences every
-- message a centre sends. It is flipped by an operator with SQL during
-- an incident - which is what "no new release" asked for - and stays out
-- of reach of a settings page where it could be turned off by somebody
-- who did not know what it was.
-- ---------------------------------------------------------------------
INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar) VALUES
  (NULL, 'SMS_SENDING_ENABLED', 'true', 'BOOLEAN',
   'مفتاح إيقاف طابور الرسائل عند عطل المزوّد — لا يوقف رمز الدخول. الصفوف تنتظر ولا تُستهلك محاولاتها')
ON CONFLICT (center_id, param_code) DO NOTHING;

-- ---------------------------------------------------------------------
-- The claim, with the switch in front of it.
--
-- Otherwise identical to 0094 / 0109.
--
-- ABSENT MEANS ON. hbh.param's third argument is the default, and it is
-- 'true': a parameter row that has not been seeded yet must not be the
-- reason a family hears nothing. Only the exact value 'false' pauses -
-- anything else sends, and v_sms_health shows the effective state, so an
-- operator who types 'no' sees that it did not take rather than
-- believing a queue is stopped when it is not.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.claim_sms(p_limit integer, p_worker text)
RETURNS TABLE(sms_id bigint, purpose text, template_code text,
              destination text, body_ar text, template_vars jsonb,
              attempts smallint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  PERFORM hbh.assert_sms_worker();

  IF lower(btrim(coalesce(hbh.param(NULL, 'SMS_SENDING_ENABLED', 'true'), 'true'))) = 'false' THEN
    -- Zero rows. Nothing is claimed, nothing is marked SENDING, and no
    -- attempt is counted - the backlog waits exactly where it is.
    RETURN;
  END IF;

  RETURN QUERY
  WITH due AS (
    SELECT o.sms_id
    FROM   hbh.sms_outbox o
    WHERE  o.status = 'PENDING'
    AND    o.next_attempt_at <= now()
    ORDER  BY o.next_attempt_at, o.sms_id
    LIMIT  greatest(p_limit, 0)
    FOR    UPDATE SKIP LOCKED)
  UPDATE hbh.sms_outbox o
     SET status     = 'SENDING',
         attempts   = o.attempts + 1,
         claimed_at = now(),
         claimed_by = p_worker
  FROM   due
  WHERE  o.sms_id = due.sms_id
  RETURNING o.sms_id, o.purpose, o.template_code,
            o.destination, o.body_ar, o.template_vars, o.attempts;
END
$fn$;

COMMENT ON FUNCTION hbh.claim_sms(integer, text) IS
  'Claims up to p_limit due messages for one worker, or none at all while sys_params.SMS_SENDING_ENABLED is false. Claiming marks a row SENDING and counts its attempt; a paused queue touches nothing.';

REVOKE ALL ON FUNCTION hbh.claim_sms(integer, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.claim_sms(integer, text) TO hbh_app;

-- ---------------------------------------------------------------------
-- WHAT THE QUEUE LOOKS LIKE FROM OUTSIDE IT
--
-- security_invoker, like every other view in this schema: without it the
-- view runs as its owner, who bypasses RLS on every table, and an
-- operations screen would hand one centre another centre's traffic. The
-- existing p_sms_select policy then does the filtering - centre plus
-- OPS.VIEW - and no new policy is needed.
--
-- ONE THRESHOLD, NOT TWO. is_stalled reuses SMS_STUCK_MINUTES rather
-- than introducing a second parameter. Both questions are the same
-- question - "has something been waiting longer than it should" - and
-- two knobs that mean the worker is not working is one knob too many.
-- ---------------------------------------------------------------------
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
  (lower(btrim(coalesce(hbh.param(NULL, 'SMS_SENDING_ENABLED', 'true'), 'true'))) <> 'false'
   AND min(o.next_attempt_at) FILTER (WHERE o.status = 'PENDING' AND o.next_attempt_at <= now())
       < now() - make_interval(mins => hbh.param(NULL, 'SMS_STUCK_MINUTES', '10')::integer))
    AS is_stalled

FROM hbh.sms_outbox o
GROUP BY o.center_id;

COMMENT ON VIEW hbh.v_sms_health IS
  'Whether the outbox is being drained, and whether somebody turned it off. is_stalled means work has been due longer than SMS_STUCK_MINUTES while sending was enabled - which is what a stopped worker looks like from here, since it runs inside the API process and leaves no error behind when it goes.';

GRANT SELECT ON hbh.v_sms_health TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0115');
