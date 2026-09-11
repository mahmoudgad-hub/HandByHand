-- =====================================================================
-- 0115 down - the outbox loses its off switch
--
-- The view goes before the function it reads, for the reason written in
-- 0112's down: the whole file is one transaction, so a drop that fails
-- on a dependency drops NOTHING and the rebuild quietly keeps the old
-- definitions.
--
-- claim_sms goes back to its 0109 body - the one WITH template_vars.
-- Restoring 0094's would take the WhatsApp template columns out of the
-- worker's hands, which belongs to another change entirely.
--
-- sys_params.SMS_SENDING_ENABLED is NOT deleted. It is seeded, not
-- created here, and a row whose only effect is gone does nothing;
-- removing it would also throw away an operator's deliberate 'false' on
-- the way past.
-- =====================================================================

\set ON_ERROR_STOP on

DROP VIEW IF EXISTS hbh.v_sms_health;

CREATE OR REPLACE FUNCTION hbh.claim_sms(p_limit integer, p_worker text)
RETURNS TABLE(sms_id bigint, purpose text, template_code text,
              destination text, body_ar text, template_vars jsonb,
              attempts smallint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
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
$fn$;

REVOKE ALL ON FUNCTION hbh.claim_sms(integer, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.claim_sms(integer, text) TO hbh_app;

DELETE FROM hbh.schema_migrations WHERE version = '0115';
