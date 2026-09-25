-- =====================================================================
-- 0167 - a WhatsApp template is named by Meta, not by a reseller
--
-- HELD. Moves to db/migrations/ when an API image carrying
-- hbh.message_template_ref is running - the same condition 0153 had, for
-- the same reason: the lookups this replaces are what the running image
-- calls, and a database that answers neither shape can send nothing.
--
-- WHY. Until today this centre reached WhatsApp through Twilio, and a
-- template was identified by a Twilio ContentSid (HX + 32 hex). The owner
-- moved the centre onto Meta's own Cloud API on 2026-09-18 and the Twilio
-- sender was deleted in the same change. Meta does not issue an id for a
-- template: it takes THE NAME IT WAS APPROVED UNDER AND THE LANGUAGE IT
-- WAS APPROVED IN, and it treats a name in a language it does not have as
-- a template that does not exist. So the column that held one opaque
-- string becomes two, and every lookup hands both back together - a
-- caller that could take the name without the language would fail every
-- send with an error that names the template and not the missing half.
--
-- AND A THIRD THING TRAVELS WITH THEM: whether the template is an
-- AUTHENTICATION one. Meta builds those with a button that copies the
-- code, and refuses the message unless the button's value is sent
-- alongside the body - the same code, twice. The transport cannot know
-- that from the name, and the category is already recorded here, so it is
-- returned rather than guessed at.
--
-- WHAT IS DROPPED AND WHY IT COSTS NOTHING. content_sid, its CHECK, and
-- the three functions that read it. Checked on the live database before
-- this was written: 6 templates, 0 with a sid, 0 APPROVED. Nothing was
-- ever approved under a Twilio id, so no history is lost - and the
-- append-only events table keeps every row it has.
--
-- HB306 KEEPS ITS NUMBER AND CHANGES ITS SUBJECT: "an approved template
-- needs the id Meta gave it" becomes "needs the name and language it was
-- approved under". The API names HB306 already; its client code moves
-- from CONTENT_SID_REQUIRED to TEMPLATE_NAME_REQUIRED in the same image
-- this migration waits for, so no screen sees a code it cannot act on.
-- =====================================================================

DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0153') THEN
    RAISE EXCEPTION 'migration 0153 must be applied first';
  END IF;
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0167') THEN
    RAISE EXCEPTION 'migration 0167 is already applied';
  END IF;
END
$guard$;

-- =====================================================================
-- THE IDENTITY
-- =====================================================================
ALTER TABLE hbh.message_templates
  ADD COLUMN template_name text,
  ADD COLUMN language_code text;

ALTER TABLE hbh.message_templates
  DROP CONSTRAINT ck_mt_sid,
  DROP CONSTRAINT ck_mt_approved,
  DROP COLUMN content_sid;

ALTER TABLE hbh.message_templates
  -- Meta's own rule for a template name: lower case, digits and
  -- underscores. Rejecting HBH's uppercase template_key here is the point -
  -- the two are different names for different audiences, and typing the key
  -- into this column would produce a template Meta has never heard of.
  -- THE LENGTH IS A SEPARATE TERM, not {0,511} in the pattern: Postgres
  -- refuses a repetition count above 255 outright ("invalid repetition
  -- count"), and Meta's limit is 512. Written as one regex, this
  -- constraint does not reject a long name - it makes every UPDATE of
  -- this table fail.
  ADD CONSTRAINT ck_mt_name CHECK (template_name IS NULL
                                   OR (template_name ~ '^[a-z][a-z0-9_]*$'
                                       AND length(template_name) <= 512)),
  ADD CONSTRAINT ck_mt_lang CHECK (language_code IS NULL
                                   OR language_code ~ '^[a-z]{2}(_[A-Z]{2})?$'),
  -- NEITHER HALF IS USEFUL ALONE, so neither may be stored alone.
  ADD CONSTRAINT ck_mt_identity CHECK ((template_name IS NULL) = (language_code IS NULL)),
  -- A template that says APPROVED has something to be sent under.
  ADD CONSTRAINT ck_mt_approved CHECK (status <> 'APPROVED' OR template_name IS NOT NULL);

-- The history records what was approved, in the same two parts. The rows
-- already there keep their NULLs: nothing was ever approved under a sid.
ALTER TABLE hbh.message_template_events
  ADD COLUMN template_name text,
  ADD COLUMN language_code text,
  DROP COLUMN content_sid;

COMMENT ON COLUMN hbh.message_templates.template_name IS
  'The name Meta approved this template under, lower case. NULL until an approval.';
COMMENT ON COLUMN hbh.message_templates.language_code IS
  'The language Meta approved it in: ar, en, or a locale such as ar_EG.';

-- =====================================================================
-- THE RULES, REWRITTEN WHERE THEY NAMED THE SID
--
-- The contract fields are unchanged. What changes is which columns count
-- as "the approval", for the event trigger.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.trg_message_template_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF TG_OP = 'INSERT'
     OR NEW.status        IS DISTINCT FROM OLD.status
     OR NEW.body_ar       IS DISTINCT FROM OLD.body_ar
     OR NEW.button_url    IS DISTINCT FROM OLD.button_url
     OR NEW.template_name IS DISTINCT FROM OLD.template_name
     OR NEW.language_code IS DISTINCT FROM OLD.language_code THEN
    INSERT INTO hbh.message_template_events
      (center_id, template_id, from_status, to_status, body_ar, button_url,
       template_name, language_code, note_ar)
    VALUES
      (NEW.center_id, NEW.template_id,
       CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.status END,
       NEW.status, NEW.body_ar, NEW.button_url,
       NEW.template_name, NEW.language_code, NEW.status_note_ar);
  END IF;
  RETURN NULL;
END
$$;

-- =====================================================================
-- THE LOOKUPS
--
-- One row rather than one string, and the three fields are answered
-- together for the reason the header gives.
-- =====================================================================
DROP FUNCTION IF EXISTS hbh.sms_template_sid(bigint);
DROP FUNCTION IF EXISTS hbh.centres_without_template_sid(text);
DROP FUNCTION IF EXISTS hbh.message_template_sid(integer, text);

-- What a message of this code goes out as, for this centre - or no row
-- when there is no approved template yet.
--
-- SECURITY DEFINER AND GRANTED TO hbh_app, for the reason 0095 gave
-- request_otp: a login code is sent before there is a session, so RLS on
-- the table matches nothing. What it hands back is a template name, a
-- language and a category - the same values that travel in every request
-- to Meta, and nothing about any family.
CREATE OR REPLACE FUNCTION hbh.message_template_ref(p_center_id integer, p_code text)
RETURNS TABLE (template_name text, language_code text, is_auth boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT t.template_name, t.language_code, t.category = 'AUTHENTICATION'
  FROM   hbh.message_templates t
  WHERE  t.center_id = p_center_id
  AND    t.template_key = hbh.message_template_key(p_code)
  AND    t.active_flg
$$;

-- The same, for a row the worker has claimed: the outbox already knows its
-- centre and its code, and the worker should not have to carry them.
CREATE OR REPLACE FUNCTION hbh.sms_template_ref(p_sms_id bigint)
RETURNS TABLE (template_name text, language_code text, is_auth boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  PERFORM hbh.assert_sms_worker();
  RETURN QUERY
    SELECT r.template_name, r.language_code, r.is_auth
    FROM   hbh.sms_outbox o
    CROSS JOIN LATERAL hbh.message_template_ref(o.center_id, o.template_code) r
    WHERE  o.sms_id = p_sms_id;
END
$$;

-- How many active centres could not send a message of this code under an
-- approved template. The API asks this at startup in production for
-- OTP_LOGIN: a centre whose parents cannot receive a login code has no
-- working front door.
--
-- "APPROVED" IS A NAME, NOT THE STATUS COLUMN, and that is deliberate: an
-- edit sends a row back to DRAFT and keeps the name it is still being sent
-- under, which is what stops a typo fix from silencing a whole kind of
-- message. A centre counts as able to send when there is something to send
-- with.
CREATE OR REPLACE FUNCTION hbh.centres_without_approved_template(p_code text)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT count(*)::integer
  FROM   hbh.centers c
  WHERE  NOT EXISTS (SELECT 1
                     FROM   hbh.message_template_ref(c.center_id, p_code) r
                     WHERE  r.template_name IS NOT NULL)
$$;

-- =====================================================================
-- THE APPROVAL
-- =====================================================================
DROP FUNCTION IF EXISTS hbh.set_message_template_status(integer, text, text, text);

CREATE OR REPLACE FUNCTION hbh.set_message_template_status(
  p_template_id   integer,
  p_status        text,
  p_template_name text DEFAULT NULL,
  p_language_code text DEFAULT NULL,
  p_note_ar       text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_center integer := hbh.current_center_id();
  l_t      hbh.message_templates%ROWTYPE;
BEGIN
  IF NOT hbh.has_permission('MESSAGE_TEMPLATE.EDIT') THEN
    RAISE EXCEPTION 'not permitted to manage message templates' USING ERRCODE = 'HB300';
  END IF;

  SELECT * INTO l_t FROM hbh.message_templates
  WHERE  template_id = p_template_id AND center_id = l_center AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such template %', p_template_id USING ERRCODE = 'HB301';
  END IF;

  IF p_status NOT IN ('SUBMITTED', 'APPROVED', 'REJECTED')
     OR NOT hbh.legal_message_template_transition(l_t.status, p_status) THEN
    RAISE EXCEPTION 'template % cannot move from % to %', p_template_id, l_t.status, p_status
      USING ERRCODE = 'HB303';
  END IF;

  -- BOTH HALVES, OR NEITHER. A name with no language is a send that fails
  -- with "template does not exist" - the error that sends the reader
  -- looking at the wrong thing.
  IF p_status = 'APPROVED'
     AND (p_template_name IS NULL OR p_template_name !~ '^[a-z][a-z0-9_]*$'
          OR length(p_template_name) > 512
          OR p_language_code IS NULL OR p_language_code !~ '^[a-z]{2}(_[A-Z]{2})?$') THEN
    RAISE EXCEPTION 'an approved template needs the name Meta approved it under (lower case) and its language, such as ar'
      USING ERRCODE = 'HB306';
  END IF;

  UPDATE hbh.message_templates
     SET status         = p_status,
         template_name  = CASE WHEN p_status = 'APPROVED' THEN p_template_name ELSE template_name END,
         language_code  = CASE WHEN p_status = 'APPROVED' THEN p_language_code ELSE language_code END,
         status_note_ar = p_note_ar
   WHERE template_id = p_template_id;

  RETURN p_template_id;
END
$$;

REVOKE ALL ON FUNCTION hbh.message_template_ref(integer, text)                            FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.sms_template_ref(bigint)                                       FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.centres_without_approved_template(text)                        FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.set_message_template_status(integer, text, text, text, text)   FROM PUBLIC;

GRANT EXECUTE ON FUNCTION hbh.message_template_ref(integer, text)                         TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.sms_template_ref(bigint)                                    TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.centres_without_approved_template(text)                     TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.set_message_template_status(integer, text, text, text, text) TO hbh_app;

-- =====================================================================
-- PROVE IT, BEFORE THE TRANSACTION COMMITS
--
-- A migration that renames the thing every message is sent under has one
-- way to be wrong that nothing downstream would notice for days: a
-- function that exists, is granted, and answers NULL. So the lookups are
-- asked about a template that IS approved.
--
-- AND THE APPROVAL IS UNDONE WITHOUT LEAVING A CERTIFICATE THAT IS NOT
-- TRUE. hbh.message_template_events is append-only by trigger and is the
-- record of what was approved under which name; a probe that approved a
-- template and then deleted its own event would be refused (HB001), and
-- one that left it would make the history say the owner approved
-- "hbh_otp_login_check". So the probe runs inside a plpgsql block with an
-- EXCEPTION handler - which is a savepoint - and ends by raising, so
-- every row it wrote is rolled back. plpgsql variables survive that, so
-- the answers it read are still here to be asserted on.
-- =====================================================================
DO $verify$
DECLARE
  l_left  text;
  l_id    integer;
  l_name  text;
  l_auth  boolean;
  l_n     integer;
  l_probe constant text := '0167 probe rollback';
BEGIN
  SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO l_left
  FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'hbh' AND p.proname IN
         ('message_template_sid', 'sms_template_sid', 'centres_without_template_sid');
  IF l_left IS NOT NULL THEN
    RAISE EXCEPTION '0167: the sid lookups are still here: %', l_left;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'hbh' AND table_name = 'message_templates'
             AND   column_name = 'content_sid') THEN
    RAISE EXCEPTION '0167: content_sid was not dropped';
  END IF;

  SELECT template_id INTO l_id FROM hbh.message_templates
  WHERE  template_key = 'OTP_LOGIN' AND active_flg ORDER BY template_id LIMIT 1;
  IF l_id IS NULL THEN
    RAISE NOTICE '0167: no OTP_LOGIN template to prove the lookups on - seed not applied';
    RETURN;
  END IF;

  BEGIN
    -- TWO STATEMENTS, AND THE ORDER IS THE STATE MACHINE'S, NOT THE
    -- PROBE'S CONVENIENCE. DRAFT does not jump to APPROVED - the rule
    -- trigger refuses it with HB303, which is how this probe found out it
    -- was writing a transition nobody can make. One statement per
    -- transition, because a second UPDATE of the same row in one statement
    -- is dropped in silence.
    UPDATE hbh.message_templates SET status = 'SUBMITTED' WHERE template_id = l_id;
    UPDATE hbh.message_templates
       SET status = 'APPROVED', template_name = 'hbh_otp_login_check', language_code = 'ar'
     WHERE template_id = l_id;

    SELECT r.template_name, r.is_auth INTO l_name, l_auth
    FROM   hbh.message_templates t
    CROSS  JOIN LATERAL hbh.message_template_ref(t.center_id, 'OTP_LOGIN') r
    WHERE  t.template_id = l_id;

    SELECT hbh.centres_without_approved_template('OTP_LOGIN') INTO l_n;

    RAISE EXCEPTION '%', l_probe;
  EXCEPTION WHEN raise_exception THEN
    -- ONLY THE PROBE'S OWN RAISE IS SWALLOWED. Anything else - a constraint
    -- this migration got wrong, a function that will not run - is re-raised,
    -- because a handler that ate it would report a successful migration
    -- whose lookups do not work.
    IF SQLERRM <> l_probe THEN
      RAISE;
    END IF;
  END;

  IF l_name IS DISTINCT FROM 'hbh_otp_login_check' THEN
    RAISE EXCEPTION '0167: message_template_ref answered % for an approved template', coalesce(l_name, 'NULL');
  END IF;
  IF NOT l_auth THEN
    RAISE EXCEPTION '0167: an AUTHENTICATION template did not say so - its login code would go out one parameter short';
  END IF;
  IF l_n IS NULL THEN
    RAISE EXCEPTION '0167: centres_without_approved_template answered NULL';
  END IF;

  -- And the key map still reaches PORTAL_UPDATE, which is what every
  -- notification is sent under.
  IF hbh.message_template_key('REQUEST_DECIDED') <> 'PORTAL_UPDATE' THEN
    RAISE EXCEPTION '0167: the template key map was lost';
  END IF;

  -- The probe left nothing behind: no approval, and no event saying there
  -- was one.
  IF EXISTS (SELECT 1 FROM hbh.message_templates WHERE template_name = 'hbh_otp_login_check')
     OR EXISTS (SELECT 1 FROM hbh.message_template_events WHERE template_name = 'hbh_otp_login_check') THEN
    RAISE EXCEPTION '0167: the probe''s approval outlived it';
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0167');
