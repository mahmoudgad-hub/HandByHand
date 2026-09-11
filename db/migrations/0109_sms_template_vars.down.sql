-- =====================================================================
-- 0106 down - the outbox goes back to carrying only the sentence.
--
-- THE COLUMN IS DROPPED AND THAT IS DELIBERATE. Everywhere else in this
-- schema a down migration keeps the rows, because a row records that
-- something happened and withdrawing a function does not make it untrue.
-- template_vars is the exception: it is not a record of anything, it is
-- the same information body_ar already holds, taken apart for one
-- transport. Leaving it behind would leave a column the ledger no longer
-- explains - and this project has already paid for one of those.
--
-- The WhatsApp path stops working, loudly: a sender with no variables
-- refuses the message as CONFIG and names the template. That is the
-- intended shape of this reversal, not a side effect of it.
-- =====================================================================

DROP FUNCTION IF EXISTS hbh.claim_sms(integer, text);

CREATE FUNCTION hbh.claim_sms(p_limit integer, p_worker text)
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

REVOKE ALL ON FUNCTION hbh.claim_sms(integer, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.claim_sms(integer, text) TO hbh_app;

-- The trigger loses its last argument before the function it passes it
-- to disappears, or the next notification raises for a function that
-- does not exist.
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

  SELECT g.mobile INTO l_mobile
  FROM   hbh.guardians g
  WHERE  g.user_id = NEW.user_id AND g.active_flg
  ORDER  BY g.guardian_id
  LIMIT  1;

  IF l_mobile IS NULL OR l_mobile = '' THEN
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

DROP FUNCTION IF EXISTS hbh.enqueue_sms(integer, text, text, text, text, text, bigint, text, jsonb);

CREATE FUNCTION hbh.enqueue_sms(
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
  ON CONFLICT (dedupe_key) DO NOTHING
  RETURNING sms_id INTO l_id;

  IF l_id IS NULL THEN
    SELECT sms_id INTO l_id FROM hbh.sms_outbox WHERE dedupe_key = p_dedupe_key;
  END IF;
  RETURN l_id;
END
$$;

REVOKE ALL ON FUNCTION hbh.enqueue_sms(integer, text, text, text, text, text, bigint, text) FROM PUBLIC;

ALTER TABLE hbh.sms_outbox DROP CONSTRAINT IF EXISTS ck_sms_vars_otp;
ALTER TABLE hbh.sms_outbox DROP CONSTRAINT IF EXISTS ck_sms_vars;
ALTER TABLE hbh.sms_outbox DROP COLUMN IF EXISTS template_vars;

DELETE FROM hbh.schema_migrations WHERE version = '0109';
