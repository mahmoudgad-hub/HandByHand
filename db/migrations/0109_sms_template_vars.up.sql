-- =====================================================================
-- Hand By Hand (new) - migration 0109: the outbox carries the VALUES,
-- not only the sentence.
--
-- ON THE GUARD BELOW, WHICH NAMES 0094 AND NOT THIS FILE'S PREDECESSOR.
-- Every other migration here requires the number immediately before it.
-- This one cannot: it was written as 0106 and renumbered, because two
-- other files were claiming 0106 and 0107 at the same time from another
-- session, and the numbers between 0105 and here are still being settled
-- by whoever owns them. Guarding on a number somebody else may yet move
-- would fail for a reason that has nothing to do with this change. So it
-- names what it ACTUALLY needs - 0094, which built hbh.sms_outbox,
-- hbh.enqueue_sms and hbh.claim_sms - and that is true no matter how the
-- numbering in between resolves.
--
-- THE API GOES FIRST, for 0094's reason restated: hbh.claim_sms changes
-- its return type here, and a worker built against the old shape reads
-- one column short. The API deploys, then this.
--
-- WHAT WAS WRONG WITH WHAT WAS HERE. 0094 renders body_ar in PL/pgSQL
-- and the worker hands that sentence to a provider. For SMS that is
-- exactly right and nothing about it changes. For WhatsApp it cannot
-- work at all: a business-initiated WhatsApp message is an APPROVED
-- TEMPLATE named by a code, and Meta wants the VALUES that go into the
-- template, separately - never a sentence this service composed. Sending
-- one is refused with error 63016 on every attempt, so the retry ladder
-- climbs to SMS_MAX_ATTEMPTS and the family still gets nothing.
--
-- So a row now carries both. body_ar stays the SMS text and stays the
-- thing a centre edits; template_vars is the same information taken
-- apart, for a transport that insists on assembling it itself.
--
-- WHY A jsonb ARRAY AND NOT COLUMNS. The variables are POSITIONAL -
-- Meta numbers them {{1}}, {{2}} - and how many there are is a property
-- of each approved template, not of this schema. Three text columns
-- would be three columns that mean nothing for the templates that take
-- one, and a fourth migration the day a template takes four.
--
-- AND WHY A LOGIN CODE MAY NEVER HAVE ONE. ck_sms_vars_otp is the point
-- of this migration that is worth reading twice. hbh.otp_codes stores a
-- bcrypt hash and nothing else, precisely so that a database dump is not
-- a list of live credentials, and ck_sms_body has kept body_ar NULL for
-- OTP_LOGIN since 0094 for the same reason. A variables column with no
-- such rule is the identical hole reopened in a new shape: the code IS
-- the variable, so an OTP row with template_vars set is the plaintext at
-- rest. The constraint makes that impossible rather than discouraged.
-- The login handler passes its variable to the provider in memory, over
-- the wire, and writes nothing - see deliverOTP.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0109') THEN
    RAISE EXCEPTION 'migration 0109 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0094') THEN
    RAISE EXCEPTION 'migration 0094 must be applied first';
  END IF;
END
$guard$;

ALTER TABLE hbh.sms_outbox
  ADD COLUMN IF NOT EXISTS template_vars jsonb;

-- An array, because the positions are the contract with the approved
-- template. Element types are not checked here - a CHECK cannot contain
-- the subquery that would walk the array - and do not need to be: the
-- only writer builds it from text with jsonb_build_array, and the worker
-- scans it into []string, which fails loudly rather than silently on
-- anything else.
ALTER TABLE hbh.sms_outbox
  ADD CONSTRAINT ck_sms_vars
  CHECK (template_vars IS NULL OR jsonb_typeof(template_vars) = 'array');

-- THE CODE IS NEVER AT REST. See the header.
ALTER TABLE hbh.sms_outbox
  ADD CONSTRAINT ck_sms_vars_otp
  CHECK (NOT (purpose = 'OTP_LOGIN' AND template_vars IS NOT NULL));

-- =====================================================================
-- ENQUEUE TAKES THE VARIABLES
--
-- DROP then CREATE, not CREATE OR REPLACE. Adding a defaulted argument
-- with REPLACE does not replace anything: it OVERLOADS, and every
-- existing eight-argument call then matches both candidates and fails as
-- ambiguous - at the moment a family was owed a message, with an error
-- that names none of this.
-- =====================================================================
DROP FUNCTION IF EXISTS hbh.enqueue_sms(integer, text, text, text, text, text, bigint, text);

CREATE FUNCTION hbh.enqueue_sms(
  p_center_id       integer,
  p_purpose         text,
  p_template_code   text,
  p_destination     text,
  p_dedupe_key      text,
  p_body_ar         text    DEFAULT NULL,
  p_notification_id bigint  DEFAULT NULL,
  p_status          text    DEFAULT 'PENDING',
  p_template_vars   jsonb   DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_id bigint;
BEGIN
  INSERT INTO hbh.sms_outbox (center_id, notification_id, purpose, template_code,
                              destination, body_ar, dedupe_key, status,
                              template_vars, sent_at)
  VALUES (p_center_id, p_notification_id, p_purpose, p_template_code,
          p_destination, p_body_ar, p_dedupe_key, p_status,
          p_template_vars,
          CASE WHEN p_status = 'SENT' THEN now() END)
  ON CONFLICT (dedupe_key) DO NOTHING
  RETURNING sms_id INTO l_id;

  IF l_id IS NULL THEN
    SELECT sms_id INTO l_id FROM hbh.sms_outbox WHERE dedupe_key = p_dedupe_key;
  END IF;
  RETURN l_id;
END
$$;

REVOKE ALL ON FUNCTION hbh.enqueue_sms(integer, text, text, text, text, text, bigint, text, jsonb) FROM PUBLIC;

-- =====================================================================
-- THE NOTIFICATION TRIGGER FILLS THEM
--
-- ONE VARIABLE, AND IT IS THE TITLE. 0094 decided what reaches a phone -
-- the title and a sentence telling the family where to look, never the
-- notification's body_ar, which may carry an invoice line or a decision
-- note. That rule is not relaxed here; it is restated in the shape a
-- template needs. The approved template is the fixed half:
--
--     {{1}}
--     تابع التفاصيل من بوّابة ولي الأمر.
--
-- so the array holds the title and nothing else, and a template that
-- asked for more could not be given it from this path.
-- =====================================================================
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
    'NTF:' || NEW.notification_id::text, l_body, NEW.notification_id, 'PENDING',
    jsonb_build_array(NEW.title_ar));

  RETURN NULL;
END
$$;

-- =====================================================================
-- THE WORKER CLAIMS THEM
--
-- DROP then CREATE for a second reason: a return type cannot be changed
-- by REPLACE at all. Dropping takes the grant with it, so it is given
-- back below - a claim function hbh_app cannot execute stops every
-- message in the queue, silently, because the worker's poll returns no
-- rows exactly as it does when there is nothing to send.
-- =====================================================================
DROP FUNCTION IF EXISTS hbh.claim_sms(integer, text);

CREATE FUNCTION hbh.claim_sms(p_limit integer, p_worker text)
RETURNS TABLE (sms_id bigint, purpose text, template_code text,
               destination text, body_ar text, template_vars jsonb,
               attempts smallint)
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
            o.destination, o.body_ar, o.template_vars, o.attempts;
END
$$;

REVOKE ALL ON FUNCTION hbh.claim_sms(integer, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.claim_sms(integer, text) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0109');
