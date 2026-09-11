-- =====================================================================
-- 0114 - sms_outbox.destination is E.164 too
--
-- NUMBER RESERVED BEFORE WRITING. 0106-0111 belong to another session in
-- this tree; 0112 and 0113 are mine and this completes them.
--
-- NO NEW SQLSTATE, so the API does not have to go down first.
--
-- ---------------------------------------------------------------------
-- WHAT 0112 MISSED, AND WHAT FOUND IT
--
-- 0112 converted every stored mobile and put a canonicalising trigger on
-- the four tables a person types into. It did NOT put one on
-- hbh.sms_outbox - the reasoning at the time was that nothing types into
-- an outbox, so whatever is enqueued has already been through a column
-- that has one.
--
-- That is true of every path except the one that matters most. The login
-- handler passes the number THE PARENT JUST TYPED straight to
-- hbh.record_otp_delivery - it has no reason to have read it back from
-- anywhere - and that function INSERTs into sms_outbox directly rather
-- than through hbh.enqueue_sms. So within three minutes of 0112 landing
-- there were five fresh OTP_LOGIN rows holding 01XXXXXXXXX, written by
-- hbh_app, in a column the migration had just finished converting.
--
-- NOTHING BROKE, and that is the point worth writing down. E164 in Go
-- still converts the national form, so the messages went out. What had
-- come back was the SECOND REPRESENTATION - the thing 0094's own comment
-- says a phone number must never have - and it came back silently, in
-- the one table where the evidence of what was sent to whom lives.
--
-- It was caught by a schema-wide check added to p00_verify in the same
-- change as 0112, asking not "is everything E.164" but "is anything
-- still in the national form". The first question would have been
-- answered "no" by two legacy rows for ever and switched off; the second
-- named five rows by id on its first run.
--
-- ---------------------------------------------------------------------
-- WHY A TRIGGER ON THE TABLE AND NOT A FIX IN THE CALLER
--
-- Because there are two callers and the next one will be a third.
-- hbh.enqueue_sms is the front door, hbh.record_otp_delivery goes around
-- it, and both are right to: an OTP is recorded after the fact, not
-- queued for later. A rule about what may be in a column belongs on the
-- column.
--
-- ---------------------------------------------------------------------
-- WHY THIS ONE IS LENIENT WHERE trg_canonical_mobile IS NOT
--
-- A guardian's row is written by a person who can be told to fix it. An
-- outbox row is written in the middle of somebody else's transaction -
-- an appointment confirmation, a report published - and raising here
-- would fail THAT, for a business reason that has nothing to do with it,
-- because a number recorded in 2026 is seven digits long.
--
-- So an unconvertible destination is kept exactly as it was and travels
-- on to the sender, which refuses it as PERMANENT and records why. That
-- is precisely what happened before this migration, so nothing is made
-- worse; what changes is that a number that CAN be canonicalised is.
--
-- The exception handler names the two codes it expects rather than being
-- a WHEN OTHERS around the body - the lesson audit_attempt paid for.
-- =====================================================================

\set ON_ERROR_STOP on

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0114') THEN
    RAISE EXCEPTION 'migration 0114 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0112') THEN
    RAISE EXCEPTION 'migration 0112 must be applied first';
  END IF;
END
$guard$;

-- The lenient form, so the trigger below and record_otp_delivery share
-- one definition of "canonical if it can be, untouched if it cannot".
-- Two copies of that rule would differ the first time one was edited.
CREATE OR REPLACE FUNCTION hbh.canonical_mobile_or_raw(p_raw text, p_country text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  RETURN coalesce(hbh.canonical_mobile(p_raw, p_country), p_raw);
EXCEPTION
  WHEN SQLSTATE 'HB170' OR SQLSTATE 'HB173' THEN
    RETURN p_raw;
END
$fn$;

COMMENT ON FUNCTION hbh.canonical_mobile_or_raw(text, text) IS
  'Canonicalises a number when it can be and returns it unchanged when it cannot. For paths where a bad number must not fail somebody else''s transaction - the outbox. Everywhere a person is typing, use hbh.canonical_mobile and let it refuse.';

REVOKE ALL ON FUNCTION hbh.canonical_mobile_or_raw(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.canonical_mobile_or_raw(text, text) TO hbh_app;

CREATE OR REPLACE FUNCTION hbh.trg_canonical_destination()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  cc text;
BEGIN
  IF NEW.destination IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT c.country_code INTO cc
    FROM hbh.centers c WHERE c.center_id = NEW.center_id;

  NEW.destination := hbh.canonical_mobile_or_raw(NEW.destination, cc);
  RETURN NEW;
END
$fn$;

COMMENT ON FUNCTION hbh.trg_canonical_destination() IS
  'Keeps hbh.sms_outbox.destination in E.164 whichever function enqueued the row. Lenient: a number it cannot convert travels on unchanged and the sender refuses it.';

DROP TRIGGER IF EXISTS trg_sms_destination_canon ON hbh.sms_outbox;
CREATE TRIGGER trg_sms_destination_canon
  BEFORE INSERT OR UPDATE OF destination ON hbh.sms_outbox
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_canonical_destination();

-- ---------------------------------------------------------------------
-- And the dedupe key is built from the same value as the column.
--
-- The trigger above fixes `destination` whatever this function passes,
-- but `dedupe_key` is composed HERE and the trigger cannot reach inside
-- it. Leaving it would put the national form back into the row by the
-- other door - two spellings of one number in one row, which is the
-- state this whole change exists to end.
--
-- Otherwise identical to 0096.
-- ---------------------------------------------------------------------
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
  l_dest   text;
BEGIN
  IF p_center_id IS NULL OR coalesce(p_mobile, '') = '' THEN
    RAISE EXCEPTION 'a delivery record needs a centre and a destination'
      USING ERRCODE = 'HB231';
  END IF;

  SELECT hbh.canonical_mobile_or_raw(p_mobile, c.country_code) INTO l_dest
    FROM hbh.centers c WHERE c.center_id = p_center_id;
  l_dest := coalesce(l_dest, p_mobile);

  l_status := CASE WHEN coalesce(p_error_class, '') = '' THEN 'SENT' ELSE 'DEAD' END;

  INSERT INTO hbh.sms_outbox (center_id, notification_id, purpose, template_code,
                              destination, body_ar, dedupe_key, status,
                              attempts, sent_at, failed_at,
                              provider_code, provider_msg_id,
                              error_class, error_detail)
  VALUES (p_center_id, NULL, 'OTP_LOGIN', 'OTP_LOGIN',
          l_dest, NULL,
          -- Per ATTEMPT, not per event. Unlike a notification - which
          -- must produce exactly one message however many times its
          -- trigger fires - a second code request IS a second code and
          -- genuinely is a second message. What limits them is
          -- hbh.request_otp's own RESEND_TOO_SOON window, not this key.
          'OTP:' || extract(epoch from clock_timestamp())::numeric(20,6)::text
                 || ':' || l_dest,
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

-- The rows written between 0112 and this migration.
UPDATE hbh.sms_outbox s
   SET destination = hbh.canonical_mobile(s.destination, c.country_code)
  FROM hbh.centers c
 WHERE c.center_id = s.center_id
   AND s.destination ~ '^01[0-9]{9}$';

INSERT INTO hbh.schema_migrations (version) VALUES ('0114');
