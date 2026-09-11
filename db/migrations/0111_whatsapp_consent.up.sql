-- =====================================================================
-- Hand By Hand (new) - migration 0111: agreeing to be texted is not
-- agreeing to be messaged on WhatsApp.
--
-- WHAT THIS IS FOR. 0094 gates every family message on the guardian's
-- own SMS_NOTIFY consent, and D-38 says the channel is each guardian's
-- choice and not the household's. Delivering over WhatsApp under a
-- consent whose name, text and Arabic description all say SMS is
-- delivering on a channel nobody agreed to - the consent row would be
-- evidence of a permission that was never given, sitting in the part of
-- the schema that is supposed to be the most truthful thing in it.
--
-- SO THE CHANNEL BECOMES A PARAMETER AND THE CONSENT FOLLOWS IT.
-- NOTIFY_CHANNEL is SMS or WHATSAPP, per centre, and hbh.notify_guardians
-- asks for the consent that matches. Rule 2: the decision is in PL/pgSQL,
-- not in the Go that happens to hold SMS_PROVIDER. The two are related
-- and are deliberately NOT wired together - a deployment that points its
-- transport at WhatsApp while the database still asks for SMS_NOTIFY
-- would otherwise start messaging families on a channel they refused,
-- and nothing in either layer would notice.
--
-- READ THIS BEFORE SWITCHING THE PARAMETER. On the day a centre sets
-- NOTIFY_CHANNEL to WHATSAPP, every guardian who has granted SMS_NOTIFY
-- and not WHATSAPP_NOTIFY stops being messaged. That is correct - they
-- agreed to one thing and not the other - and it will look exactly like
-- an outage: the portal keeps its notifications, sms_pending_flg simply
-- stops being raised, and no error appears anywhere. It is not an
-- outage. It is the fail-closed direction of a consent check, and the
-- fix is to ask the families, not to widen the rule.
--
-- WHY sms_pending_flg KEEPS ITS NAME. Renaming a column read by 0015,
-- 0089 and 0094, by the outbox trigger and by an index whose header
-- calls it "what a sender polls", buys a better word and costs a
-- rewrite of four migrations' worth of meaning. What it MEANS is
-- widened here and said plainly: this family agreed to the channel this
-- centre messages on.
--
-- A LOGIN CODE IS NOT COVERED BY ANY OF THIS. It carries no consent
-- because it is not a notification: the person asked for it, seconds
-- ago, by typing their own number into a login box.
--
-- ON HB232 AND THE 500 IT BECOMES. This migration raises a SQLSTATE the
-- transport layer does not recognise, which 0053, 0058, 0059 and 0083
-- each warn turns into "an unexpected error occurred" on a screen. Here
-- that is the RIGHT answer and no mapping is added: HB232 is not a
-- business rule refusing a caller, it is this deployment's parameter
-- being unreadable. Nobody typed anything wrong, no wording would help
-- them, and an operator needs it in the log as the fault it is. Compare
-- HB172 in store/pgerr.go, which stays a 500 for the same reason.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0111') THEN
    RAISE EXCEPTION 'migration 0111 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0110') THEN
    RAISE EXCEPTION 'migration 0110 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- A FOURTH CONSENT
--
-- Scoped like SMS_NOTIFY and for its reason: watching a child and
-- photographing a child are about a CHILD; being messaged is about the
-- guardian, so it carries no child.
-- =====================================================================
ALTER TABLE hbh.consents DROP CONSTRAINT ck_con_type;
ALTER TABLE hbh.consents
  ADD CONSTRAINT ck_con_type
  CHECK (consent_type IN ('LIVE_VIEW','SMS_NOTIFY','PHOTO_USE','WHATSAPP_NOTIFY'));

ALTER TABLE hbh.consents DROP CONSTRAINT ck_con_scope;
ALTER TABLE hbh.consents
  ADD CONSTRAINT ck_con_scope
  CHECK (
    (consent_type IN ('LIVE_VIEW','PHOTO_USE') AND child_id IS NOT NULL)
    OR (consent_type IN ('SMS_NOTIFY','WHATSAPP_NOTIFY') AND child_id IS NULL));

-- =====================================================================
-- THE CHANNEL
-- =====================================================================
INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar) VALUES
  (NULL, 'NOTIFY_CHANNEL', 'SMS', 'STRING',
   'قناة رسائل الأسر: SMS أو WHATSAPP. تحدّد أي موافقة تُفحص قبل الإرسال')
ON CONFLICT (center_id, param_code) DO NOTHING;

-- =====================================================================
-- THE CONSENT THAT IS ASKED FOR FOLLOWS THE CHANNEL
--
-- THE GUARD COMES FIRST AND THE BUILD AFTER IT. A misspelled channel -
-- "Whatsapp", "whats_app" - must not fall quietly through to SMS_NOTIFY
-- and message families on a channel the centre thought it had left. It
-- raises, before a single row is written, so nothing is half done: this
-- function either notifies everybody or nobody, and D-1's rule about
-- changing state and then raising is not engaged because no state has
-- changed yet.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.notify_guardians(
  p_child_id  integer,
  p_kind      text,
  p_title_ar  text,
  p_body_ar   text    DEFAULT NULL,
  p_link_kind text    DEFAULT NULL,
  p_link_id   integer DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_n       integer;
  l_center  integer;
  l_channel text;
  l_consent text;
BEGIN
  SELECT c.center_id INTO l_center
  FROM   hbh.children c
  WHERE  c.child_id = p_child_id;

  l_channel := upper(trim(hbh.param(l_center, 'NOTIFY_CHANNEL', 'SMS')));

  IF l_channel NOT IN ('SMS', 'WHATSAPP') THEN
    RAISE EXCEPTION 'NOTIFY_CHANNEL must be SMS or WHATSAPP, found %', l_channel
      USING ERRCODE = 'HB232',
            HINT = 'hbh.sys_params NOTIFY_CHANNEL; an unrecognised value is not a default';
  END IF;

  l_consent := CASE l_channel
                 WHEN 'WHATSAPP' THEN 'WHATSAPP_NOTIFY'
                 ELSE 'SMS_NOTIFY'
               END;

  INSERT INTO hbh.notifications (center_id, user_id, child_id, kind_code, title_ar, body_ar,
                                 link_kind, link_id, sms_pending_flg)
  SELECT c.center_id, g.user_id, p_child_id, p_kind, p_title_ar, p_body_ar,
         p_link_kind, p_link_id,
         hbh.has_consent(g.guardian_id, l_consent)
  FROM   hbh.children c
  JOIN   hbh.guardian_children gc ON gc.child_id = c.child_id AND gc.active_flg
  JOIN   hbh.guardians g          ON g.guardian_id = gc.guardian_id AND g.active_flg
  WHERE  c.child_id = p_child_id
  AND    g.user_id IS NOT NULL;

  GET DIAGNOSTICS l_n = ROW_COUNT;
  RETURN l_n;
END
$$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0111');
