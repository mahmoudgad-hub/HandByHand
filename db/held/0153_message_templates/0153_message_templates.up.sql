-- =====================================================================
-- Hand By Hand (new) - migration 0153: the WhatsApp templates live in
-- the database, and so does the id Meta gives each one.
--
-- THE API GOES FIRST. This raises HB300-HB306, which the transport layer
-- has never seen, and scripts/api.sh code-drift refuses a live code that
-- businessRefusal does not name. The API that names them deploys, then
-- this. Nothing that exists today calls the new functions, so an API
-- still on the old build is not broken by this landing early - it simply
-- keeps reading TWILIO_CONTENT_SIDS until it is rebuilt.
--
-- WRITTEN AS 0150, RENUMBERED 0152 AND THEN 0153 BEFORE IT WAS EVER APPLIED.
-- 0149-0151 were owner-approved for other work (the database developer's
-- center_argument security fix among them), and 0152 went to a conventions
-- fix for 0145/0146 that was ready while this one waits on an API image. A
-- migration that waits takes the later number, so the ledger has no gap
-- while it waits. So the guard names 0152, the immediate predecessor.
-- What this migration actually needs is older: 0148 (the reminder codes it
-- seeds for) and 0094 (the outbox it reads).
--
-- WHAT THIS IS FOR. The owner asked, on 2026-09-17, to be able to change
-- the message templates, and chose the complete version: text, approval
-- state and the Meta ContentSid all here, and the Go transport reading the
-- ContentSid from here instead of from TWILIO_CONTENT_SIDS.
--
-- THE ONE THING A ROW HERE CANNOT DO, said before anything else. Editing
-- a template's text does NOT change what WhatsApp sends. Meta approved a
-- specific text under a specific ContentSid; a new text is a new
-- submission, a new approval and a new id. So an edit puts the row back in
-- DRAFT and LEAVES content_sid AS IT WAS - the approved template keeps
-- being sent until the new one is approved and its id written in. A
-- design that cleared the id on edit would stop every message of that
-- kind the moment somebody fixed a typo.
--
-- WHAT THE OWNER MAY CHANGE AND WHAT IS A CONTRACT WITH THE CODE.
--   Editable: the text, the button, the approval state, the ContentSid.
--   Fixed at seed: template_key, category, var_count and the variable
--   labels. The code fills {{1}}..{{n}} in a fixed order; a template
--   approved with a different count is sent wrong or refused, and nothing
--   shows it until a real family's message. trg_message_template_rules
--   refuses a change to any of them (HB305), and the edit function refuses
--   a text whose placeholders are not exactly {{1}}..{{var_count}} (HB302).
--
-- WHICH ROW A MESSAGE USES is also code, not data: message_template_key
-- maps an outbox template_code to a template_key. Ten notification kinds
-- send only their title as {{1}}, so they share PORTAL_UPDATE; the rest
-- map to themselves. It is a function and not a column because which
-- values a code sends is decided where the values are built.
--
-- ONE ROW PER CENTRE, SEEDED - NO GLOBAL ROWS. A NULL-centre row is
-- readable by an unauthenticated connection under a policy that allows
-- center_id IS NULL, which is the lesson in CLAUDE.md, and editing a global
-- row would change every centre's messages at once. The rows are created
-- by db/seed/0005_message_templates.sql for every centre, because this
-- migration runs before the seeds and hbh.centers is empty on a rebuild.
--
-- Error classes added here:
--   HB300  not permitted to manage message templates    (403)
--   HB301  no such template in this centre              (404)
--   HB302  the text's placeholders break the contract   (422)
--   HB303  a template status off its state machine      (409)
--   HB304  an AUTHENTICATION template has no text       (422)
--   HB305  a contract field was changed                 (500 - schema only)
--   HB306  APPROVED without a valid ContentSid          (422)
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0153') THEN
    RAISE EXCEPTION 'migration 0153 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0152') THEN
    RAISE EXCEPTION 'migration 0152 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- THE TABLE
-- =====================================================================
CREATE TABLE hbh.message_templates (
  template_id    integer     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  center_id      integer     NOT NULL REFERENCES hbh.centers (center_id),
  template_key   text        NOT NULL,
  category       text        NOT NULL,
  var_count      smallint    NOT NULL,
  var_labels_ar  text[]      NOT NULL DEFAULT '{}',
  body_ar        text,
  button_text_ar text,
  button_url     text,
  content_sid    text,
  status         text        NOT NULL DEFAULT 'DRAFT',
  status_note_ar text,
  active_flg     boolean     NOT NULL DEFAULT true,
  deleted_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at     timestamptz,
  updated_by     text,

  CONSTRAINT ck_mt_key      CHECK (template_key ~ '^[A-Z][A-Z0-9_]{1,59}$'),
  CONSTRAINT ck_mt_category CHECK (category IN ('UTILITY','AUTHENTICATION')),
  CONSTRAINT ck_mt_status   CHECK (status IN ('DRAFT','SUBMITTED','APPROVED','REJECTED')),
  CONSTRAINT ck_mt_vars     CHECK (var_count BETWEEN 0 AND 10
                                   AND cardinality(var_labels_ar) = var_count),
  -- Meta writes an AUTHENTICATION template's text itself; every other
  -- category is text this centre wrote.
  CONSTRAINT ck_mt_body     CHECK ((category = 'AUTHENTICATION') = (body_ar IS NULL)),
  CONSTRAINT ck_mt_button   CHECK ((button_text_ar IS NULL) = (button_url IS NULL)),
  CONSTRAINT ck_mt_url      CHECK (button_url IS NULL OR button_url ~ '^https://[^[:space:]]+$'),
  CONSTRAINT ck_mt_sid      CHECK (content_sid IS NULL OR content_sid ~ '^HX[0-9a-fA-F]{32}$'),
  -- A template that says APPROVED has an id to be sent under.
  CONSTRAINT ck_mt_approved CHECK (status <> 'APPROVED' OR content_sid IS NOT NULL),
  CONSTRAINT ck_mt_deleted  CHECK (active_flg OR deleted_at IS NOT NULL)
);

CREATE UNIQUE INDEX uix_mt_center_key ON hbh.message_templates (center_id, template_key) WHERE active_flg;
CREATE INDEX ix_mt_center ON hbh.message_templates (center_id);

-- =====================================================================
-- THE HISTORY - append-only
-- =====================================================================
CREATE TABLE hbh.message_template_events (
  event_id    bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  center_id   integer     NOT NULL REFERENCES hbh.centers (center_id),
  template_id integer     NOT NULL REFERENCES hbh.message_templates (template_id),
  from_status text,
  to_status   text        NOT NULL,
  -- The text and the id AS THEY WERE AFTER this event, so the question
  -- "what exactly was approved under HX..." has an answer after the row
  -- has been edited again.
  body_ar     text,
  button_url  text,
  content_sid text,
  note_ar     text,
  changed_by  text        NOT NULL DEFAULT hbh.current_app_user(),
  changed_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_mte_template ON hbh.message_template_events (template_id);
CREATE INDEX ix_mte_center   ON hbh.message_template_events (center_id);

CREATE TRIGGER trg_mte_append_only
  BEFORE UPDATE OR DELETE ON hbh.message_template_events
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_append_only();

INSERT INTO hbh.convention_exemptions (table_name, rule_code, reason) VALUES
  ('message_template_events', 'AUDIT_COLUMNS',
   'An append-only record of one change to a template. changed_by and changed_at are its attribution; a row here is never edited.'),
  ('message_template_events', 'SOFT_DELETE',
   'Append-only by trigger. A flag that hid an event would be a way to hide which text was approved under which Meta id.');

-- =====================================================================
-- THE PLACEHOLDER CONTRACT
--
-- Exactly {{1}}..{{n}}, each at least once, nothing else in braces, and
-- neither the first nor the last thing in the text - Meta refuses a body
-- that starts or ends with a variable.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.template_placeholders_ok(p_body text, p_var_count integer)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_found  integer[];
  l_opens  integer;
  l_trim   text;
BEGIN
  IF p_body IS NULL OR btrim(p_body) = '' THEN
    RETURN false;
  END IF;

  -- Every "{{" must open a well-formed placeholder. Counting the openers
  -- separately catches "{{ 1}}" and "{{1}" that the pattern below skips.
  l_opens := (length(p_body) - length(replace(p_body, '{{', ''))) / 2;

  SELECT coalesce(array_agg(DISTINCT m[1]::integer ORDER BY m[1]::integer), '{}')
    INTO l_found
  FROM regexp_matches(p_body, '\{\{([1-9][0-9]?)\}\}', 'g') m;

  IF l_opens <> (SELECT count(*) FROM regexp_matches(p_body, '\{\{[1-9][0-9]?\}\}', 'g')) THEN
    RETURN false;
  END IF;

  IF l_found IS DISTINCT FROM
     coalesce((SELECT array_agg(g ORDER BY g) FROM generate_series(1, p_var_count) g), '{}') THEN
    RETURN false;
  END IF;

  l_trim := btrim(p_body, E' \t\r\n');
  IF l_trim ~ '^\{\{' OR l_trim ~ '\}\}$' THEN
    RETURN false;
  END IF;

  RETURN true;
END
$$;

-- =====================================================================
-- THE STATE MACHINE AND THE CONTRACT, ENFORCED ON THE ROW
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.legal_message_template_transition(p_from text, p_to text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = hbh, pg_catalog
AS $$
  SELECT p_from IS DISTINCT FROM p_to AND (p_from, p_to) IN (
    ('DRAFT',     'SUBMITTED'),
    ('SUBMITTED', 'APPROVED'),
    ('SUBMITTED', 'REJECTED'),
    -- An edit sends the row back to DRAFT from any state that has one.
    ('SUBMITTED', 'DRAFT'),
    ('APPROVED',  'DRAFT'),
    ('REJECTED',  'DRAFT')
  )
$$;

CREATE OR REPLACE FUNCTION hbh.trg_message_template_rules()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF NEW.template_key IS DISTINCT FROM OLD.template_key
     OR NEW.category  IS DISTINCT FROM OLD.category
     OR NEW.var_count IS DISTINCT FROM OLD.var_count
     OR NEW.var_labels_ar IS DISTINCT FROM OLD.var_labels_ar
     OR NEW.center_id IS DISTINCT FROM OLD.center_id THEN
    RAISE EXCEPTION 'template % contract fields are fixed', OLD.template_id
      USING ERRCODE = 'HB305';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT hbh.legal_message_template_transition(OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'template % cannot move from % to %', OLD.template_id, OLD.status, NEW.status
      USING ERRCODE = 'HB303';
  END IF;

  -- A changed text is a text nobody has approved. Whoever changed it, the
  -- row says DRAFT - the approved id is kept (see the header).
  IF (NEW.body_ar IS DISTINCT FROM OLD.body_ar
      OR NEW.button_text_ar IS DISTINCT FROM OLD.button_text_ar
      OR NEW.button_url IS DISTINCT FROM OLD.button_url)
     AND NEW.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'template % text changed without returning to DRAFT', OLD.template_id
      USING ERRCODE = 'HB303';
  END IF;

  RETURN NEW;
END
$$;

CREATE TRIGGER trg_mt_rules BEFORE UPDATE ON hbh.message_templates
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_message_template_rules();

CREATE OR REPLACE FUNCTION hbh.trg_message_template_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF TG_OP = 'INSERT'
     OR NEW.status      IS DISTINCT FROM OLD.status
     OR NEW.body_ar     IS DISTINCT FROM OLD.body_ar
     OR NEW.button_url  IS DISTINCT FROM OLD.button_url
     OR NEW.content_sid IS DISTINCT FROM OLD.content_sid THEN
    INSERT INTO hbh.message_template_events
      (center_id, template_id, from_status, to_status, body_ar, button_url, content_sid, note_ar)
    VALUES
      (NEW.center_id, NEW.template_id,
       CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE OLD.status END,
       NEW.status, NEW.body_ar, NEW.button_url, NEW.content_sid, NEW.status_note_ar);
  END IF;
  RETURN NULL;
END
$$;

CREATE TRIGGER trg_mt_event AFTER INSERT OR UPDATE ON hbh.message_templates
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_message_template_event();

CREATE TRIGGER trg_mt_touch BEFORE UPDATE ON hbh.message_templates
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_mt_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.message_templates
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('template_id');

-- =====================================================================
-- WHO MAY READ IT
--
-- Staff holding MESSAGE_TEMPLATE.EDIT, in their own centre. Writes go
-- through the two functions below only - no INSERT, UPDATE or DELETE is
-- granted - so the placeholder contract cannot be walked around by a
-- direct UPDATE from the API.
-- =====================================================================
ALTER TABLE hbh.message_templates       ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.message_template_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_mt_select ON hbh.message_templates FOR SELECT TO hbh_app
  USING ((SELECT hbh.current_center_id() IS NOT NULL)
         AND center_id = (SELECT hbh.current_center_id())
         AND active_flg
         AND (SELECT hbh.has_permission('MESSAGE_TEMPLATE.EDIT')));

CREATE POLICY p_mte_select ON hbh.message_template_events FOR SELECT TO hbh_app
  USING ((SELECT hbh.current_center_id() IS NOT NULL)
         AND center_id = (SELECT hbh.current_center_id())
         AND (SELECT hbh.has_permission('MESSAGE_TEMPLATE.EDIT')));

GRANT SELECT ON hbh.message_templates       TO hbh_app;
GRANT SELECT ON hbh.message_template_events TO hbh_app;

-- =====================================================================
-- WHICH TEMPLATE A MESSAGE USES
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.message_template_key(p_code text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = hbh, pg_catalog
AS $$
  SELECT CASE
           WHEN p_code IN ('APPOINTMENT_BOOKED', 'APPOINTMENT_RESCHEDULED',
                           'APPOINTMENT_CANCELLED', 'REQUEST_DECIDED',
                           'REPORT_PUBLISHED', 'NOTE_PUBLISHED',
                           'ASSESSMENT_PUBLISHED', 'INVOICE_ISSUED',
                           'INSTALLMENT_DUE', 'INSTALLMENT_OVERDUE')
             THEN 'PORTAL_UPDATE'
           ELSE p_code
         END
$$;

-- The id to send a message of this code under, for this centre - or NULL
-- when there is no approved template yet.
--
-- SECURITY DEFINER AND GRANTED TO hbh_app, for the reason 0095 gave
-- request_otp: a login code is sent before there is a session, so RLS on
-- the table matches nothing. What it hands back is a Meta template id -
-- the same string that travels in every request to the provider - and
-- nothing about any family.
CREATE OR REPLACE FUNCTION hbh.message_template_sid(p_center_id integer, p_code text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT t.content_sid
  FROM   hbh.message_templates t
  WHERE  t.center_id = p_center_id
  AND    t.template_key = hbh.message_template_key(p_code)
  AND    t.active_flg
$$;

-- The same, for a row the worker has claimed: the outbox already knows its
-- centre and its code, and the worker should not have to carry them.
CREATE OR REPLACE FUNCTION hbh.sms_template_sid(p_sms_id bigint)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_sid text;
BEGIN
  PERFORM hbh.assert_sms_worker();
  SELECT hbh.message_template_sid(o.center_id, o.template_code) INTO l_sid
  FROM   hbh.sms_outbox o
  WHERE  o.sms_id = p_sms_id;
  RETURN l_sid;
END
$$;

-- How many active centres could not send a message of this code under an
-- approved template. The API asks this at startup in production for
-- OTP_LOGIN: a centre whose parents cannot receive a login code has no
-- working front door.
CREATE OR REPLACE FUNCTION hbh.centres_without_template_sid(p_code text)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT count(*)::integer
  FROM   hbh.centers c
  WHERE  hbh.message_template_sid(c.center_id, p_code) IS NULL
$$;

-- =====================================================================
-- THE TWO WRITERS
--
-- In the order CLAUDE.md fixes: may I - read the row - does it exist and
-- is it mine (one answer, HB301) - does its state allow it - then write.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.edit_message_template(
  p_template_id    integer,
  p_body_ar        text,
  p_button_text_ar text DEFAULT NULL,
  p_button_url     text DEFAULT NULL,
  p_note_ar        text DEFAULT NULL)
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

  IF l_t.category = 'AUTHENTICATION' THEN
    RAISE EXCEPTION 'an AUTHENTICATION template has no text to edit - Meta writes it'
      USING ERRCODE = 'HB304';
  END IF;

  IF NOT hbh.template_placeholders_ok(p_body_ar, l_t.var_count) THEN
    RAISE EXCEPTION 'template text must use exactly {{1}}..{{%}}, and neither start nor end with one',
      l_t.var_count USING ERRCODE = 'HB302';
  END IF;

  UPDATE hbh.message_templates
     SET body_ar        = p_body_ar,
         button_text_ar = p_button_text_ar,
         button_url     = p_button_url,
         status         = 'DRAFT',
         status_note_ar = p_note_ar
   WHERE template_id = p_template_id;

  RETURN p_template_id;
END
$$;

-- SUBMITTED, APPROVED (with the id Meta gave it) or REJECTED.
-- DRAFT is not reachable here: a template returns to DRAFT by being edited.
CREATE OR REPLACE FUNCTION hbh.set_message_template_status(
  p_template_id integer,
  p_status      text,
  p_content_sid text DEFAULT NULL,
  p_note_ar     text DEFAULT NULL)
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

  IF p_status = 'APPROVED'
     AND (p_content_sid IS NULL OR p_content_sid !~ '^HX[0-9a-fA-F]{32}$') THEN
    RAISE EXCEPTION 'an approved template needs the ContentSid Meta gave it (HX followed by 32 hex digits)'
      USING ERRCODE = 'HB306';
  END IF;

  UPDATE hbh.message_templates
     SET status         = p_status,
         content_sid    = CASE WHEN p_status = 'APPROVED' THEN p_content_sid ELSE content_sid END,
         status_note_ar = p_note_ar
   WHERE template_id = p_template_id;

  RETURN p_template_id;
END
$$;

REVOKE ALL ON FUNCTION hbh.template_placeholders_ok(text, integer)                    FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.legal_message_template_transition(text, text)              FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.message_template_key(text)                                 FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.message_template_sid(integer, text)                        FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.sms_template_sid(bigint)                                   FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.centres_without_template_sid(text)                         FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.edit_message_template(integer, text, text, text, text)     FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.set_message_template_status(integer, text, text, text)     FROM PUBLIC;

GRANT EXECUTE ON FUNCTION hbh.template_placeholders_ok(text, integer)                 TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.message_template_key(text)                              TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.message_template_sid(integer, text)                     TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.sms_template_sid(bigint)                                TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.centres_without_template_sid(text)                      TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.edit_message_template(integer, text, text, text, text)  TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.set_message_template_status(integer, text, text, text)  TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0153');
