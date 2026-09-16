-- =====================================================================
-- 0148 down - a reminder goes back to being its title.
--
-- The trigger is put back FIRST, while the helper it would call still
-- exists; dropping the helper first leaves a live trigger that raises on
-- the next reminder, inside whatever transaction was notifying a family.
--
-- Outbox rows already written with the two reminder codes stay. They
-- record what was sent, and withdrawing the rendering does not make that
-- untrue.
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

DROP FUNCTION IF EXISTS hbh.appointment_reminder_message(integer);
DROP FUNCTION IF EXISTS hbh.weekday_ar(date);

DELETE FROM hbh.schema_migrations WHERE version = '0148';
