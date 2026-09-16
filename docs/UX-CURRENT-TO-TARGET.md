# UX-CURRENT-TO-TARGET — مراجعة الوضع الحالي

**2026-09-14 · تحليل فقط، لا تنفيذ معتمد.** القسم الأعلى هو المرجع الحالي. التحليل السابق محفوظ في آخر الملف للأرشفة ولا يمثل العمل المتبقي.

**العدد الحالي: 49 شاشة تطبيق = 31 للمركز + 18 للبوابة. المستهدف: 47 = 31 + 16، بدمجين مقترحين في البوابة.** نعد كل route يرسم شاشة بما فيه الدخول والرفض والطباعة ونمطا إنشاء/تحرير التقرير؛ لا نعد shell أو redirects أو wildcard. لذلك هذا عدد مسارات شاشات وليس عدد المكونات أو بنود القائمة. الموقع العام site يضيف صفحتين، فيصير الإجمالي الموسع 51 → 49. website/index.html وhtml/ وfigma/ مراجع منفصلة لا يثبت وجودها أنها تشغيل فعلي.

**صفر حالات مستخدمة كصفحات انتظار مستقلة.** /live أداة مشاهدة قائمة، لا حالة متنكرة في شاشة. /my-day كان فلترًا بمسار وأصبح redirect بالفعل. لا صفحات انتظار ولي أمر/إسناد أخصائي في routes الحالية.

**حدود الإثبات:** جرد ساكن لكل routes ومصادر النماذج والأفعال وAPI، وتحليل للمنطق في Go والمهاجرات المتاحة، مع مشاهدة حية للدخول ولوحة المدير والمهام. لم تُختبر كل شاشة وكل دور عمليًا، ولم تُنفذ كتابة أعمال أو إرسال رسائل. تعذرت قراءة 0005_scheduling.up.sql و0006_plans_and_notes.up.sql بصلاحيات البيئة؛ لا ندعي اكتمال تدقيق SQL. تشغيل DB الحي قد يختلف عن ملفات الهجرة. تفاصيل الأدلة في [UX-AUDIT-SOURCE-INDEX.md](UX-AUDIT-SOURCE-INDEX.md)، والمسارات المحسوبة في [UX-AUDIT-ROUTES.json](UX-AUDIT-ROUTES.json).

## كل Route حالي

| Current | Problem | Target | Action |
| --- | --- | --- | --- |
| ops /login | شاشة أساسية/تفصيل قائم | ops /login | KEEP |
| ops /communications | شاشة أساسية/تفصيل قائم | ops /communications | KEEP |
| ops /tasks | شاشة أساسية/تفصيل قائم | ops /tasks | KEEP |
| ops /notifications | شاشة أساسية/تفصيل قائم | ops /notifications | KEEP |
| ops /dashboard | شاشة أساسية/تفصيل قائم | ops /dashboard | KEEP |
| ops /guardians | شاشة أساسية/تفصيل قائم | ops /guardians | KEEP |
| ops /guardians/:guardianId | شاشة أساسية/تفصيل قائم | ops /guardians/:guardianId | KEEP |
| ops /children | شاشة أساسية/تفصيل قائم | ops /children | KEEP |
| ops /children/:childId | شاشة أساسية/تفصيل قائم | ops /children/:childId | KEEP |
| ops /children/:childId/reports/new | شاشة أساسية/تفصيل قائم | ops /children/:childId/reports/new | KEEP |
| ops /children/:childId/reports/:reportId | شاشة أساسية/تفصيل قائم | ops /children/:childId/reports/:reportId | KEEP |
| ops /children/:childId/card | شاشة أساسية/تفصيل قائم | ops /children/:childId/card | KEEP |
| ops /therapists | شاشة أساسية/تفصيل قائم | ops /therapists | KEEP |
| ops /rooms | شاشة أساسية/تفصيل قائم | ops /rooms | KEEP |
| ops /plans | شاشة أساسية/تفصيل قائم | ops /plans | KEEP |
| ops /catalog | شاشة أساسية/تفصيل قائم | ops /catalog | KEEP |
| ops /site | شاشة أساسية/تفصيل قائم | ops /site | KEEP |
| ops /appointments | شاشة أساسية/تفصيل قائم | ops /appointments | KEEP |
| ops /sessions | شاشة أساسية/تفصيل قائم | ops /sessions | KEEP |
| ops /reports | شاشة أساسية/تفصيل قائم | ops /reports | KEEP |
| ops /billing | شاشة أساسية/تفصيل قائم | ops /billing | KEEP |
| ops /requests | شاشة أساسية/تفصيل قائم | ops /requests | KEEP |
| ops /enrolments/:applicationId | شاشة أساسية/تفصيل قائم | ops /enrolments/:applicationId | KEEP |
| ops /enrolments | شاشة أساسية/تفصيل قائم | ops /enrolments | KEEP |
| ops /therapists/:therapistId/profile | شاشة أساسية/تفصيل قائم | ops /therapists/:therapistId/profile | KEEP |
| ops /sessions/:sessionId/live | شاشة أساسية/تفصيل قائم | ops /sessions/:sessionId/live | KEEP |
| ops /users | شاشة أساسية/تفصيل قائم | ops /users | KEEP |
| ops /satisfaction | شاشة أساسية/تفصيل قائم | ops /satisfaction | KEEP |
| ops /ops-log | شاشة أساسية/تفصيل قائم | ops /ops-log | KEEP |
| ops /settings | شاشة أساسية/تفصيل قائم | ops /settings | KEEP |
| ops /denied | شاشة أساسية/تفصيل قائم | ops /denied | KEEP |
| portal /login | شاشة أساسية/تفصيل قائم | portal /login | KEEP |
| portal /login/otp | شاشة أساسية/تفصيل قائم | portal /login/otp | KEEP |
| portal /apply | شاشة أساسية/تفصيل قائم | portal /apply | KEEP |
| portal /welcome | شاشة أساسية/تفصيل قائم | portal /welcome | KEEP |
| portal /communications | وجهة إضافية لرسائل الأسرة | portal /requests?tab=messages | MERGE + redirect |
| portal /home | شاشة أساسية/تفصيل قائم | portal /home | KEEP |
| portal /schedule | شاشة أساسية/تفصيل قائم | portal /schedule | KEEP |
| portal /progress | شاشة أساسية/تفصيل قائم | portal /progress | KEEP |
| portal /activities | شاشة أساسية/تفصيل قائم | portal /activities | KEEP |
| portal /live | شاشة أساسية/تفصيل قائم | portal /live | KEEP |
| portal /consultation/:appointmentId | شاشة أساسية/تفصيل قائم | portal /consultation/:appointmentId | KEEP |
| portal /reports | متابعة الطفل موزعة | portal /progress?tab=reports | MERGE + redirect |
| portal /reports/:reportId | شاشة أساسية/تفصيل قائم | portal /reports/:reportId | KEEP |
| portal /billing | شاشة أساسية/تفصيل قائم | portal /billing | KEEP |
| portal /requests | شاشة أساسية/تفصيل قائم | portal /requests | KEEP |
| portal /therapists/:therapistId | شاشة أساسية/تفصيل قائم | portal /therapists/:therapistId | KEEP |
| portal /notifications | شاشة أساسية/تفصيل قائم | portal /notifications | KEEP |
| portal /profile | شاشة أساسية/تفصيل قائم | portal /profile | KEEP |

## Redirects قائمة تبقى

| Current | Problem | Target | Action |
| --- | --- | --- | --- |
| ops /inbox | رابط قديم/افتراضي | 'notifications' | KEEP |
| ops /therapist-services | رابط قديم/افتراضي | movedTo('/therapists', { tab: 'services' }) | KEEP |
| ops /site/team | رابط قديم/افتراضي | movedTo('/site', { tab: 'team' }) | KEEP |
| ops /my-day | رابط قديم/افتراضي | movedTo('/appointments', { view: 'mine' }) | KEEP |
| ops /access | رابط قديم/افتراضي | 'users' | KEEP |
| ops / | رابط قديم/افتراضي | '/dashboard' | KEEP |
| ops /** | رابط قديم/افتراضي | '/dashboard' | KEEP |
| portal /otp | رابط قديم/افتراضي | 'login/otp' | KEEP |
| portal / | رابط قديم/افتراضي | '/welcome' | KEEP |
| portal /** | رابط قديم/افتراضي | '/welcome' | KEEP |

## قواعد الدمج

/reports → /progress?tab=reports مع الحفاظ على notes إذا كان مطلوبًا؛ /reports/:reportId يبقى مع back link جديد. /communications → /requests?tab=messages؛ انقل تحقق اختيار الطفل إلى تبويب طلباته، فلا يُغلق مسار رسائل الأسرة. احتفظ بمعاملات focus/status/view/tab/open وreturnUrl داخلي وallowlist للaction. لا بيانات أسر شخصية في query.

الثلاثة /my-day و/therapist-services و/site/team دمجات تاريخية منفذة وليست ضمن الدمجين المتبقيين. /access و/inbox إعادة تسمية وتوجيه، لا شاشتان حاليًا للحذف. لا تغييرات routes مطبقة بهذه المراجعة.


<details>
<summary>أرشيف التحليل السابق — غير معتمد كوصف للحالة الحالية أو تكليف تنفيذ</summary>

# UX Current → Target Mapping

**المرحلة ١٠.** كل عنصر حالي ← مشكلته ← هدفه ← الفعل المطلوب. **الفعل على الواجهة فقط**؛ ما يحتاج الخادم موسوم `R-xx` (توصية في `UX-PROBLEMS.md` §و) ولا يُنفَّذ في الواجهة قبل مساره. الرموز: `REDIRECT` = يبقى المسار القديم بإعادة توجيه · `RENAME` = تسمية/ترجمة فقط · `MOVE` = يغيّر مكانه في القائمة · `MERGE` = يصير تبويبًا/عرضًا · `NEW` = شاشة/عنصر جديد على نداءات قائمة · `HIDE` = يُخفى من الواجهة لأنه بلا مسار · `KEEP` = بلا تغيير.

---

## ١ · كونسول المركز

| Current | Problem | Target | Action |
|---|---|---|---|
| القائمة الجانبية (22 بندًا مسطّحًا، بلا شارات) | لا تعكس النطاقات ولا دورة العمل؛ لا إشارة لما ينتظر | 8 مجموعات · 3 بنود علوية · شارتان (المهامّ، الإشعارات) | `nav.ts`: تجميع + شارتان تقرآن `/tasks` (عدّ) و`/notifications?limit=1` (`unread`) |
| `/inbox` «صندوق الوارد» | سجلّ إشعارات باسم يوحي بالمهامّ؛ رابط `INVOICE` → `/invoices` ميّت | `/notifications` «الإشعارات» | `RENAME` + `REDIRECT /inbox → /notifications` + إصلاح `inbox-api.ts target(INVOICE)` → `/billing?open=` |
| — | لا مكان لما يحتاج إجراءً | `/tasks` «المهامّ» | `NEW` — يجمع القراءات القائمة بفلاتر الحالة (كتالوج K-01…K-23 في `UX-TASK-INBOX.md`)؛ CTA يفتح الحوارات القائمة؛ (R-06 اختياري لاحقًا) |
| لوحة «التنبيهات والمتابعة» + بطاقات `wantsAction` في الداشبورد | عدّ لا قائمة؛ مصدر ثانٍ محتمل للمهامّ | معاينة أوّل 5 مهامّ + بطاقات تربط إلى `/tasks?type=` | `MERGE` على مصدر `/tasks` |
| بطاقة «الغرف» وبطاقة «التنبيهات» بلا قراءة | تعرض ما لا مصدر له | تُخفى حتى يوجد مصدر | `HIDE` |
| `/children` (أولياء الأمور + الأطفال) | كيانان تحت اسم أحدهما؛ وليّ الأمر بلا مسار | `/children` «المستفيدون» · `/guardians` «أولياء الأمور» | `RENAME` (واجهة فقط، `BL-45`) · `NEW /guardians` من `GUARDIANS_SPEC` + master-detail القائم |
| master-detail أولياء الأمور المضمَّن في التبويب | تفصيل بلا مسار | `/guardians/:id` DETAIL PAGE | `NEW` (`UX-DETAIL-PAGES.md` §٢) على القراءات القائمة |
| `/children/:id` للقراءة | الاستقبال يقفز 3–5 شاشات | رأس بـCTA وقائمة أفعال؛ تبويب «الخطّة» مركز العمل؛ «الأخصائي المسؤول»؛ إعادة تسمية `activityLog` | `NEW` أفعال تفتح حوارات `DayScreen`/`ResourceScreen` القائمة مسبوقة التعبئة · `RENAME` التبويب · 🔴 مكانان محجوزان (التقييمات، الخطّ الزمني) لا يُرسمان |
| `/enrolments` (صفّ + حوار) | لا تفصيل لأوّل كيان في الرحلة | `/enrolments` + `/enrolments/:id` | `NEW` DETAIL PAGE (§١) على `GET /enrolments/{id}` + الحوارات القائمة؛ CTA حسب الحالة من قائمة الانتقالات نفسها |
| «حجز التقييم» = تغيير حالة يدوي | حالة وموعد قد يفترقان | زرّ «احجز التقييم» يفتح الحجز ثم يغيّر الحالة | واجهة: نداءان بالترتيب · R-04 للربط |
| `/my-day` | فلتر بمسار ومدخل قائمة | `/appointments?view=mine` (افتراضي لصاحب `therapistId`) | `MERGE` + `REDIRECT` + حارس `/appointments` = `APPOINTMENT.BOOK` ∨ `SESSION.START` (الأفعال تبقى مفلترة بصلاحيتها) |
| `/appointments` لوحتا «بانتظار التأكيد» و«تداخلات» | مهامّ مخفيّة في disclosure | تبقيان + تُعرَّفان كمهامّ K-04/K-20 | `KEEP` + ربط بالمهامّ |
| تعديل الموعد حوار فقط؛ لا تاريخ حالات | لا سياق | درج جانبي `?open=:id` (تفصيل + سجلّ + أفعال) | `NEW` درج؛ السجلّ 🟡 حتى قراءة (`v_case_timeline`/مسار صغير) |
| `/sessions` (بدء في «يومي»، إغلاق هنا، نشر في الطفل) | عمل واحد على ثلاث شاشات | صفّ الجلسة يعرض الموعد + الملاحظة + نشرها | `MERGE` أفعال قائمة في صفّ واحد (النداءات نفسها) |
| `/therapist-services` | تبويب بمسار | تبويب «الخدمات» في `/therapists` | `MERGE` + `REDIRECT` |
| `/therapists` › «إسناد الحالات» (CRUD) | مهمّة تُدار من الجدول الخطأ | التبويب يبقى للقراءة؛ الفعل من ملفّ المستفيد + مهمّة K-16 | `KEEP` + `NEW` زرّ في الملفّ يفتح حوار `CASELOAD_SPEC` مسبوقًا |
| `/therapists/:id/profile` بالرابط فقط للأخصائي | لا يعرف أن له ملفًّا | بند «ملفّي» | `NEW` بند قائمة (شرط `therapistId`) |
| `/plans` (4 تبويبات، 4 منتقيات رقمية) | مفهرسة بالكيان لا بالطفل (`BL-32`) | `/plans` قائمة عبر الأطفال؛ التفصيل في تبويب «الخطّة» بالملفّ | `MOVE` الأهداف/القياسات/البرنامج إلى الملفّ (نفس `Spec`s بـ`plan_id`/`child_id` مثبَّتين) |
| `/reports` لا يفتح التقرير | نشر بلا قراءة | صفّ → المحرّر | `NEW` رابط |
| `/billing` (حوارات؛ لا تفصيل؛ حذف السطر بلا زرّ) | — | درج جانبي للفاتورة + زرّ حذف السطر | `NEW` درج · `NEW` زرّ على `removeInvoiceLine` القائم |
| تبويب «الباقات والأسعار» | الأسعار في الكتالوج | «الباقات والأرصدة» | `RENAME` |
| `/requests` قبول «تغيير موعد» بلا حجز | القرار على شاشة والحجز على أخرى | «قبول» يفتح حوار الحجز مسبوق التعبئة | واجهة: تسلسل · R-03 للربط |
| `/communications` | أيقونة وصلاحية = الطلبات | أيقونة مختلفة تحت «التواصل» | `KEEP` + أيقونة |
| `/catalog` › «استبيانات الرضا» | كيان على شاشتين | تبويب في «رضا الأسر» | `MOVE` (نفس `NPS_SURVEYS_SPEC`) |
| `/satisfaction` | نتائج فقط؛ حارس خطأ | «رضا الأسر»: الاستبيانات · النتائج؛ حارس `NPS.MANAGE` | `MERGE` + R-10 |
| `/site/team` | تبويب بمسار ومدخل قائمة؛ اسمه يُخلط بالموظّفين | تبويب «الفريق على الموقع» في `/site` | `MERGE` + `REDIRECT` + `RENAME` |
| `/access` «الصلاحيات والشاشات» | إدارة مستخدمين بحارس الجميع وثلاث وظائف | `/users` «المستخدمون والأدوار» (المستخدمون · الأدوار · ملفّات الموظّفين · الشاشات)؛ حارس `USER.MANAGE`؛ تبويب الموظّفين بـ`STAFF.PII` | `RENAME` + `REDIRECT` + فصل التبويب + R-10 |
| `/settings` حارس `CATALOG.MANAGE` | يسمّي غير ما تفحصه القاعدة | «بارامترات المركز» بـ`SETTINGS.MANAGE` تحت «الإعدادات» | `MOVE` + R-10 |
| `/rooms` · `/ops-log` | مبعثرة | تحت «الإعدادات» | `MOVE` |
| `/denied` لا يعرض `need` | رفض بلا سبب | يعرض الصلاحية المطلوبة بالاسم | `KEEP` + عرض |
| `status.child.*` بلا `INACTIVE` | تسمية ناقصة | إضافة | `RENAME` (i18n) |
| نصوص عربية مضمَّنة | يمنع لغة ثانية | ملفّ الترجمة | خارج نطاق التجربة — يُسجَّل |

## ٢ · بوّابة وليّ الأمر

| Current | Problem | Target | Action |
|---|---|---|---|
| شريط الهاتف (5) يخفي 6 شاشات؛ الجرس عريض فقط | لا وصول | الرئيسية · المواعيد · متابعة طفلي · البرنامج المنزلي · **المزيد** (الفواتير · طلباتي · رسائل المركز · الإشعارات · حسابي)؛ جرس في رأس الهاتف | `shell`: تبويب «المزيد» + جرس |
| `/welcome` منتقي بمسار خارج الغلاف | خطوة زائدة لكل دخول | مبدّل مستفيد في الرأس؛ `/welcome` لأوّل دخول/عدّة أطفال | `NEW` مبدّل · `KEEP` المسار |
| «ما يحتاج انتباهك» في `/welcome` (نوعان فقط؛ يتعطّل مع >1 طفل) | مهامّ الأسرة في المكان الخطأ ونصفها معطَّل | في الرئيسية، لكل الأطفال، 5 أنواع | `MOVE` + إصلاح التوجيه بالطفل |
| `/schedule` «طلب تغيير» يقفز إلى `/requests` بلا موعد | الطلب على `children[0]` دائمًا | حوار طلب من الصفّ مربوط بالموعد والطفل | `NEW` حوار على `POST /children/{id}/requests` بـ`appointment_id` |
| `/progress` + `/reports` (+ الملاحظات) | متابعة واحدة على ثلاث شاشات | `/progress?tab=progress|reports|notes` «متابعة طفلي» | `MERGE` + `REDIRECT /reports → /progress?tab=reports` (`/reports/:id` يبقى) |
| رسم التقدّم لا يُرسم (سلسلة فارغة) | عنصر ميّت | يُخفى حتى توجد قراءة | `HIDE` |
| `/communications` = مكوّن الموظّفين | شاشة استقبال في بوّابة أسرة | تبويب «رسائل المركز» في طلباتي بمكوّن أسرة (محادثة واحدة على النقاط نفسها) | `NEW` مكوّن أسرة + `REDIRECT` |
| `<a href="/communications">` خام | إعادة تحميل | `routerLink` | إصلاح |
| `/requests` مفردات `SUBMITTED/UNDER_REVIEW/DECLINED` | لا مصدر لها | مفردات القاعدة | R-12 (طبقة النقل) + i18n |
| `/billing` «طرق الدفع» toast | وعد بلا فعل | نصّ صادق «الدفع في المركز — تواصل معنا» حتى `FE-07` | `RENAME` |
| `/consultation` «لم تُسدَّد» → `/billing` | طريق مسدود | → «طلباتي/مكالمة» بنصّ صادق حتى `FE-07` | تغيير الوجهة |
| `/live` «لحظة مهمّة» | يفشل دائمًا (403 محلّيًّا) | يُحذف من واجهة الأسرة | `HIDE` |
| `/profile` مفاتيح الموافقة | تفشل دائمًا (405 محلّيًّا)؛ مفتاحان بلا مصدر | عرض للقراءة: «تُدار من المركز» | `HIDE` الأفعال |
| `/activities` إلغاء التعليم | لا يُكتب | يُخفى حتى R-09 | `HIDE` |
| `AppointmentStatus` بلا `CHECKED_IN` | موعد حضر بلا تسمية | إضافة «حضر» | i18n + النموذج |
| `/therapists/:id` `back: true` | رابط غير صالح | `back: '/schedule'` | إصلاح |
| `AlertsService` | كود ميّت | يُزال | تنظيف (لا سلوك) |

## ٣ · جدول إعادة التوجيه (Deep Links القديمة)

| المسار القديم | الجديد | ملاحظة |
|---|---|---|
| `/inbox` | `/notifications` | الإشعارات والرسائل القديمة تشير إليه |
| `/my-day` | `/appointments?view=mine` | |
| `/therapist-services` | `/therapists?tab=services` | |
| `/site/team` | `/site?tab=team` | |
| `/access` | `/users` | |
| `/invoices` (رابط الإشعار الميّت) | `/billing?open=:id` | كان يسقط على `/dashboard` |
| `/children` | يبقى (اسم العرض «المستفيدون») | |
| البوّابة `/reports` | `/progress?tab=reports` | `/reports/:id` يبقى (الإشعارات تشير إليه) |
| البوّابة `/communications` | `/requests?tab=messages` | |
| البوّابة `/otp` | `/login/otp` | قائم |

**ما لا يتغيّر إطلاقًا:** كل مسار في `server.go` · كل نداء في `core/api/*` و`day-api.ts` · كل `Spec` (تُعاد الإشارة إليها من أماكن جديدة فقط) · آلات الحالة المنسوخة في `day-spec.ts` · قاعدة «لا معرّف طفل في مسار البوّابة» · `sessionStorage` · قاعدة 401/403.

</details>
