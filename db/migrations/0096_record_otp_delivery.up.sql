-- =====================================================================
-- Hand By Hand (new) - migration 0096: recording a login code's delivery
-- without handing anybody a way to send one.
--
-- WHAT 0094 LEFT OPEN, and it left it open on purpose. hbh.enqueue_sms
-- is NOT granted to hbh_app: a function taking a destination and a body
-- and putting them on the send queue is, exactly, "send any text to any
-- number", which is the capability the brief refuses to build and which
-- has different abuse rules from anything in this phase. Its callers are
-- a trigger and the owner.
--
-- But the login handler DOES need to record that it handed a code to a
-- provider, and it runs as hbh_app. So it needs a way in - and the way
-- in must not be the general one.
--
-- THIS FUNCTION CANNOT SEND ANYTHING, and that is structural rather than
-- promised:
--
--   * IT TAKES NO BODY. There is no parameter for message text, so
--     there is no text to smuggle. ck_sms_body already requires body_ar
--     to be NULL for an OTP_LOGIN row, so even the owner could not put
--     one there through this path.
--   * IT WRITES A TERMINAL ROW. status is SENT or DEAD, never PENDING,
--     so nothing it creates is ever claimed by the worker. It records
--     something that has ALREADY happened; it does not ask for anything
--     to happen.
--   * IT BUILDS ITS OWN DEDUPE KEY. The caller cannot choose one, so it
--     cannot collide with, or overwrite, a notification's row.
--
-- The worst a compromised caller can do with it is write rows into
-- hbh.sms_outbox that claim codes were sent. That is a false entry in an
-- operations view - worth knowing about, and not remotely the same as
-- being able to text a stranger.
--
-- WHY THE CENTRE IS A PARAMETER. The handler has it from
-- hbh.request_otp (migration 0095) and nothing else on that connection
-- can see it: a login code is issued before there is a session, so RLS
-- is failing closed on hbh.users. Passing it in is not a trust decision
-- - a wrong centre writes a misfiled row and nothing more.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0096') THEN
    RAISE EXCEPTION 'migration 0096 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0095') THEN
    RAISE EXCEPTION 'migration 0095 must be applied first';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION hbh.record_otp_delivery(
  p_center_id     integer,
  p_mobile        text,
  p_provider_code text,
  p_provider_msg  text DEFAULT NULL,
  p_error_class   text DEFAULT NULL,
  p_error_detail  text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_id     bigint;
  l_status text;
BEGIN
  IF p_center_id IS NULL OR coalesce(p_mobile, '') = '' THEN
    RAISE EXCEPTION 'a delivery record needs a centre and a destination'
      USING ERRCODE = 'HB231';
  END IF;

  l_status := CASE WHEN coalesce(p_error_class, '') = '' THEN 'SENT' ELSE 'DEAD' END;

  INSERT INTO hbh.sms_outbox (center_id, notification_id, purpose, template_code,
                              destination, body_ar, dedupe_key, status,
                              attempts, sent_at, failed_at,
                              provider_code, provider_msg_id,
                              error_class, error_detail)
  VALUES (p_center_id, NULL, 'OTP_LOGIN', 'OTP_LOGIN',
          p_mobile, NULL,
          -- Per ATTEMPT, not per event. Unlike a notification - which
          -- must produce exactly one message however many times its
          -- trigger fires - a second code request IS a second code and
          -- genuinely is a second message. What limits them is
          -- hbh.request_otp's own RESEND_TOO_SOON window, not this key.
          'OTP:' || extract(epoch from clock_timestamp())::numeric(20,6)::text
                 || ':' || p_mobile,
          l_status,
          1,
          CASE WHEN l_status = 'SENT' THEN now() END,
          CASE WHEN l_status = 'DEAD' THEN now() END,
          p_provider_code,
          nullif(p_provider_msg, ''),
          nullif(p_error_class, ''),
          left(coalesce(p_error_detail, ''), 500))
  RETURNING sms_id INTO l_id;

  RETURN l_id;
END
$$;

REVOKE ALL ON FUNCTION hbh.record_otp_delivery(integer, text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.record_otp_delivery(integer, text, text, text, text, text) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0096');
