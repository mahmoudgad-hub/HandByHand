-- =====================================================================
-- 0167 down - back to a Twilio ContentSid
--
-- IT RESTORES THE SHAPE AND NOT THE DATA, and it cannot do otherwise: a
-- template approved under a Meta name has no ContentSid anywhere to put
-- back. Any approval made while 0167 was applied returns to DRAFT, which
-- is the truth of a database that has no id to send under - not a loss,
-- because the Twilio account this shape belongs to is no longer used.
--
-- The point of this file is that 0167 can be taken off a database it was
-- applied to by mistake, leaving 0153's schema exactly as it was.
-- =====================================================================

DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0167') THEN
    RAISE EXCEPTION 'migration 0167 is not applied';
  END IF;
END
$guard$;

DROP FUNCTION IF EXISTS hbh.set_message_template_status(integer, text, text, text, text);
DROP FUNCTION IF EXISTS hbh.centres_without_approved_template(text);
DROP FUNCTION IF EXISTS hbh.sms_template_ref(bigint);
DROP FUNCTION IF EXISTS hbh.message_template_ref(integer, text);

-- Nothing can be sent under a name this shape cannot hold.
UPDATE hbh.message_templates
   SET status = 'DRAFT', status_note_ar = 'returned to DRAFT by the 0167 down migration'
 WHERE status = 'APPROVED';

ALTER TABLE hbh.message_template_events
  ADD COLUMN content_sid text,
  DROP COLUMN template_name,
  DROP COLUMN language_code;

ALTER TABLE hbh.message_templates
  DROP CONSTRAINT ck_mt_name,
  DROP CONSTRAINT ck_mt_lang,
  DROP CONSTRAINT ck_mt_identity,
  DROP CONSTRAINT ck_mt_approved,
  DROP COLUMN template_name,
  DROP COLUMN language_code;

ALTER TABLE hbh.message_templates
  ADD COLUMN content_sid text,
  ADD CONSTRAINT ck_mt_sid      CHECK (content_sid IS NULL OR content_sid ~ '^HX[0-9a-fA-F]{32}$'),
  ADD CONSTRAINT ck_mt_approved CHECK (status <> 'APPROVED' OR content_sid IS NOT NULL);

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

REVOKE ALL ON FUNCTION hbh.message_template_sid(integer, text)                    FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.sms_template_sid(bigint)                               FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.centres_without_template_sid(text)                     FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.set_message_template_status(integer, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION hbh.message_template_sid(integer, text)                 TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.sms_template_sid(bigint)                            TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.centres_without_template_sid(text)                  TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.set_message_template_status(integer, text, text, text) TO hbh_app;

DELETE FROM hbh.schema_migrations WHERE version = '0167';
