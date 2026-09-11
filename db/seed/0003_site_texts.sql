-- =====================================================================
-- Hand By Hand (new) - the marketing page's words, for migration 0092
--
-- ONE HUNDRED AND TWELVE ROWS IN TWO STATEMENTS: eighty-two here, and
-- thirty more at the bottom of the file with their own heading. Both are
-- lifted from the data-i18n keys in site/index.html so the table starts
-- saying exactly what the page already says. Nothing changes on the site
-- the moment this lands - which is the point: the screen becomes able to
-- edit the page without first changing it.
--
-- The count below describes THIS statement. The second one narrows it,
-- and says why.
--
-- NINETY-SEVEN OF THE PAGE'S 179 KEYS ARE DELIBERATELY ABSENT.
-- team, programs, faq, reviews and contact each have a table of their
-- own that already answers for those words. A row here as well would
-- give one sentence two sources, and the resolver - not a person -
-- would decide which the visitor reads.
--
-- SIX ARE LOCKED. The `live.*` keys state that a session is streamed
-- and never recorded. That is a promise about a child's privacy, and
-- the schema enforces the thing it describes; nothing in the system can
-- check PROSE, so a screen able to reword them could weaken the promise
-- in public while every guard stayed green. hbh.guard_site_text_locked
-- refuses the edit - see 0092 for the whole reasoning.
--
-- ⚠ SIXTEEN `svc.*` ROWS ARE TRUE ONLY WHILE hbh.site_services IS EMPTY.
-- They are the eight service cards written into the page, and nothing
-- else answers for those words today. The moment the catalogue is
-- seeded, the site draws its cards from hbh.services and these sixteen
-- become text nobody reads - edited, published, and invisible, with
-- nothing on screen to explain it. Archive them in the same change that
-- seeds the catalogue. Raised by the site session; noted here and on
-- SITE_TEXTS_SPEC, which is the screen somebody will be staring at.
--
-- Idempotent: ON CONFLICT DO NOTHING against the partial unique index,
-- so re-running never overwrites a sentence the centre has since
-- edited. This file seeds a starting point; it does not own the text
-- afterwards.
-- =====================================================================

INSERT INTO hbh.site_texts (center_id, text_key, text_ar, is_locked)
SELECT c.center_id, v.text_key, v.text_ar, v.is_locked
FROM   hbh.centers c
CROSS  JOIN (VALUES
  ('loading.message', 'جارٍ تحميل الموقع…', false),
  ('a11y.skip', 'تخطَّ إلى المحتوى', false),
  ('nav.services', 'خدماتنا', false),
  ('nav.programs', 'برامجنا الإضافية', false),
  ('nav.how', 'كيف تبدأ', false),
  ('nav.why', 'لماذا نحن', false),
  ('nav.portal', 'بوابة أولياء الأمور', false),
  ('nav.team', 'فريق العمل', false),
  ('nav.faq', 'أسئلة شائعة', false),
  ('nav.contact', 'تواصل معنا', false),
  ('cta.portal', 'دخول أولياء الأمور', false),
  ('cta.apply', 'طلب التحاق', false),
  ('a11y.menu', 'فتح القائمة', false),
  ('hero.lead', 'معًا', false),
  ('hero.title', 'نصنع فرقًا أكبر', false),
  ('hero.sub', 'مركز لتنمية مهارات الأطفال في مصر. جلسة لطفل واحد، خطة علاج بأهداف مكتوبة وقياس دوري، وأسرة ترى ما يحدث أولًا بأول.', false),
  ('benefit.one', 'جلسة لطفل واحد', false),
  ('benefit.team', 'فريق متخصص', false),
  ('benefit.measured', 'أهداف تُقاس', false),
  ('benefit.live', 'متابعة مباشرة', false),
  ('benefit.reports', 'تقارير تقدّم', false),
  ('cta.applyLong', 'ابدأ بطلب التحاق', false),
  ('cta.contact', 'تواصل معنا', false),
  ('portal.offline', 'بوابة أولياء الأمور قيد التجهيز للنشر. حتى ذلك الحين نستقبل طلبات الالتحاق عبر الهاتف والواتساب.', false),
  ('services.title', 'خدماتنا', false),
  ('services.sub', 'ثماني خدمات، تُبنى منها خطة الطفل بعد جلسة التقييم', false),
  ('svc.speech', 'تخاطب وتنمية لغة', false),
  ('svc.speechText', 'عمل على النطق والفهم والتعبير، وعلى وسائل تواصل بديلة عند الحاجة.', false),
  ('svc.ot', 'علاج وظيفي', false),
  ('svc.otText', 'مهارات اليد والحركة الدقيقة والاعتماد على النفس في مهام اليوم.', false),
  ('svc.aba', 'تحليل سلوك تطبيقي (ABA)', false),
  ('svc.abaText', 'برنامج سلوكي بأهداف محددة وقياس متكرر لما يتغير فعلًا.', false),
  ('svc.skills', 'مهارات', false),
  ('svc.skillsText', 'مهارات اللعب والانتباه والتنظيم الذاتي والتعامل مع الآخرين.', false),
  ('svc.assess', 'تقييم', false),
  ('svc.assessText', 'جلسة أولى نفهم فيها وضع الطفل، ومنها تُكتب الخطة وتُحدد الخدمات.', false),
  ('svc.music', 'علاج بالموسيقى', false),
  ('svc.musicText', 'الإيقاع والصوت كمدخل للانتباه المشترك والتواصل والتنظيم.', false),
  ('svc.sensory', 'تكامل حسّي', false),
  ('svc.sensoryText', 'أنشطة محسوبة للحس واللمس والتوازن حسب احتياج كل طفل.', false),
  ('svc.academic', 'أكاديمي وصعوبات تعلّم', false),
  ('svc.academicText', 'قراءة وكتابة وحساب، ودعم موازٍ لما يدرسه الطفل في مدرسته.', false),
  ('how.title', 'كيف تبدأ', false),
  ('how.sub', 'أربع خطوات من أول اتصال حتى أول جلسة', false),
  ('how.s1', 'طلب التحاق', false),
  ('how.s1Text', 'تملأ نموذجًا قصيرًا ببياناتك وبيانات الطفل وما يقلقك. لا يُنشئ الطلب ملفًا للطفل، بل ينتظر مراجعة المركز.', false),
  ('how.s2', 'اتصال من المركز', false),
  ('how.s2Text', 'نتصل بك في الوقت الذي تختاره لنسأل عمّا نحتاجه ونحدد موعد التقييم.', false),
  ('how.s3', 'جلسة تقييم', false),
  ('how.s3Text', 'جلسة مع الطفل يحضرها وليّ الأمر، نخرج منها بصورة واضحة عن نقاط القوة والاحتياج.', false),
  ('how.s4', 'خطة علاج', false),
  ('how.s4Text', 'خطة مكتوبة بأهداف محددة وجدول جلسات، تُراجع دوريًا بناءً على القياس لا على الانطباع.', false),
  ('why.title', 'لماذا Hand By Hand', false),
  ('why.sub', 'أربعة قرارات في طريقة عملنا، لا شعارات', false),
  ('why.one', 'جلسة لطفل واحد', false),
  ('why.oneText', 'لا جلسات جماعية ولا فصول. هذا اختيار وليس ظرفًا: الجلسة كلها لطفل واحد، وهكذا بُني النظام الذي يديرها.', false),
  ('why.live', 'بثّ مباشر أثناء الجلسة — ولا تسجيل', false),
  ('why.liveText', 'تتابع الأسرة الجلسة لحظة حدوثها من بوابتها. ولا شيء يُسجَّل أو يُحفظ أو يُنزَّل: المنع مفروض في قاعدة البيانات نفسها، لا في سياسة مكتوبة على ورق.', false),
  ('why.plan', 'خطة بأهداف مكتوبة وقياس دوري', false),
  ('why.planText', 'لكل طفل أهداف محددة تُقاس على فترات، وتقارير تقدّم يقرأها وليّ الأمر في بوابته.', false),
  ('why.record', 'سجلّ كامل في مكان واحد', false),
  ('why.recordText', 'كل موعد وجلسة وملاحظة وفاتورة في ملف واحد للطفل، لا في دفاتر متفرقة.', false),
  ('live.title', 'تشاهدين الجلسة وهي تحدث — ولا شيء يُسجَّل', true),
  ('live.text', 'البثّ مباشر فقط. لا يوجد تسجيل ولا مكتبة مقاطع ولا رابط تنزيل، ولا طريقة لمشاهدة الجلسة بعد انتهائها. هذه ليست إعدادًا يمكن تغييره لاحقًا؛ النظام لا يقبل تخزين مقطع من الأساس.', true),
  ('live.p1', 'الرابط يُفتح لوليّ الأمر وحده وينتهي مع الجلسة.', true),
  ('live.p2', 'لا تُعرض عناوين الكاميرات ولا بياناتها في أي صفحة.', true),
  ('live.p3', '«لحظة مهمة» تُكتب كملاحظة سريرية بوقتها، لا كمقطع محفوظ.', true),
  ('live.badge', 'مباشر', true),
  ('portal.title', 'بوابة أولياء الأمور', false),
  ('portal.sub', 'بعد تسجيل الطفل في المركز، لوليّ أمره حساب يرى منه ملف طفله وحده.', false),
  ('portal.f1', 'جدول المواعيد القادمة', false),
  ('portal.f2', 'التقدّم مقابل أهداف الخطة', false),
  ('portal.f3', 'تقارير الأخصائيين', false),
  ('portal.f4', 'البرنامج المنزلي', false),
  ('portal.f5', 'الفواتير والمدفوعات', false),
  ('portal.f6', 'البثّ المباشر أثناء الجلسة', false),
  ('portal.privacy', 'وليّ الأمر يرى بيانات طفله فقط. الصلاحية تُفحص في الخادم عند كل طلب، ولا يغيّرها تعديل الرابط.', false),
  ('band.title', 'ابدأ رحلة طفلك', false),
  ('band.text', 'املأ طلب التحاق، ونتصل بك لتحديد موعد التقييم.', false),
  ('footer.tag', 'مركز مهارات وعلاج للأطفال', false),
  ('nav.privacy', 'سياسة الخصوصية', false),
  ('footer.rights', 'جميع الحقوق محفوظة', false)
) AS v(text_key, text_ar, is_locked)
WHERE  c.code = 'HBH'
ON CONFLICT DO NOTHING;

-- =====================================================================
-- THIRTY MORE, ADDED 2026-09-11 - and the reason they were missing is
-- the point of writing them down.
--
-- These went into the database by hand, from psql, while migrating the
-- page's last written strings onto the screen. The site read correctly
-- from that moment, the console could edit all 112 keys, and every check
-- anybody ran was green - because every check ran against THIS database.
--
-- A database rebuilt from scratch would have had 82. The thirty sections
-- headings would have fallen back to what is written in index.html,
-- which is the same words - so nothing would look broken, and the
-- console would simply have thirty fewer rows than the page has keys,
-- with nothing anywhere to say why. Found by the console session, which
-- asked the only question that catches this: are the rows you published
-- in the file that builds the database?
--
-- WHY THEY ARE A SEPARATE STATEMENT and not merged into the block above:
-- that block carries no text_en at all and these thirty do. Folding them
-- in would mean adding a NULL English column to all 82, which says
-- "somebody decided there is no English here" about rows where nobody
-- decided anything.
--
-- WHY THESE THIRTY AND NOT THE OTHER SIXTY-SEVEN. The block above
-- excludes team, programs, faq, reviews and contact entirely, because
-- each has a table of its own. That rule is right for the CONTENT of
-- those sections - a testimonial, a question, a member's name - and
-- wrong for the words AROUND it. "فريق العمل" is a heading; no row in
-- hbh.site_team answers for it, and no row in any other table does
-- either. It had no source at all, which is why it was still written
-- into the page.
--
-- reviews.text0/1/2 AND person0/1/2 ARE STILL ABSENT, and must stay
-- absent. They are three families' words, they live in hbh.site_reviews
-- as DRAFT with zero recorded consent, and one of them names a child.
-- Seeding them here would make them PUBLISHED page text - publishing a
-- family's testimonial without their consent, through a side door. The
-- classification argument says they are content; this is the heavier one.
--
-- Idempotent for the same reason as the block above.
-- =====================================================================

INSERT INTO hbh.site_texts (center_id, text_key, text_ar, text_en)
SELECT c.center_id, v.text_key, v.text_ar, v.text_en
FROM   hbh.centers c
CROSS  JOIN (VALUES
  ('contact.address', 'العنوان بالتفصيل', 'Address'),
  ('contact.arrival', 'ملاحظات عن الوصول', 'Getting here'),
  ('contact.direct', 'للمكالمات المباشرة', 'For direct calls'),
  ('contact.email', 'البريد الإلكتروني', 'Email'),
  ('contact.hours', 'مواعيد العمل', 'Working hours'),
  ('contact.landline', 'الرقم المنزلي', 'Landline'),
  ('contact.map', 'فتح الموقع على الخريطة', 'Open in maps'),
  ('contact.mapNote', 'سيتم فتح الموقع في تبويب جديد على Google Maps', 'The location opens in a new Google Maps tab.'),
  ('contact.phone', 'رقم الهاتف', 'Phone'),
  ('contact.quick', 'للاستفسارات السريعة', 'For quick enquiries'),
  ('contact.sub', 'نرد خلال ساعات العمل', 'We answer during working hours'),
  ('contact.title', 'تواصل معنا', 'Contact us'),
  ('contact.whatsapp', 'واتساب', 'WhatsApp'),
  ('faq.title', 'أسئلة شائعة', 'Frequently asked questions'),
  ('programs.ask', 'استفسر عن التوافر والمواعيد المناسبة', 'Ask about availability and suitable times'),
  ('programs.badge', 'فرص أكبر .. لتنمية شاملة', 'More opportunities for all-round development'),
  ('programs.contact', 'تواصل معنا لمعرفة المزيد من البرامج', 'Contact us to learn more about the programmes'),
  ('programs.more', 'المزيد', 'More details'),
  ('programs.sub', 'لأن احتياجات كل طفل مختلفة، نوفر مجموعة من البرامج والأنشطة المتخصصة التي تدعم نموه في مختلف الجوانب.', 'Every child has different needs. Our specialised programmes and activities support growth in different areas.'),
  ('programs.title', 'برامجنا الإضافية', 'Our additional programmes'),
  ('reviews.badge', 'قصص حقيقية', 'Real stories'),
  ('reviews.guardian', 'ولي أمر', 'Parent'),
  ('reviews.sub', 'مكان مخصص لآراء حقيقية، تُنشر بموافقة أصحابها', 'A place for real reviews, published with their authors’ consent'),
  ('reviews.title', 'آراء أولياء الأمور', 'What parents say'),
  ('reviews.trust', 'ثقتكم هي قصتنا', 'Your trust is our story'),
  ('team.profile', 'عرض الملف المهني', 'View professional profile'),
  ('team.promise', 'نعمل معًا من أجل مستقبل أفضل لأطفالنا', 'Working together for a better future for our children'),
  ('team.quran.details', 'عرض تفاصيل الجلسات', 'View session details'),
  ('team.sub', 'أخصائيون في التخاطب والعلاج الوظيفي وتحليل السلوك والتكامل الحسي', 'Specialists in speech, occupational therapy, behaviour analysis and sensory integration'),
  ('team.title', 'فريق العمل', 'Our team')
) AS v(text_key, text_ar, text_en)
WHERE  c.code = 'HBH'
ON CONFLICT DO NOTHING;
