-- =====================================================================
-- Hand By Hand (new) - seed: WhatsApp message templates (migration 0153)
--
-- In the seed and not in 0153, because it reads hbh.centers - empty when
-- migrations run on a rebuilt database.
--
-- ONLY WHAT IS MISSING. A seed runs on every migrate; one that rewrote a
-- template the centre had edited, or reset an APPROVED row to DRAFT,
-- would overrule the owner every time anybody deployed. A row is inserted
-- for a centre that has no active row of that key, and never touched
-- again from here.
--
-- EVERY ROW STARTS AS DRAFT WITH NO ContentSid. Nothing has been approved
-- by Meta; the text below is what is submitted. The texts are those in
-- docs/08-whatsapp-templates.md, and the variable counts are the contract
-- with the code that fills them - see 0153's header.
-- =====================================================================

-- ---------------------------------------------------------------------
-- The permission. CENTER_ADMIN alone: the wording a family receives from
-- the centre, and the Meta ids it is sent under, are the owner's to
-- change - not reception's and not a therapist's.
-- ---------------------------------------------------------------------
INSERT INTO hbh.permissions (code, name_ar, name_en) VALUES
  ('MESSAGE_TEMPLATE.EDIT', 'تعديل قوالب رسائل واتساب', 'Edit WhatsApp message templates')
ON CONFLICT (code) DO NOTHING;

INSERT INTO hbh.role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM   hbh.roles r
JOIN   hbh.permissions p ON p.code = 'MESSAGE_TEMPLATE.EDIT'
WHERE  r.code = 'CENTER_ADMIN'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- The templates
-- ---------------------------------------------------------------------
INSERT INTO hbh.message_templates
  (center_id, template_key, category, var_count, var_labels_ar, body_ar, button_text_ar, button_url)
SELECT c.center_id, t.template_key, t.category, t.var_count, t.var_labels_ar,
       t.body_ar, t.button_text_ar, t.button_url
FROM   hbh.centers c
CROSS  JOIN (VALUES
  ('OTP_LOGIN', 'AUTHENTICATION', 1::smallint,
   ARRAY['رمز الدخول']::text[],
   NULL::text, NULL::text, NULL::text),

  ('APPOINTMENT_REMINDER', 'UTILITY', 4::smallint,
   ARRAY['اسم الطفل', 'اليوم', 'التاريخ', 'الساعة']::text[],
   E'مركز هاند باي هاند للمهارات 🌸\n'
   'نذكّركم بموعد جلسة {{1}} يوم {{2}} الموافق {{3}} الساعة {{4}}.\n'
   'في حالة الاعتذار يُرجى إبلاغنا برسالة كتابية على واتساب قبل الموعد، حتى نتمكّن من تعويض الجلسة. التعويض داخل فترة الاشتراك نفسها وخارج المواعيد الأصلية.\n'
   'شكرًا لثقتكم.',
   NULL, NULL),

  ('APPOINTMENT_REMINDER_RESCHEDULED', 'UTILITY', 5::smallint,
   ARRAY['اسم الطفل', 'اليوم', 'التاريخ', 'الساعة', 'يوم الموعد الأصلي']::text[],
   E'مركز هاند باي هاند للمهارات 🌸\n'
   'نذكّركم بموعد جلسة {{1}} يوم {{2}} الموافق {{3}} الساعة {{4}}.\n'
   '(هذا موعد مؤقت بدلًا من يوم {{5}} بناءً على طلبكم، ومواعيدكم الأصلية كما هي.)\n'
   'في حالة الاعتذار يُرجى إبلاغنا برسالة كتابية على واتساب قبل الموعد، حتى نتمكّن من تعويض الجلسة. التعويض داخل فترة الاشتراك نفسها وخارج المواعيد الأصلية.\n'
   'شكرًا لثقتكم.',
   NULL, NULL),

  ('ENROLMENT_ASSESSMENT', 'UTILITY', 3::smallint,
   ARRAY['اسم وليّ الأمر', 'اسم الطفل', 'الموعد']::text[],
   E'مركز هاند باي هاند للمهارات 🌸\n'
   'أهلًا {{1}}، تم تحديد موعد المقابلة الأولى لـ{{2}} يوم {{3}}.\n'
   'في انتظاركم.',
   NULL, NULL),

  ('PORTAL_UPDATE', 'UTILITY', 1::smallint,
   ARRAY['عنوان الإشعار']::text[],
   E'مركز هاند باي هاند للمهارات 🌸\n'
   'لديكم تحديث جديد: {{1}}.\n'
   'تجدون التفاصيل في بوّابة ولي الأمر.',
   'افتح البوابة', 'https://portal.hbhskills.com/'),

  ('PORTAL_INVITATION', 'UTILITY', 1::smallint,
   ARRAY['آخر أربعة أرقام من الموبايل']::text[],
   E'مركز هاند باي هاند للمهارات 🌸\n'
   'يسعدنا إبلاغكم بأن حسابكم على بوّابة ولي الأمر الجديدة أصبح جاهزًا.\n'
   'من خلالها تتابعون مواعيد الجلسات، وتقارير التقدّم، وملاحظات الأخصائي، والفواتير.\n'
   'للدخول استخدموا رقم الموبايل المسجّل لدينا المنتهي بـ {{1}}، وسيصلكم رمز الدخول على واتساب.\n'
   'شكرًا لثقتكم.',
   'افتح البوابة', 'https://portal.hbhskills.com/')
) AS t(template_key, category, var_count, var_labels_ar, body_ar, button_text_ar, button_url)
WHERE  c.active_flg
AND    NOT EXISTS (SELECT 1 FROM hbh.message_templates m
                   WHERE m.center_id = c.center_id
                   AND   m.template_key = t.template_key
                   AND   m.active_flg);

-- A seed that inserts nothing reports success. Say so out loud when a
-- centre is left without its templates.
DO $check$
DECLARE l_missing integer;
BEGIN
  SELECT count(*) INTO l_missing
  FROM   hbh.centers c
  WHERE  c.active_flg
  AND    (SELECT count(*) FROM hbh.message_templates m
          WHERE m.center_id = c.center_id AND m.active_flg) < 6;
  IF l_missing > 0 THEN
    RAISE EXCEPTION '% active centre(s) are missing message templates after seeding', l_missing;
  END IF;
END
$check$;
