-- =====================================================================
-- Hand By Hand (new) - migration 0094: the message actually leaves.
--
-- THE API GOES FIRST. This migration adds SQLSTATEs HB230 and HB231 that
-- the transport layer has never seen, and an unrecognised code there
-- becomes a 500 - the trap 0053, 0058, 0059 and 0083 each carry the same
-- warning about.
--
-- WHAT WAS ALREADY HERE, AND WHY IT WAS NOT ENOUGH
--
-- 0015 built hbh.notifications and seven triggers that fill it. It has a
-- column called sms_pending_flg, an index the header calls "what a
-- sender polls", and - for eleven months - NO SENDER. Every row written
-- since is a message nobody was ever going to receive, and the portal
-- has no screen that reads them either. The feed is write-only at both
-- ends.
--
-- WHY THIS IS A SECOND TABLE AND NOT SIX MORE COLUMNS ON notifications
--
-- The decisive reason is not tidiness, it is that ONE-TIME CODES CANNOT
-- BE NOTIFICATION ROWS AT ALL. A notification is addressed to a
-- logged-in person's feed (hbh.notifications.user_id, RLS on
-- current_user_id). A login code is sent to somebody who is BY
-- DEFINITION not logged in, must never appear in any feed, and must
-- never be persisted in plaintext anywhere - hbh.otp_codes stores only
-- a bcrypt hash precisely so that a database dump is not a list of live
-- credentials. Putting delivery on notifications would leave OTP with
-- no delivery path, which is the one delivery path that blocks launch.
--
-- Three further reasons, each sufficient on its own:
--   * notifications has no destination. It names a USER; a text message
--     needs a NUMBER, resolved at enqueue time and frozen, because a
--     guardian who changes their mobile must not retroactively change
--     where a message already accepted by a provider was sent.
--   * notifications.read_at is written by the reader, from an HTTP
--     request, at any moment. Delivery state is written by a worker
--     holding a row lock. Two writers with unrelated cadences on one
--     row is a lock-contention bug waiting for the first busy evening.
--   * one notification row is created PER GUARDIAN, and delivery has to
--     be per guardian too - but a retry counter, a backoff clock and a
--     provider message id on a UI table make every SELECT in the portal
--     read columns that mean nothing to it.
--
-- WHAT IS REUSED UNCHANGED. hbh.notifications keeps sms_pending_flg as
-- the INTENT (set from that guardian's own SMS_NOTIFY consent, by 0015's
-- rule, which this migration does not touch) and sms_sent_at as the
-- completion stamp. This migration adds the machinery BETWEEN them. No
-- notification column changes, no policy changes, no kind is added.
--
-- THE DELIVERY GUARANTEE IS AT-LEAST-ONCE AND IS NOT CLAIMED TO BE MORE.
-- A worker that crashes after the provider accepted a message and
-- before record_sms_sent commits leaves a SENDING row, and reap_stuck_sms
-- returns it to PENDING. That is a duplicate text message. The
-- alternative - never retrying - loses messages silently, which for an
-- appointment reminder is worse. What IS guaranteed exactly once is the
-- ENQUEUE: uq_sms_outbox_dedupe makes a second outbox row for the same
-- notification impossible, so a trigger firing twice, a worker restart,
-- or a replayed transaction cannot multiply the intent.
--
-- Error classes added here:
--   HB230  not permitted to operate the delivery queue
--   HB231  the outbox row is not in a state that accepts this result
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0094') THEN
    RAISE EXCEPTION 'migration 0094 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0093') THEN
    RAISE EXCEPTION 'migration 0093 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- THE OUTBOX
-- =====================================================================
CREATE TABLE hbh.sms_outbox (
  sms_id          bigint      GENERATED ALWAYS AS IDENTITY,
  center_id       integer     NOT NULL,

  -- NULL for a login code. A code is not an event in anybody's feed.
  notification_id bigint,

  purpose         text        NOT NULL,
  template_code   text        NOT NULL,

  -- The number as this domain stores it (MOBILE_PATTERN, 01XXXXXXXXX).
  -- Conversion to whatever shape a provider wants happens at the
  -- provider boundary, in Go, and is never written back here: a second
  -- representation of a phone number in the database is a second thing
  -- to keep in step.
  destination     text        NOT NULL,

  -- NULL FOR A LOGIN CODE, and ck_sms_body makes that structural rather
  -- than a habit somebody can forget. The message a family receives is
  -- rendered from template_code at the boundary; for OTP the plaintext
  -- exists in memory for the length of one request and is written down
  -- nowhere - not here, not in a log, not in the response outside
  -- development.
  body_ar         text,

  dedupe_key      text        NOT NULL,

  status          text        NOT NULL DEFAULT 'PENDING',
  attempts        smallint    NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  claimed_at      timestamptz,
  claimed_by      text,
  sent_at         timestamptz,
  failed_at       timestamptz,

  provider_code   text,
  provider_msg_id text,
  -- TRANSIENT retries, PERMANENT does not, CONFIG means this deployment
  -- cannot send at all and a retry would fail identically.
  error_class     text,
  error_detail    text,

  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at      timestamptz,
  updated_by      text,

  CONSTRAINT pk_sms_outbox PRIMARY KEY (sms_id),
  CONSTRAINT fk_sms_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  -- ON DELETE SET NULL for the same reason 0015 gave for child_id: a
  -- documented compliance erasure must not be blocked by a delivery
  -- record, and must not leave a dangling reference either.
  CONSTRAINT fk_sms_notification FOREIGN KEY (notification_id)
    REFERENCES hbh.notifications (notification_id) ON DELETE SET NULL,

  CONSTRAINT ck_sms_purpose CHECK (purpose IN ('OTP_LOGIN','NOTIFICATION')),
  CONSTRAINT ck_sms_status  CHECK (status IN ('PENDING','SENDING','SENT','FAILED','DEAD')),
  CONSTRAINT ck_sms_class   CHECK (error_class IS NULL
                                   OR error_class IN ('TRANSIENT','PERMANENT','CONFIG')),
  -- A credential is never at rest here.
  CONSTRAINT ck_sms_body    CHECK ((purpose = 'OTP_LOGIN') = (body_ar IS NULL)),
  CONSTRAINT ck_sms_sent    CHECK ((status = 'SENT') = (sent_at IS NOT NULL)),
  CONSTRAINT ck_sms_dest    CHECK (destination <> '')
);

-- ENQUEUE-EXACTLY-ONCE. The whole idempotency claim rests on this one
-- index: a retrying trigger, a replayed transaction or a worker that
-- restarts mid-flight cannot create a second row for the same business
-- event, because the key is derived from the event and not from the
-- moment.
CREATE UNIQUE INDEX uq_sms_outbox_dedupe ON hbh.sms_outbox (dedupe_key);

CREATE INDEX ix_sms_center       ON hbh.sms_outbox (center_id, created_at DESC);
CREATE INDEX ix_sms_notification ON hbh.sms_outbox (notification_id);
-- What the worker claims, in the order it should claim it. Partial, so
-- the index stays the size of the backlog and not of the history.
CREATE INDEX ix_sms_due ON hbh.sms_outbox (next_attempt_at, sms_id)
  WHERE status = 'PENDING';
-- What the reaper looks for.
CREATE INDEX ix_sms_sending ON hbh.sms_outbox (claimed_at) WHERE status = 'SENDING';

CREATE TRIGGER trg_sms_touch BEFORE UPDATE ON hbh.sms_outbox
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

-- =====================================================================
-- WHO MAY READ IT
--
-- Nobody's family. A delivery record names a number and an event, and a
-- guardian has no operational question it answers - they already see the
-- notification itself. Centre staff holding OPS.VIEW do: "did the
-- reminder go out" is exactly their question, and 51 of the owner's
-- brief asks for it to be answerable without a new screen.
-- =====================================================================
ALTER TABLE hbh.sms_outbox ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_sms_select ON hbh.sms_outbox
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('OPS.VIEW'));

GRANT SELECT ON hbh.sms_outbox TO hbh_app;

-- =====================================================================
-- PUTTING SOMETHING IN IT
--
-- Internal. Nothing outside this schema calls it, and it takes the
-- destination as an argument rather than looking one up, because its two
-- callers resolve the number differently: a notification resolves the
-- guardian's, a login code already has the one that was typed.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.enqueue_sms(
  p_center_id       integer,
  p_purpose         text,
  p_template_code   text,
  p_destination     text,
  p_dedupe_key      text,
  p_body_ar         text    DEFAULT NULL,
  p_notification_id bigint  DEFAULT NULL,
  p_status          text    DEFAULT 'PENDING')
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_id bigint;
BEGIN
  INSERT INTO hbh.sms_outbox (center_id, notification_id, purpose, template_code,
                              destination, body_ar, dedupe_key, status,
                              sent_at)
  VALUES (p_center_id, p_notification_id, p_purpose, p_template_code,
          p_destination, p_body_ar, p_dedupe_key, p_status,
          CASE WHEN p_status = 'SENT' THEN now() END)
  -- Second time round is not an error and is not a second message. The
  -- caller gets the id of the row that already exists, which is what it
  -- would have got the first time.
  ON CONFLICT (dedupe_key) DO NOTHING
  RETURNING sms_id INTO l_id;

  IF l_id IS NULL THEN
    SELECT sms_id INTO l_id FROM hbh.sms_outbox WHERE dedupe_key = p_dedupe_key;
  END IF;
  RETURN l_id;
END
$$;

-- ---------------------------------------------------------------------
-- A NOTIFICATION WITH SMS INTENT BECOMES AN OUTBOX ROW
--
-- A trigger, for 0015's reason restated: a family is texted because
-- something HAPPENED, not because a handler remembered. Every existing
-- notify_* path is served by this one statement and none of them
-- changes.
--
-- NO CLINICAL TEXT LEAVES BY SMS. body_ar on the notification may carry
-- an invoice line or a decision note; what goes to the phone is the
-- TITLE and a sentence telling the family where to look. 0089's header
-- already states the rule for notifications; this is where it becomes
-- load-bearing, because SMS is the channel with no gate in front of it.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.trg_sms_from_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_mobile text;
  l_body   text;
BEGIN
  IF NOT NEW.sms_pending_flg THEN
    RETURN NULL;
  END IF;

  -- The guardian's number, frozen at this instant. A staff notification
  -- never reaches here: 0015 sets sms_pending_flg only from a guardian's
  -- SMS_NOTIFY consent and notify_staff leaves it false.
  SELECT g.mobile INTO l_mobile
  FROM   hbh.guardians g
  WHERE  g.user_id = NEW.user_id AND g.active_flg
  ORDER  BY g.guardian_id
  LIMIT  1;

  IF l_mobile IS NULL OR l_mobile = '' THEN
    -- 22 of the brief: a family with no usable number must not block the
    -- thing that happened. The intent is recorded as undeliverable and
    -- the report, the appointment and the invoice all stand.
    UPDATE hbh.notifications SET sms_pending_flg = false
     WHERE notification_id = NEW.notification_id;

    PERFORM hbh.enqueue_sms(
      NEW.center_id, 'NOTIFICATION', NEW.kind_code, 'UNKNOWN',
      'NTF:' || NEW.notification_id::text, NEW.title_ar,
      NEW.notification_id, 'DEAD');

    UPDATE hbh.sms_outbox
       SET error_class = 'PERMANENT',
           error_detail = 'no mobile number on file for this guardian',
           failed_at = now()
     WHERE dedupe_key = 'NTF:' || NEW.notification_id::text;
    RETURN NULL;
  END IF;

  l_body := NEW.title_ar || ' — تابع التفاصيل من بوّابة ولي الأمر.';

  PERFORM hbh.enqueue_sms(
    NEW.center_id, 'NOTIFICATION', NEW.kind_code, l_mobile,
    'NTF:' || NEW.notification_id::text, l_body, NEW.notification_id, 'PENDING');

  RETURN NULL;
END
$$;

CREATE TRIGGER trg_ntf_enqueue_sms
  AFTER INSERT ON hbh.notifications
  FOR EACH ROW WHEN (NEW.sms_pending_flg)
  EXECUTE FUNCTION hbh.trg_sms_from_notification();

-- =====================================================================
-- THE WORKER'S THREE VERBS
--
-- WHO IS ALLOWED TO CALL THEM, and the limit of it written plainly.
-- These are granted to hbh_app, exactly as hbh.run_maintenance() has
-- been since 0011, and like it they are reachable only because no HTTP
-- route calls them. That alone is a routing fact, not a control, so
-- there is a second one that IS: every function below refuses when a
-- USER identity is set on the connection. A background worker holds no
-- session, so it passes; every request serving a signed-in parent,
-- therapist or administrator is carrying an identity by the time it
-- reaches any handler, so none of them can reach the queue even if a
-- route were added by accident.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.assert_sms_worker()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF hbh.current_user_id() IS NOT NULL THEN
    RAISE EXCEPTION 'the delivery queue is not operable from a user session'
      USING ERRCODE = 'HB230';
  END IF;
END
$$;

-- claim_sms takes work and gives it away exactly once.
--
-- SKIP LOCKED is the whole of the concurrency answer: two workers
-- running the same statement at the same instant take disjoint sets,
-- and neither waits for the other. The rows are marked SENDING and the
-- CALLER COMMITS BEFORE SENDING ANYTHING - which is what makes a crash
-- recoverable rather than invisible.
CREATE OR REPLACE FUNCTION hbh.claim_sms(p_limit integer, p_worker text)
RETURNS TABLE (sms_id bigint, purpose text, template_code text,
               destination text, body_ar text, attempts smallint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  PERFORM hbh.assert_sms_worker();

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
            o.destination, o.body_ar, o.attempts;
END
$$;

CREATE OR REPLACE FUNCTION hbh.record_sms_sent(
  p_sms_id        bigint,
  p_provider_code text,
  p_provider_msg  text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_ntf bigint;
BEGIN
  PERFORM hbh.assert_sms_worker();

  UPDATE hbh.sms_outbox
     SET status          = 'SENT',
         sent_at         = now(),
         provider_code   = p_provider_code,
         provider_msg_id = p_provider_msg,
         error_class     = NULL,
         error_detail    = NULL
   WHERE sms_id = p_sms_id
     AND status = 'SENDING'
  RETURNING notification_id INTO l_ntf;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  -- The notification's own two columns are the record 0015 designed and
  -- the portal may one day read. ck_ntf_sms refuses the pair being set
  -- together, so the flag clears in the same statement.
  IF l_ntf IS NOT NULL THEN
    UPDATE hbh.notifications
       SET sms_pending_flg = false, sms_sent_at = now()
     WHERE notification_id = l_ntf;
  END IF;
  RETURN true;
END
$$;

-- A failure either comes back or it does not, and the row says which.
--
-- THE FUNCTION DECIDES, not the worker: attempt ceilings and backoff are
-- business rules and rule 2 of this project puts them here. A PERMANENT
-- or CONFIG classification is DEAD at once - retrying an invalid number
-- five times is five identical refusals and a bill for none of them.
CREATE OR REPLACE FUNCTION hbh.record_sms_failed(
  p_sms_id      bigint,
  p_error_class text,
  p_detail      text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_row    hbh.sms_outbox%ROWTYPE;
  l_max    integer;
  l_base   integer;
  l_status text;
BEGIN
  PERFORM hbh.assert_sms_worker();

  SELECT * INTO l_row FROM hbh.sms_outbox WHERE sms_id = p_sms_id FOR UPDATE;
  IF NOT FOUND OR l_row.status <> 'SENDING' THEN
    RAISE EXCEPTION 'outbox row % is not being sent', p_sms_id USING ERRCODE = 'HB231';
  END IF;

  l_max  := hbh.param(l_row.center_id, 'SMS_MAX_ATTEMPTS',    '5')::integer;
  l_base := hbh.param(l_row.center_id, 'SMS_RETRY_BASE_SECONDS', '60')::integer;

  IF p_error_class <> 'TRANSIENT' OR l_row.attempts >= l_max THEN
    l_status := 'DEAD';
  ELSE
    l_status := 'PENDING';
  END IF;

  UPDATE hbh.sms_outbox
     SET status       = l_status,
         error_class  = p_error_class,
         error_detail = left(coalesce(p_detail, ''), 500),
         failed_at    = now(),
         claimed_at   = NULL,
         claimed_by   = NULL,
         -- Exponential, and capped so a long-dead provider does not push
         -- the next try beyond the life of the thing being announced.
         next_attempt_at = now() + make_interval(
           secs => least(l_base * power(2, l_row.attempts)::integer, 3600))
   WHERE sms_id = p_sms_id;

  IF l_status = 'DEAD' AND l_row.notification_id IS NOT NULL THEN
    -- The intent is spent. Leaving the flag set would make the row
    -- eligible again for anything that ever polls the old index.
    UPDATE hbh.notifications SET sms_pending_flg = false
     WHERE notification_id = l_row.notification_id;
  END IF;

  RETURN l_status;
END
$$;

-- A worker that died holding rows. Without this they are SENDING for
-- ever and the backlog silently shrinks by however many were in flight.
CREATE OR REPLACE FUNCTION hbh.reap_stuck_sms()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_n   integer;
  l_min integer;
BEGIN
  l_min := hbh.param(NULL, 'SMS_STUCK_MINUTES', '10')::integer;

  UPDATE hbh.sms_outbox
     SET status       = 'PENDING',
         claimed_at   = NULL,
         claimed_by   = NULL,
         error_class  = 'TRANSIENT',
         error_detail = 'reclaimed after the worker stopped responding',
         next_attempt_at = now()
   WHERE status = 'SENDING'
     AND claimed_at < now() - make_interval(mins => l_min);
  GET DIAGNOSTICS l_n = ROW_COUNT;
  RETURN l_n;
END
$$;

-- =====================================================================
-- THE REMINDER
--
-- WHAT IS DELIBERATELY NOT DECIDED HERE. How many hours before a session
-- a family should be reminded is a business decision, and nobody has
-- made it: the lifecycle document (07, LC-05) asks for the mechanism and
-- names no interval, and no parameter in this schema carries one. So
-- APPOINTMENT_REMINDER_HOURS IS NOT SEEDED, and with it absent this
-- function returns 0 and sends nothing. The machinery is complete and
-- switched off by the absence of an answer, rather than switched on by
-- an interval this migration invented.
--
-- IDEMPOTENT BY THE SAME KEY AS EVERYTHING ELSE. uq_ntf_reminder makes a
-- second reminder for one appointment and one guardian impossible, so
-- running the maintenance pass twice, or twice a minute, produces one
-- message. That is what 43 of the brief asks to be demonstrated.
-- =====================================================================
CREATE UNIQUE INDEX uq_ntf_reminder
  ON hbh.notifications (link_id, user_id)
  WHERE kind_code = 'APPOINTMENT_REMINDER' AND link_kind = 'APPOINTMENT';

CREATE OR REPLACE FUNCTION hbh.queue_appointment_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_hours integer;
  l_raw   text;
  l_n     integer := 0;
  l_a     record;
BEGIN
  l_raw := hbh.param(NULL, 'APPOINTMENT_REMINDER_HOURS', '');
  IF l_raw !~ '^[0-9]+$' THEN
    -- No decision, no reminders. Not an error: a centre that has not
    -- chosen an interval has not asked for this.
    RETURN 0;
  END IF;
  l_hours := l_raw::integer;

  FOR l_a IN
    SELECT a.appointment_id, a.child_id
    FROM   hbh.appointments a
    WHERE  a.active_flg
    AND    a.status IN ('BOOKED','CONFIRMED')
    AND    a.starts_at > now()
    AND    a.starts_at <= now() + make_interval(hours => l_hours)
  LOOP
    -- notify_guardians is the one writer, so consent, the portal row and
    -- the SMS intent all follow the rules 0015 set. The unique index
    -- above is what makes a second pass a no-op; ON CONFLICT cannot be
    -- expressed through the function, so the insert is attempted and the
    -- duplicate is swallowed HERE and only here.
    BEGIN
      PERFORM hbh.notify_guardians(
        l_a.child_id, 'APPOINTMENT_REMINDER', 'تذكير بموعد قادم',
        NULL, 'APPOINTMENT', l_a.appointment_id);
      l_n := l_n + 1;
    EXCEPTION WHEN unique_violation THEN
      NULL;
    END;
  END LOOP;

  RETURN l_n;
END
$$;

-- =====================================================================
-- A CONFIRMED APPOINTMENT IS A DIFFERENT FACT FROM A BOOKED ONE
--
-- 0089 gave the family APPOINTMENT_BOOKED on insert and 0015 gave them
-- APPOINTMENT_CANCELLED on the way out. BOOKED -> CONFIRMED is the
-- transition the centre makes when the slot is certain, and it was the
-- one the owner's list names first and the schema never said.
--
-- ONE TRANSITION, NOT EVERY UPDATE. The guard is the pair of statuses,
-- so editing a note, moving a room or recalculating a price on the same
-- row says nothing to anybody.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.trg_notify_confirmed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  PERFORM hbh.notify_guardians(NEW.child_id, 'APPOINTMENT_BOOKED',
                               'تم تأكيد موعد', NULL,
                               'APPOINTMENT', NEW.appointment_id);
  RETURN NULL;
END
$$;

CREATE TRIGGER trg_appt_notify_confirmed
  AFTER UPDATE ON hbh.appointments
  FOR EACH ROW WHEN (OLD.status = 'BOOKED' AND NEW.status = 'CONFIRMED')
  EXECUTE FUNCTION hbh.trg_notify_confirmed();

-- =====================================================================
-- THE PERIODIC PASS
--
-- run_maintenance is REDEFINED rather than extended, for 0020's reason:
-- a function that grows by patching is a function nobody can read whole.
-- Everything 0025 left in it is carried forward unchanged; two tasks are
-- added at the end, each in its own handler so one failing leaves the
-- others alone and leaves its reason on the run.
-- =====================================================================
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
$$;
-- =====================================================================
-- WHAT OPERATIONS CAN ASK
--
-- 51 of the brief wants delivery diagnosable without an admin screen.
-- One view answers it, and carries no secret and no credential: the
-- destination is masked here rather than at the reader, because a view
-- that shows the whole number is a view somebody exports.
-- =====================================================================
CREATE VIEW hbh.v_sms_delivery
WITH (security_invoker = true)
AS
SELECT o.sms_id,
       o.center_id,
       o.purpose,
       o.template_code,
       '****' || right(o.destination, 4) AS destination_masked,
       o.status,
       o.attempts,
       o.next_attempt_at,
       o.provider_code,
       o.provider_msg_id,
       o.error_class,
       o.error_detail,
       o.created_at,
       o.sent_at,
       o.failed_at
FROM   hbh.sms_outbox o;

COMMENT ON VIEW hbh.v_sms_delivery IS
  'Delivery state per message, with the destination masked. Never carries a message body for a login code, because none is stored.';

GRANT SELECT ON hbh.v_sms_delivery TO hbh_app;

-- =====================================================================
-- PARAMETERS
--
-- APPOINTMENT_REMINDER_HOURS IS ABSENT ON PURPOSE - see the header of
-- queue_appointment_reminders. Absent means "no decision", which is the
-- truth, and it means no reminder is sent until somebody makes one.
-- =====================================================================
-- AND THE ONE MESSAGE THAT IS NOT RENDERED IN THE DATABASE.
--
-- Every notification body is built by trg_sms_from_notification from the
-- title the event already wrote. A login code cannot be: the code is the
-- one value in this system that must never be stored, so the text is
-- assembled in the request that issued it and then forgotten. The
-- WORDING still belongs to the centre rather than to a build, so it is a
-- parameter with two placeholders - {code} and {minutes}. The handler
-- refuses to send a template with no {code} in it.
--
-- WHAT IT SAYS AND DOES NOT SAY. The code, how long it lasts, and not to
-- pass it on. No name, no child, no centre address: SMS is the one
-- channel with no gate in front of it, and a message that names a family
-- and a children's therapy centre is a disclosure to anybody holding the
-- handset.
INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar) VALUES
  (NULL, 'SMS_MAX_ATTEMPTS',        '5',  'NUMBER', 'محاولات إرسال الرسالة قبل اعتبارها فاشلة نهائيًا'),
  (NULL, 'SMS_RETRY_BASE_SECONDS',  '60', 'NUMBER', 'أساس التأخير بين المحاولات، يتضاعف مع كل محاولة'),
  (NULL, 'SMS_STUCK_MINUTES',       '10', 'NUMBER', 'بعدها تُستعاد الرسالة العالقة من عامل توقّف'),
  (NULL, 'SMS_TEMPLATE_OTP',
   'رمز الدخول: {code} — صالح {minutes} دقيقة. لا تشاركه مع أحد.',
   'STRING', 'نصّ رسالة رمز الدخول. {code} و{minutes} يُستبدلان عند الإرسال')
ON CONFLICT (center_id, param_code) DO NOTHING;

-- =====================================================================
-- GRANTS
-- =====================================================================
REVOKE ALL ON FUNCTION hbh.enqueue_sms(integer, text, text, text, text, text, bigint, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.assert_sms_worker()                     FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.claim_sms(integer, text)                FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.record_sms_sent(bigint, text, text)     FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.record_sms_failed(bigint, text, text)   FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.reap_stuck_sms()                        FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.queue_appointment_reminders()           FROM PUBLIC;

-- enqueue_sms is NOT granted to hbh_app. Its callers are a trigger and
-- the OTP path, and both reach it as the owner; a route that could
-- enqueue an arbitrary message to an arbitrary number is precisely the
-- capability 47 of the brief refuses to build.
GRANT EXECUTE ON FUNCTION hbh.claim_sms(integer, text)              TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.record_sms_sent(bigint, text, text)   TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.record_sms_failed(bigint, text, text) TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.convention_exemptions (table_name, rule_code, reason) VALUES
  ('sms_outbox', 'SOFT_DELETE',
   'A delivery attempt happened or it did not. A hidden row would make v_sms_delivery understate what was sent to a family, which is the one question this table exists to answer. Retention is by archival, not by a flag.');

INSERT INTO hbh.schema_migrations (version) VALUES ('0094');
