-- =====================================================================
-- Hand By Hand (new) - seed: payment plans (OD-33, 11-FEAT §15 PP-D1)
--
-- In the seed and not in 0142, because it reads hbh.centers - empty when
-- migrations run on a rebuilt database.
--
-- FULL is the default in every centre: pay the invoice at once, on the
-- invoice's own due date. That is exactly what every invoice did before
-- 0142, so introducing plans changes nothing until a centre chooses to.
--
-- DEPOSIT_50 is seeded ACTIVE (OD-38): half on issue, the other half
-- after 6 COMPLETED sessions. Until layer B counts sessions, that second
-- instalment stays PENDING and nobody is told about it - correct, not a
-- gap (11-FEAT §17.5).
--
-- ONLY WHEN THE CENTRE HAS NO DEPOSIT_50 AT ALL. A seed runs on every
-- migrate; one that re-activated a plan a centre had deliberately retired
-- or left in draft would overrule the console every time anyone deployed.
-- =====================================================================
INSERT INTO hbh.payment_plans (center_id, code, name_ar, kind, status, is_default_flg)
SELECT c.center_id, 'FULL', 'سداد كامل', 'FULL', 'ACTIVE',
       NOT EXISTS (SELECT 1 FROM hbh.payment_plans d WHERE d.center_id = c.center_id AND d.is_default_flg)
FROM   hbh.centers c
WHERE  c.active_flg
  AND  NOT EXISTS (SELECT 1 FROM hbh.payment_plans p
                   WHERE p.center_id = c.center_id AND p.code = 'FULL' AND p.active_flg);

-- Three statements per centre, in order, because the plan must exist as
-- DRAFT to take its instalment and must have it to become ACTIVE.
DO $seed$
DECLARE c record; l_plan integer;
BEGIN
  FOR c IN SELECT center_id FROM hbh.centers
           WHERE active_flg
             AND NOT EXISTS (SELECT 1 FROM hbh.payment_plans p
                             WHERE p.center_id = centers.center_id AND p.code = 'DEPOSIT_50')
  LOOP
    INSERT INTO hbh.payment_plans (center_id, code, name_ar, kind, deposit_pct, status)
    VALUES (c.center_id, 'DEPOSIT_50', 'مقدَّم ٥٠٪ والباقي بعد ٦ جلسات', 'DEPOSIT_PERCENT', 50, 'DRAFT')
    RETURNING plan_id INTO l_plan;

    INSERT INTO hbh.payment_plan_installments (plan_id, center_id, seq, amount_kind, amount_value, due_kind, due_value)
    VALUES (l_plan, c.center_id, 1, 'PERCENT', 50, 'AFTER_SESSIONS', 6);

    UPDATE hbh.payment_plans SET status = 'ACTIVE' WHERE plan_id = l_plan;
  END LOOP;
END
$seed$;
