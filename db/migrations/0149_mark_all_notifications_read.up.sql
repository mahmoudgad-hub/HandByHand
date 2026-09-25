-- =====================================================================
-- Hand By Hand (new) - migration 0149: mark every notification read.
--
-- Owner's list, item 24. The screen had "mark as read" one row at a time
-- (hbh.mark_notification_read, bigint) and nothing for the whole list.
--
-- SHAPE. Built like the single-row function, on purpose:
--   * own rows only, and the WHERE clause is the enforcement - there is no
--     id argument, so there is nothing to point at another family or
--     another centre;
--   * returns how many rows it marked, so the screen can say so. 0 is an
--     answer ("nothing was unread"), not a refusal.
--   * active rows only. A soft-deleted notification is not on the screen,
--     and counting it would make the number disagree with the list the
--     person just looked at.
--
-- NO IDENTITY IS A VISIBLE REFUSAL, not "zero rows". user_id = NULL would
-- match nothing and return 0, which reads as success. HB180 is the code
-- this schema already raises for 'no identity' (0058) and the API already
-- maps it by name to 403. No new SQLSTATE, so nothing has to land first.
--
-- HB032 was proposed for this and is NOT used: in pg_proc it means a
-- session-note publish refusal, and one code with two meanings is what
-- 0140 removed.
--
-- The batch UPDATE fires trg_ntf_touch (BEFORE UPDATE, per row) and
-- nothing else: trg_ntf_enqueue_sms is AFTER INSERT only, so marking read
-- sends no SMS.
-- =====================================================================

CREATE FUNCTION hbh.mark_all_notifications_read()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_user integer := hbh.current_user_id();
  l_n    integer;
BEGIN
  IF l_user IS NULL THEN
    RAISE EXCEPTION 'no identity' USING ERRCODE = 'HB180';
  END IF;

  UPDATE hbh.notifications
     SET read_at = now()
   WHERE user_id = l_user
     AND active_flg
     AND read_at IS NULL;
  GET DIAGNOSTICS l_n = ROW_COUNT;
  RETURN l_n;
END
$$;

REVOKE ALL ON FUNCTION hbh.mark_all_notifications_read() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.mark_all_notifications_read() TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0149');
