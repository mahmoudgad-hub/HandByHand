-- =====================================================================
-- 0114 down - the outbox stops canonicalising its own destination
--
-- The trigger goes before the functions it calls, for the reason written
-- in 0112's down: a down that drops a function a live trigger still
-- needs fails, and the whole file is one transaction, so NOTHING is
-- dropped and the rebuild quietly keeps the old definitions.
--
-- record_otp_delivery goes back to its 0096 body verbatim.
--
-- The destinations are NOT converted back. 0112's down is what returns
-- stored numbers to the national form, and it covers this column too;
-- undoing it here as well would convert twice on the way down.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TRIGGER IF EXISTS trg_sms_destination_canon ON hbh.sms_outbox;

CREATE OR REPLACE FUNCTION hbh.record_otp_delivery(
  p_center_id integer, p_mobile text, p_provider_code text,
  p_provider_msg text DEFAULT NULL, p_error_class text DEFAULT NULL,
  p_error_detail text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
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
$fn$;

REVOKE ALL ON FUNCTION hbh.record_otp_delivery(integer, text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.record_otp_delivery(integer, text, text, text, text, text) TO hbh_app;

DROP FUNCTION IF EXISTS hbh.trg_canonical_destination();
DROP FUNCTION IF EXISTS hbh.canonical_mobile_or_raw(text, text);

DELETE FROM hbh.schema_migrations WHERE version = '0114';
