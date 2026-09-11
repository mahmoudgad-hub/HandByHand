-- =====================================================================
-- Hand By Hand (new) - migration 0015: recorded consents, and the
-- notifications they gate.
--
-- Two gaps the visual prototype already promises and the schema did
-- not have. They are in one migration because the first one gates the
-- second: a text message may only be sent to a family that agreed to
-- receive one.
--
-- 1. CONSENT IS A RECORD, NOT A CHECKBOX.
--    guardian_children.can_view_live_flg existed, and nothing said WHO
--    turned it on, WHEN, or on the strength of what. For permission to
--    watch a child in therapy, and for permission to use a child's
--    photograph, that is not a defensible answer six months later.
--
--    So the flag stops being writable by hand. From here it can ONLY
--    move through grant_consent / withdraw_consent, each of which
--    writes an append-only event naming the guardian, the child, the
--    person who recorded it and the version of the wording they saw.
--    A trigger refuses any other route.
--
-- 2. A NOTIFICATION IS GENERATED, NOT TYPED.
--    The bell in the prototype had a red dot and nothing behind it.
--    Notifications are now written by triggers on the events that
--    matter - a report published, a note published, a request decided,
--    an invoice issued - so a family is told because something HAPPENED
--    and not because somebody remembered to tell them.
--
--    And the SMS channel is opt-in: the row is always created for the
--    portal, and sms_pending_flg is set only where a granted
--    SMS_NOTIFY consent exists. That is the join between the two halves
--    of this migration.
--
-- Error classes added here:
--   HB080  the consent scope does not match its type
--   HB081  can_view_live_flg may only move through a recorded consent
--   HB082  not permitted to record this consent
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0015') THEN
    RAISE EXCEPTION 'migration 0015 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0014') THEN
    RAISE EXCEPTION 'migration 0014 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- CONSENTS
--
-- Current state in one table, every change in an append-only companion
-- - the same shape as appointments and their status history, and for
-- the same reason: the current answer has to be cheap to read, and the
-- history has to be impossible to rewrite.
-- =====================================================================
CREATE TABLE hbh.consents (
  consent_id    integer     GENERATED ALWAYS AS IDENTITY,
  center_id     integer     NOT NULL,
  guardian_id   integer     NOT NULL,
  child_id      integer,
  consent_type  text        NOT NULL,
  granted_flg   boolean     NOT NULL DEFAULT false,
  granted_at    timestamptz,
  withdrawn_at  timestamptz,
  recorded_by   integer,
  text_version  text        NOT NULL DEFAULT 'v1',
  note_ar       text,
  active_flg    boolean     NOT NULL DEFAULT true,
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at    timestamptz,
  updated_by    text,
  CONSTRAINT pk_consents PRIMARY KEY (consent_id),
  CONSTRAINT fk_con_center   FOREIGN KEY (center_id)   REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_con_guardian FOREIGN KEY (guardian_id) REFERENCES hbh.guardians (guardian_id),
  CONSTRAINT fk_con_child    FOREIGN KEY (child_id)    REFERENCES hbh.children (child_id),
  CONSTRAINT fk_con_recorder FOREIGN KEY (recorded_by) REFERENCES hbh.users (user_id),
  CONSTRAINT ck_con_type CHECK (consent_type IN ('LIVE_VIEW','SMS_NOTIFY','PHOTO_USE')),
  -- Watching a child and photographing a child are about a CHILD.
  -- Being texted is about the guardian, so it carries no child.
  CONSTRAINT ck_con_scope CHECK (
    (consent_type IN ('LIVE_VIEW','PHOTO_USE') AND child_id IS NOT NULL)
    OR (consent_type = 'SMS_NOTIFY' AND child_id IS NULL)),
  CONSTRAINT ck_con_granted CHECK ((granted_flg AND granted_at IS NOT NULL)
                                OR (NOT granted_flg)),
  CONSTRAINT ck_con_withdrawn CHECK (NOT (granted_flg AND withdrawn_at IS NOT NULL))
);

-- One current answer per guardian, per child where relevant, per type.
-- coalesce rather than NULLS NOT DISTINCT because SMS_NOTIFY's NULL is
-- a real value here - it means "about the guardian, not a child".
CREATE UNIQUE INDEX uix_consents_current
  ON hbh.consents (guardian_id, coalesce(child_id, 0), consent_type) WHERE active_flg;

CREATE INDEX ix_con_center   ON hbh.consents (center_id);
CREATE INDEX ix_con_guardian ON hbh.consents (guardian_id);
CREATE INDEX ix_con_child    ON hbh.consents (child_id);
CREATE INDEX ix_con_recorder ON hbh.consents (recorded_by);
CREATE INDEX ix_con_granted  ON hbh.consents (guardian_id, consent_type) WHERE granted_flg;

CREATE TABLE hbh.consent_events (
  event_id     bigint      GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,
  consent_id   integer     NOT NULL,
  guardian_id  integer     NOT NULL,
  child_id     integer,
  consent_type text        NOT NULL,
  action       text        NOT NULL,
  text_version text        NOT NULL,
  note_ar      text,
  recorded_by  integer,
  changed_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  changed_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pk_consent_events PRIMARY KEY (event_id),
  CONSTRAINT fk_cev_center   FOREIGN KEY (center_id)   REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_cev_consent  FOREIGN KEY (consent_id)  REFERENCES hbh.consents (consent_id),
  CONSTRAINT fk_cev_guardian FOREIGN KEY (guardian_id) REFERENCES hbh.guardians (guardian_id),
  CONSTRAINT fk_cev_child    FOREIGN KEY (child_id)    REFERENCES hbh.children (child_id),
  CONSTRAINT fk_cev_recorder FOREIGN KEY (recorded_by) REFERENCES hbh.users (user_id),
  CONSTRAINT ck_cev_action CHECK (action IN ('GRANTED','WITHDRAWN'))
);

CREATE INDEX ix_cev_center   ON hbh.consent_events (center_id, changed_at DESC);
CREATE INDEX ix_cev_consent  ON hbh.consent_events (consent_id, changed_at DESC);
CREATE INDEX ix_cev_guardian ON hbh.consent_events (guardian_id, changed_at DESC);
CREATE INDEX ix_cev_child    ON hbh.consent_events (child_id);
CREATE INDEX ix_cev_recorder ON hbh.consent_events (recorded_by);

CREATE TRIGGER trg_cev_append_only
  BEFORE UPDATE OR DELETE ON hbh.consent_events
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_append_only();

-- =====================================================================
-- THE FLAG STOPS BEING WRITABLE BY HAND
--
-- can_view_live_flg is the hot path P7 reads on every viewing request,
-- so it stays on guardian_children. What changes is that it may only
-- get there through a recorded consent - the trigger refuses any other
-- route, on INSERT as well as UPDATE.
--
-- Without the INSERT case a new link row could be created with the flag
-- already true, and the whole record would be bypassed on the one
-- occasion it matters: setting a family up for the first time.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.trg_live_flag_needs_consent()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.can_view_live_flg
     AND (TG_OP = 'INSERT' OR NOT OLD.can_view_live_flg) THEN
    IF NOT EXISTS (SELECT 1 FROM hbh.consents c
                   WHERE c.guardian_id  = NEW.guardian_id
                     AND c.child_id     = NEW.child_id
                     AND c.consent_type = 'LIVE_VIEW'
                     AND c.granted_flg AND c.active_flg) THEN
      RAISE EXCEPTION
        'can_view_live_flg needs a recorded LIVE_VIEW consent for guardian % and child %',
        NEW.guardian_id, NEW.child_id
        USING ERRCODE = 'HB081';
    END IF;
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER trg_gc_live_consent
  BEFORE INSERT OR UPDATE ON hbh.guardian_children
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_live_flag_needs_consent();

-- =====================================================================
-- RECORDING ONE
--
-- Two people may legitimately record a consent, and the row says which:
-- the guardian themselves, through the portal toggle, and centre staff
-- holding GUARDIAN.MANAGE, entering a form the family signed on paper.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.grant_consent(
  p_guardian_id  integer,
  p_consent_type text,
  p_child_id     integer DEFAULT NULL,
  p_text_version text    DEFAULT 'v1',
  p_note_ar      text    DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_g   hbh.guardians%ROWTYPE;
  l_id  integer;
BEGIN
  SELECT * INTO l_g FROM hbh.guardians WHERE guardian_id = p_guardian_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such guardian %', p_guardian_id USING ERRCODE = 'HB082';
  END IF;

  IF l_g.user_id IS DISTINCT FROM hbh.current_user_id()
     AND NOT hbh.has_permission('GUARDIAN.MANAGE') THEN
    RAISE EXCEPTION 'not permitted to record a consent for guardian %', p_guardian_id
      USING ERRCODE = 'HB082';
  END IF;

  IF p_consent_type IN ('LIVE_VIEW','PHOTO_USE') THEN
    IF p_child_id IS NULL THEN
      RAISE EXCEPTION '% is a consent about a child and needs one', p_consent_type
        USING ERRCODE = 'HB080';
    END IF;
    -- A consent about a child the guardian is not linked to would be a
    -- permission granted over somebody else's family.
    IF NOT EXISTS (SELECT 1 FROM hbh.guardian_children gc
                   WHERE gc.guardian_id = p_guardian_id AND gc.child_id = p_child_id
                     AND gc.active_flg) THEN
      RAISE EXCEPTION 'guardian % is not linked to child %', p_guardian_id, p_child_id
        USING ERRCODE = 'HB082';
    END IF;
  ELSIF p_child_id IS NOT NULL THEN
    RAISE EXCEPTION '% is a consent about the guardian and takes no child', p_consent_type
      USING ERRCODE = 'HB080';
  END IF;

  INSERT INTO hbh.consents (center_id, guardian_id, child_id, consent_type,
                            granted_flg, granted_at, withdrawn_at,
                            recorded_by, text_version, note_ar)
  VALUES (l_g.center_id, p_guardian_id, p_child_id, p_consent_type,
          true, now(), NULL, hbh.current_user_id(), p_text_version, p_note_ar)
  ON CONFLICT (guardian_id, coalesce(child_id, 0), consent_type) WHERE active_flg
  DO UPDATE SET granted_flg  = true,
                granted_at   = now(),
                withdrawn_at = NULL,
                recorded_by  = hbh.current_user_id(),
                text_version = excluded.text_version,
                note_ar      = excluded.note_ar
  RETURNING consent_id INTO l_id;

  INSERT INTO hbh.consent_events (center_id, consent_id, guardian_id, child_id, consent_type,
                                  action, text_version, note_ar, recorded_by)
  VALUES (l_g.center_id, l_id, p_guardian_id, p_child_id, p_consent_type,
          'GRANTED', p_text_version, p_note_ar, hbh.current_user_id());

  -- The operational switch follows the record, never the other way
  -- round. The trigger above now sees a granted consent and allows it.
  IF p_consent_type = 'LIVE_VIEW' THEN
    UPDATE hbh.guardian_children
       SET can_view_live_flg = true
     WHERE guardian_id = p_guardian_id AND child_id = p_child_id;
  END IF;

  RETURN l_id;
END
$$;

CREATE OR REPLACE FUNCTION hbh.withdraw_consent(
  p_guardian_id  integer,
  p_consent_type text,
  p_child_id     integer DEFAULT NULL,
  p_note_ar      text    DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_g  hbh.guardians%ROWTYPE;
  l_c  hbh.consents%ROWTYPE;
BEGIN
  SELECT * INTO l_g FROM hbh.guardians WHERE guardian_id = p_guardian_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such guardian %', p_guardian_id USING ERRCODE = 'HB082';
  END IF;

  IF l_g.user_id IS DISTINCT FROM hbh.current_user_id()
     AND NOT hbh.has_permission('GUARDIAN.MANAGE') THEN
    RAISE EXCEPTION 'not permitted to withdraw a consent for guardian %', p_guardian_id
      USING ERRCODE = 'HB082';
  END IF;

  SELECT * INTO l_c FROM hbh.consents
  WHERE guardian_id = p_guardian_id
    AND coalesce(child_id, 0) = coalesce(p_child_id, 0)
    AND consent_type = p_consent_type
    AND active_flg
  FOR UPDATE;

  IF NOT FOUND OR NOT l_c.granted_flg THEN
    RETURN false;
  END IF;

  -- The switch closes FIRST. If anything below failed, a family that
  -- said no would not be left watchable for the rest of the
  -- transaction.
  IF p_consent_type = 'LIVE_VIEW' THEN
    UPDATE hbh.guardian_children
       SET can_view_live_flg = false
     WHERE guardian_id = p_guardian_id AND child_id = p_child_id;
  END IF;

  UPDATE hbh.consents
     SET granted_flg  = false,
         withdrawn_at = now(),
         recorded_by  = hbh.current_user_id(),
         note_ar      = coalesce(p_note_ar, note_ar)
   WHERE consent_id = l_c.consent_id;

  INSERT INTO hbh.consent_events (center_id, consent_id, guardian_id, child_id, consent_type,
                                  action, text_version, note_ar, recorded_by)
  VALUES (l_g.center_id, l_c.consent_id, p_guardian_id, p_child_id, p_consent_type,
          'WITHDRAWN', l_c.text_version, p_note_ar, hbh.current_user_id());

  RETURN true;
END
$$;

CREATE OR REPLACE FUNCTION hbh.has_consent(
  p_guardian_id  integer,
  p_consent_type text,
  p_child_id     integer DEFAULT NULL)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT EXISTS (SELECT 1 FROM hbh.consents c
                 WHERE c.guardian_id = p_guardian_id
                   AND coalesce(c.child_id, 0) = coalesce(p_child_id, 0)
                   AND c.consent_type = p_consent_type
                   AND c.granted_flg AND c.active_flg)
$$;

-- =====================================================================
-- NOTIFICATIONS
-- =====================================================================
CREATE TABLE hbh.notifications (
  notification_id bigint      GENERATED ALWAYS AS IDENTITY,
  center_id       integer     NOT NULL,
  user_id         integer     NOT NULL,
  child_id        integer,
  kind_code       text        NOT NULL,
  title_ar        text        NOT NULL,
  body_ar         text,
  link_kind       text,
  link_id         integer,
  -- The portal row is always written. The text message is opt-in, and
  -- this is the flag a sender picks up.
  sms_pending_flg boolean     NOT NULL DEFAULT false,
  sms_sent_at     timestamptz,
  read_at         timestamptz,
  active_flg      boolean     NOT NULL DEFAULT true,
  deleted_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at      timestamptz,
  updated_by      text,
  CONSTRAINT pk_notifications PRIMARY KEY (notification_id),
  CONSTRAINT fk_ntf_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_ntf_user   FOREIGN KEY (user_id)   REFERENCES hbh.users (user_id),
  -- ON DELETE SET NULL: a notification is addressed to a PERSON, and
  -- the child is context. A documented compliance erasure of a child
  -- must not be blocked by a message somebody was once sent, and must
  -- not leave a dangling reference behind either.
  CONSTRAINT fk_ntf_child  FOREIGN KEY (child_id)  REFERENCES hbh.children (child_id) ON DELETE SET NULL,
  CONSTRAINT ck_ntf_kind CHECK (kind_code IN
    ('REPORT_PUBLISHED','NOTE_PUBLISHED','REQUEST_DECIDED','INVOICE_ISSUED',
     'APPOINTMENT_CANCELLED','SESSION_STARTED')),
  CONSTRAINT ck_ntf_link CHECK ((link_kind IS NULL) = (link_id IS NULL)),
  CONSTRAINT ck_ntf_sms  CHECK (NOT (sms_pending_flg AND sms_sent_at IS NOT NULL))
);

CREATE INDEX ix_ntf_center ON hbh.notifications (center_id, created_at DESC);
CREATE INDEX ix_ntf_child  ON hbh.notifications (child_id);
-- The portal's own query: my unread notifications, newest first.
CREATE INDEX ix_ntf_unread ON hbh.notifications (user_id, created_at DESC)
  WHERE read_at IS NULL AND active_flg;
CREATE INDEX ix_ntf_user   ON hbh.notifications (user_id, created_at DESC);
-- What a sender polls.
CREATE INDEX ix_ntf_sms    ON hbh.notifications (created_at)
  WHERE sms_pending_flg AND sms_sent_at IS NULL;

-- ---------------------------------------------------------------------
-- One place writes a notification
--
-- Every guardian linked to the child gets the portal row. The SMS flag
-- is set per guardian, from that guardian's own SMS_NOTIFY consent -
-- one family member may have agreed to be texted and another not.
-- ---------------------------------------------------------------------
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
DECLARE l_n integer;
BEGIN
  INSERT INTO hbh.notifications (center_id, user_id, child_id, kind_code, title_ar, body_ar,
                                 link_kind, link_id, sms_pending_flg)
  SELECT c.center_id, g.user_id, p_child_id, p_kind, p_title_ar, p_body_ar,
         p_link_kind, p_link_id,
         hbh.has_consent(g.guardian_id, 'SMS_NOTIFY')
  FROM   hbh.children c
  JOIN   hbh.guardian_children gc ON gc.child_id = c.child_id AND gc.active_flg
  JOIN   hbh.guardians g          ON g.guardian_id = gc.guardian_id AND g.active_flg
  WHERE  c.child_id = p_child_id
  AND    g.user_id IS NOT NULL;

  GET DIAGNOSTICS l_n = ROW_COUNT;
  RETURN l_n;
END
$$;

CREATE OR REPLACE FUNCTION hbh.mark_notification_read(p_notification_id bigint)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_n integer;
BEGIN
  -- Only your own, and the WHERE clause is the enforcement rather than
  -- a check the caller could forget.
  UPDATE hbh.notifications
     SET read_at = now()
   WHERE notification_id = p_notification_id
     AND user_id = hbh.current_user_id()
     AND read_at IS NULL;
  GET DIAGNOSTICS l_n = ROW_COUNT;
  RETURN l_n > 0;
END
$$;

-- =====================================================================
-- THE EVENTS THAT RAISE ONE
--
-- Triggers, not API calls. A family is told because something happened,
-- not because a handler remembered to tell them - and a second client
-- writing to the same tables cannot forget.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.trg_notify_report()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF NEW.status = 'PUBLISHED' AND OLD.status <> 'PUBLISHED' THEN
    PERFORM hbh.notify_guardians(NEW.child_id, 'REPORT_PUBLISHED',
                                 'تقرير تقدّم جديد', NEW.title_ar,
                                 'REPORT', NEW.report_id);
  END IF;
  RETURN NULL;
END
$$;

CREATE OR REPLACE FUNCTION hbh.trg_notify_note()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF NEW.visibility = 'PARENT' AND OLD.visibility <> 'PARENT' THEN
    PERFORM hbh.notify_guardians(NEW.child_id, 'NOTE_PUBLISHED',
                                 'ملاحظة جديدة من الأخصائي', NULL,
                                 'NOTE', NEW.note_id);
  END IF;
  RETURN NULL;
END
$$;

CREATE OR REPLACE FUNCTION hbh.trg_notify_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_user integer;
BEGIN
  IF NEW.status <> OLD.status AND OLD.status = 'NEW' THEN
    -- Only the guardian who asked. The other parent did not submit it
    -- and has no decision waiting for them.
    SELECT g.user_id INTO l_user FROM hbh.guardians g
    WHERE g.guardian_id = NEW.guardian_id AND g.active_flg;

    IF l_user IS NOT NULL THEN
      INSERT INTO hbh.notifications (center_id, user_id, child_id, kind_code, title_ar,
                                     body_ar, link_kind, link_id, sms_pending_flg)
      VALUES (NEW.center_id, l_user, NEW.child_id, 'REQUEST_DECIDED',
              CASE WHEN NEW.status = 'ACCEPTED' THEN 'تم قبول طلبك'
                   ELSE 'تم الردّ على طلبك' END,
              NEW.decision_note_ar, 'REQUEST', NEW.request_id,
              hbh.has_consent(NEW.guardian_id, 'SMS_NOTIFY'));
    END IF;
  END IF;
  RETURN NULL;
END
$$;

CREATE OR REPLACE FUNCTION hbh.trg_notify_invoice()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF NEW.status = 'ISSUED' AND OLD.status = 'DRAFT' THEN
    PERFORM hbh.notify_guardians(NEW.child_id, 'INVOICE_ISSUED',
                                 'فاتورة جديدة',
                                 NEW.invoice_no || ' — ' || NEW.total_amt::text
                                   || ' ' || NEW.currency_code,
                                 'INVOICE', NEW.invoice_id);
  END IF;
  RETURN NULL;
END
$$;

CREATE OR REPLACE FUNCTION hbh.trg_notify_cancelled()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF NEW.status = 'CANCELLED' AND OLD.status <> 'CANCELLED' THEN
    PERFORM hbh.notify_guardians(NEW.child_id, 'APPOINTMENT_CANCELLED',
                                 'تم إلغاء موعد', NEW.cancel_reason,
                                 'APPOINTMENT', NEW.appointment_id);
  END IF;
  RETURN NULL;
END
$$;

CREATE TRIGGER trg_reports_notify AFTER UPDATE ON hbh.progress_reports
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_notify_report();
CREATE TRIGGER trg_notes_notify AFTER UPDATE ON hbh.session_notes
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_notify_note();
CREATE TRIGGER trg_requests_notify AFTER UPDATE ON hbh.parent_requests
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_notify_request();
CREATE TRIGGER trg_invoices_notify AFTER UPDATE ON hbh.invoices
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_notify_invoice();
CREATE TRIGGER trg_appointments_notify AFTER UPDATE ON hbh.appointments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_notify_cancelled();

-- =====================================================================
-- TRIGGERS AND AUDIT
-- =====================================================================
CREATE TRIGGER trg_con_touch BEFORE UPDATE ON hbh.consents      FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_ntf_touch BEFORE UPDATE ON hbh.notifications FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

CREATE TRIGGER trg_con_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.consents
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('consent_id');

-- =====================================================================
-- ROW LEVEL SECURITY
-- =====================================================================
ALTER TABLE hbh.consents       ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.consent_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.notifications  ENABLE ROW LEVEL SECURITY;

-- A guardian sees their own consents. Staff who can see every child see
-- the centre's, because recording a paper form requires reading it.
CREATE POLICY p_con_select ON hbh.consents
  FOR SELECT TO hbh_app
  USING (
    center_id = hbh.current_center_id() AND active_flg
    AND (guardian_id IN (SELECT g.guardian_id FROM hbh.guardians g
                         WHERE g.user_id = hbh.current_user_id())
         OR hbh.has_permission('CHILD.VIEW_ALL'))
  );

CREATE POLICY p_cev_select ON hbh.consent_events
  FOR SELECT TO hbh_app
  USING (
    center_id = hbh.current_center_id()
    AND (guardian_id IN (SELECT g.guardian_id FROM hbh.guardians g
                         WHERE g.user_id = hbh.current_user_id())
         OR hbh.has_permission('CHILD.VIEW_ALL'))
  );

-- Your own notifications, and nobody else's - not even a member of
-- staff who can see the child. A notification is addressed to a person.
CREATE POLICY p_ntf_select ON hbh.notifications
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg
         AND user_id = hbh.current_user_id());

GRANT SELECT ON hbh.consents, hbh.consent_events, hbh.notifications TO hbh_app;

REVOKE ALL ON FUNCTION hbh.grant_consent(integer, text, integer, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.withdraw_consent(integer, text, integer, text)    FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.has_consent(integer, text, integer)               FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.notify_guardians(integer, text, text, text, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.mark_notification_read(bigint)                    FROM PUBLIC;

GRANT EXECUTE ON FUNCTION hbh.grant_consent(integer, text, integer, text, text) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.withdraw_consent(integer, text, integer, text)    TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.has_consent(integer, text, integer)               TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.mark_notification_read(bigint)                    TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.convention_exemptions (table_name, rule_code, reason) VALUES
  ('consent_events', 'AUDIT_COLUMNS',
   'An append-only record of one consent decision. changed_by, changed_at and recorded_by are its attribution, and a row here is never edited.'),
  ('consent_events', 'SOFT_DELETE',
   'Append-only by trigger. A hidden consent event is a family decision the centre can no longer prove, which is the one thing this table exists to prevent.');

INSERT INTO hbh.schema_migrations (version) VALUES ('0015');
