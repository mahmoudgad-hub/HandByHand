-- =====================================================================
-- Hand By Hand (new) - migration 0148: an appointment reminder says
-- whose session it is, and when.
--
-- WHAT A FAMILY RECEIVED BEFORE THIS. "تذكير بموعد قادم" - and nothing
-- else. The centre, meanwhile, was writing the real reminder by hand on
-- WhatsApp: the child, the day, the date, the hour, and, when a session
-- had been moved, that this one is temporary and the regular slots stand.
-- This makes the automatic reminder carry what the manual one carried,
-- within the owner's decisions of 2026-09-16 (D-42):
--
--   * the child's name and the centre's name MAY reach the handset;
--   * no amount, no offer, no numbers from the cancellation policy;
--   * no "session N of M" - an appointment is not linked to a package, so
--     the number would be a guess, and a wrong number in a message about
--     a paid course starts an argument about the course.
--
-- WHAT THIS OVERRULES, SAID PLAINLY. 0094 wrote that nothing reaching a
-- phone names a family or a children's therapy centre, because the phone
-- has no gate in front of it. That was a rule, not an accident, and the
-- owner has decided otherwise for reminders - which is recorded in D-42
-- rather than left for the next reader to find as a contradiction. It is
-- NOT relaxed for anything else here: every other notification kind still
-- reaches the phone as its title and a pointer to the portal.
--
-- WHY IN THE TRIGGER AND NOT IN queue_appointment_reminders. The reminder
-- goes through notify_guardians, which is the one writer for consent, the
-- portal row and the SMS intent (0015, 0111). Rendering the message there
-- would mean a second path that has to remember consent. The trigger
-- already receives the notification with link_kind = 'APPOINTMENT' and the
-- appointment id, so it can build the message from the appointment itself,
-- and every rule about WHO is told stays exactly where it was.
--
-- TWO TEMPLATE CODES, BECAUSE WHATSAPP WILL NOT TAKE AN EMPTY VARIABLE.
-- "This is a temporary slot instead of Tuesday" appears only for a moved
-- session. A single template with that sentence as a variable would need
-- the variable blank for every ordinary reminder, and Meta refuses a blank
-- variable. So:
--
--   APPOINTMENT_REMINDER             {{1}} child  {{2}} day  {{3}} date  {{4}} time
--   APPOINTMENT_REMINDER_RESCHEDULED the same, and {{5}} the original day
--
-- Neither code is mapped in TWILIO_CONTENT_SIDS yet. Until it is, a
-- WhatsApp sender refuses these as CONFIG and names the code - the same
-- honest failure as any other unapproved template. No Go change is needed
-- and no SQLSTATE is added, so the API does not have to deploy first.
--
-- THE SMS BODY IS SHORTER THAN THE WHATSAPP TEMPLATE, ON PURPOSE. The
-- cancellation paragraph lives in the approved WhatsApp template's fixed
-- text. Arabic SMS is UCS-2, 70 characters a segment, and that paragraph
-- alone is four segments on every reminder to every family.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0148') THEN
    RAISE EXCEPTION 'migration 0148 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0147') THEN
    RAISE EXCEPTION 'migration 0147 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- THE DAY, IN ARABIC
--
-- By ISO day of week and not by to_char(..., 'TMDay'): TMDay follows the
-- server's lc_time, which is not Arabic here and is not this migration's
-- to set. A reminder that says "Sunday" to a family is a reminder that
-- was tested on a different machine.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.weekday_ar(p_day date)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = hbh, pg_catalog
AS $$
  SELECT (ARRAY['الاثنين','الثلاثاء','الأربعاء','الخميس',
                'الجمعة','السبت','الأحد'])[extract(isodow FROM p_day)::integer]
$$;

-- =====================================================================
-- THE MESSAGE, BUILT FROM THE APPOINTMENT
--
-- Returns no row when there is nothing to build from - the appointment is
-- gone, or its child is. The caller then falls back to the plain title,
-- which is what a family received before this and is still true.
--
-- Stored UTC, printed in the centre's own zone (hbh.centers.time_zone, NOT
-- NULL, so there is no literal zone to fall back to and none is written).
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.appointment_reminder_message(p_appointment_id integer)
RETURNS TABLE (template_code text, template_vars jsonb, body_ar text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_child   text;
  l_center  text;
  l_tz      text;
  l_start   timestamptz;
  l_from    integer;
  l_local   timestamp;
  l_orig    timestamptz;
  l_day     text;
  l_date    text;
  l_time    text;
  l_origday text;
  l_body    text;
BEGIN
  SELECT c.full_name_ar, ce.name_ar, ce.time_zone, a.starts_at,
         a.rescheduled_from_appointment_id
    INTO l_child, l_center, l_tz, l_start, l_from
  FROM   hbh.appointments a
  JOIN   hbh.children c  ON c.child_id   = a.child_id
  JOIN   hbh.centers  ce ON ce.center_id = a.center_id
  WHERE  a.appointment_id = p_appointment_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  l_local := l_start AT TIME ZONE l_tz;
  l_day   := hbh.weekday_ar(l_local::date);
  l_date  := to_char(l_local, 'DD/MM/YYYY');
  -- 12-hour with the Arabic period, the way the centre writes it.
  l_time  := to_char(l_local, 'FMHH12:MI')
             || CASE WHEN extract(hour FROM l_local) < 12 THEN ' صباحًا' ELSE ' مساءً' END;

  l_body := l_center || ': تذكير بموعد جلسة ' || l_child || ' يوم ' || l_day
            || ' ' || l_date || ' الساعة ' || l_time || '.';

  IF l_from IS NOT NULL THEN
    SELECT a.starts_at INTO l_orig FROM hbh.appointments a
    WHERE  a.appointment_id = l_from;
  END IF;

  -- A reschedule whose original row cannot be read is sent as an ordinary
  -- reminder rather than as "instead of" nothing. The date and time are
  -- still right; only the explanation is missing.
  IF l_orig IS NULL THEN
    RETURN QUERY SELECT 'APPOINTMENT_REMINDER'::text,
                        jsonb_build_array(l_child, l_day, l_date, l_time),
                        l_body;
    RETURN;
  END IF;

  l_origday := hbh.weekday_ar((l_orig AT TIME ZONE l_tz)::date);
  l_body := l_body || ' (موعد مؤقت بدلًا من يوم ' || l_origday
            || '، ومواعيدكم الأصلية كما هي.)';

  RETURN QUERY SELECT 'APPOINTMENT_REMINDER_RESCHEDULED'::text,
                      jsonb_build_array(l_child, l_day, l_date, l_time, l_origday),
                      l_body;
END
$$;

-- Internal. Its caller is a trigger; nothing on hbh_app reaches it.
REVOKE ALL ON FUNCTION hbh.appointment_reminder_message(integer) FROM PUBLIC;

-- =====================================================================
-- THE TRIGGER USES IT FOR REMINDERS, AND ONLY FOR REMINDERS
--
-- Carried forward from 0109 unchanged except for the one branch. Every
-- other kind still sends its title and a pointer to the portal.
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
  l_code   text;
  l_vars   jsonb;
  l_msg    record;
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

  l_code := NEW.kind_code;
  l_body := NEW.title_ar || ' — تابع التفاصيل من بوّابة ولي الأمر.';
  l_vars := jsonb_build_array(NEW.title_ar);

  IF NEW.kind_code = 'APPOINTMENT_REMINDER'
     AND NEW.link_kind = 'APPOINTMENT' AND NEW.link_id IS NOT NULL THEN
    SELECT * INTO l_msg FROM hbh.appointment_reminder_message(NEW.link_id);
    IF FOUND THEN
      l_code := l_msg.template_code;
      l_vars := l_msg.template_vars;
      l_body := l_msg.body_ar;
    END IF;
  END IF;

  PERFORM hbh.enqueue_sms(
    NEW.center_id, 'NOTIFICATION', l_code, l_mobile,
    'NTF:' || NEW.notification_id::text, l_body, NEW.notification_id, 'PENDING',
    l_vars);

  RETURN NULL;
END
$$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0148');
