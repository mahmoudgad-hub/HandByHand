-- =====================================================================
-- 0111 down - the channel stops being a question and SMS_NOTIFY governs
-- again.
--
-- ORDER MATTERS HERE. notify_guardians is put back FIRST, while
-- WHATSAPP_NOTIFY rows are still legal. Narrowing ck_con_type first
-- would fail against any consent a family has already granted and take
-- the whole reversal with it - nothing dropped, the function still
-- reading a parameter that is about to vanish, and a schema that looks
-- reverted from the outside.
--
-- AND THE CONSTRAINT IS NOT NARROWED AT ALL. A granted WHATSAPP_NOTIFY
-- row is a family's recorded answer to a question the centre actually
-- asked them. Deleting it to make a CHECK pass would destroy consent
-- evidence to tidy up a schema, which is the wrong way round; leaving it
-- while forbidding its type would leave rows their own constraint
-- rejects. So the type stays permitted and stops being ASKED for, which
-- is the whole of what this reversal needs to mean.
--
-- NOTIFY_CHANNEL is retired rather than deleted, for D-3: nothing in
-- this schema is hard deleted, and a parameter that was once set is
-- worth being able to see was once set.
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

UPDATE hbh.sys_params
   SET active_flg = false, deleted_at = now()
 WHERE center_id IS NULL AND param_code = 'NOTIFY_CHANNEL';

DELETE FROM hbh.schema_migrations WHERE version = '0111';
