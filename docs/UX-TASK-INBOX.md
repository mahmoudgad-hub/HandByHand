# UX-TASK-INBOX — مراجعة الوضع الحالي

**2026-09-14 · تحليل فقط، لا تنفيذ معتمد.** القسم الأعلى هو المرجع الحالي. التحليل السابق محفوظ في آخر الملف للأرشفة ولا يمثل العمل المتبقي.

## الموجود

/tasks موجودة، و/notifications منفصلة؛ /inbox redirect إليها. **14 نوعًا فعليًا** في task-catalog.ts. المشاهدة الحية عرضت 12 عنصرًا للمدير وقت الفحص، وليس 12 نوعًا. لا جدول ولا endpoint Tasks ولا زر إغلاق مهمة مستقل.

| Type | Business Object | Permission |
| --- | --- | --- |
| ENROLMENT_TRIAGE | APPLICATION | ENROLMENT.MANAGE |
| ENROLMENT_BOOK_ASSESSMENT | APPLICATION | ENROLMENT.MANAGE |
| ENROLMENT_CONVERT | APPLICATION | ENROLMENT.MANAGE |
| APPOINTMENT_CONFIRM | APPOINTMENT | APPOINTMENT.BOOK |
| APPOINTMENT_CHECK_IN | APPOINTMENT | APPOINTMENT.BOOK |
| SESSION_START | APPOINTMENT | SESSION.START |
| SESSION_CLOSE | SESSION | SESSION.COMPLETE |
| REPORT_FINISH | REPORT | REPORT.WRITE |
| REQUEST_DECIDE | REQUEST | REQUEST.MANAGE |
| INVOICE_ISSUE | INVOICE | BILLING.MANAGE |
| INVOICE_OVERDUE | INVOICE | BILLING.VIEW |
| CHILD_ASSIGN_THERAPIST | BENEFICIARY | STAFF.MANAGE |
| THERAPIST_PROFILE_CONSENT | THERAPIST | PORTAL.VIEW |
| SCHEDULE_CONFLICT | APPOINTMENT | APPOINTMENT.BOOK |

## مصادر الأنواع وأفعالها

TRIAGE: NEW → الطلب/contact. BOOK_ASSESSMENT: CONTACTED → الطلب/book-assessment مع فجوة R01. CONVERT: ASSESSMENT_BOOKED → convert، مع بقاء التحويل من CONTACTED في السجل. CONFIRM: BOOKED اليوم؛ CHECK_IN: CONFIRMED وفق within(15min)؛ START: CHECKED_IN بلا session؛ CLOSE: IN_PROGRESS اليوم؛ REPORT_FINISH: DRAFT؛ REQUEST_DECIDE: NEW؛ INVOICE_ISSUE: DRAFT؛ OVERDUE: ISSUED/PARTIALLY_PAID وdue_date قبل اليوم؛ CHILD_ASSIGN: ACTIVE بلا caseload في العينة؛ PROFILE_CONSENT: ملف الأخصائي نفسه DRAFT دون consent_at؛ CONFLICT: زوج مواعيد اليوم متداخلان في غرفة أو أخصائي.

## شكل العنصر

Type، كيان ومعرفه، Parent/Child عند توافرهما، الحالة الأصلية، الإجراء المطلوب، أولوية عرض، دور مؤهل، شخص مسند فقط إن أثبته المصدر، Due Date حقيقي أو غير محدد، CTA ورابط أصل السجل. assignedRole الحالي permission code لا تكليف بشخص. لا تصنع dueDate من عمر الطلب؛ عتبات 24/72 ساعة ليست SLA معتمدة.

## التحسين المطلوب

- اقرأ صفحات كل مصدر حتى الاكتمال أو أظهر incomplete وعددًا جزئيًا؛ لا تشتق عدم إسناد من عينة 200 caseload.
- failed مستقل عن incomplete وعن empty. الشارة والداشبورد والشاشة من نفس المصدر والعد.
- SESSION_CLOSE لا يدعي شمول العمل الماضي وهو يقرأ اليوم فقط؛ النطاق الزمني واضح.
- CTA الإسناد يفتح ملف الطفل والحوار الحالي مع child_id؛ الفعل يعيد قراءة الحالة ويتأكد من صلاحيتها.
- صاحب BILLING.VIEW وحدها يرى الفواتير في الماليات؛ لا مهمة تحصيل بلا إجراء مسموح ولا منح BILLING.MANAGE. لا escalation API مخترع.
- TasksService.load يشترك داخليًا ثم يعيد Observable باردًا؛ الاشتراك اللاحق يمكن أن يكرر القراءات. وحّد رحلة القراءة دون تغيير العقود.
- لا تنفذ mutation من action query؛ افتح dialog مع تأكيد المستخدم فقط.

## المرشحات غير المنفذة

ثمانية: SESSION_NOTE، CONSENT_MISSING، PACKAGE_RENEW، PLAN_APPROVE، GUARDIAN_GRANT_PORTAL، PROFILE_INCOMPLETE، INSTALLMENT_DUE، SITE_PUBLISH. منها ما يحتاج API/بيانات/سياسة ومنها مؤجل؛ ليست «19 مهمة جاهزة» كما قال التحليل القديم. فئة consultation assignment/receipt review/hold extend مستقبلية خارج الأربعة عشر.

## المهام والإشعارات

المهمة حالة تتطلب فعلًا وتنتهي بتغير السجل؛ الإشعار حدث محفوظ يُعلّم مقروءًا. قراءة إشعار تقرير لا تنجز مهمة نشر/حجز/دفع. تذكير موعد أو تقرير غير مقروء لا يدخل المهام تلقائيًا. للأسرة إنجاز نشاط منزلي فعل مثبت؛ بطاقات الانتباه الأخرى تسمى تنبيهات عندما لا تتطلب فعلًا مثبتًا.


<details>
<summary>أرشيف التحليل السابق — غير معتمد كوصف للحالة الحالية أو تكليف تنفيذ</summary>

# UX Task Inbox — إعادة تعريف «صندوق الوارد»

**المرحلة ٥.** ما هو الوارد الحالي، ولماذا لا يصلح صندوق مهامّ، وما البنية المقترحة لصندوق مهامّ **يُشتقّ من الحالات القائمة** بلا جدول جديد ولا كتابة جديدة — ثم الفصل الصريح بين المهامّ والإشعارات.

---

## ١ · ما هو الوارد الحالي — بالدليل

| الخاصية | الكونسول `/inbox` | البوّابة `/notifications` |
|---|---|---|
| المصدر | `GET /api/v1/notifications` (سياسة RLS: `user_id = current_user_id()`) | نفسه |
| الأفعال | تعليم مقروء · فتح الهدف | نفسه |
| الفلاتر | «غير المقروء فقط» | لا شيء |
| هل ينكمش حين يُنجَز العمل؟ | **لا** — الصفّ يبقى، يُعلَّم مقروءًا فقط | لا |
| ما لا يظهر فيه | طلب `NEW`، فاتورة متأخّرة، تقرير مسودّة، طفل بلا أخصائي… (لأن **لا مُنتِج** لإشعارات `STAFF_ENROLMENT_NEW` و`STAFF_REQUEST_NEW` أصلًا — 5 أنواع معلَنة بلا مصدر) | — |
| التعريف الذاتي في الكود | `inbox.ts:18-41`: «**ليس لوحة.** اللوحة تعيد الحساب وتنكمش حين يُنجَز العمل؛ الوارد سجلّ يكبر فقط. خلطهما هو الطريقة التي تبدأ بها قائمة المهامّ في الكذب عمّا لم يُنجَز بعد» | — |

**الحكم:** الوارد الحالي **Notification Inbox خالص** — والكود على حقّ في رفض تحويله إلى لوحة. المشكلة أن اسمه «صندوق الوارد» يوحي بأنه مكان «ما عليّ فعله»، وأن **لا مكان آخر** لذلك: بذور صندوق المهامّ الحقيقي متناثرة في ثلاثة مواضع —

1. لوحة «التنبيهات والمتابعة» في الداشبورد: 4 بطاقات `wantsAction` (التحاق جديد · طلبات جديدة · تقارير مسودّة · فواتير غير مسدّدة) — **عدّ** لا قائمة.
2. لوحة «متابعة مواعيد اليوم» في `/appointments`: «بانتظار التأكيد» + «تداخلات» — قائمة، لكن مخفيّة في disclosure على شاشة واحدة.
3. لوحة «يومك» في الداشبورد للأخصائي: الجلسة القادمة/الجارية + زرّ البدء.

فالجواب ليس «تعديل الوارد» بل **شاشتان**: **الإشعارات** (الوارد الحالي باسمه الصحيح) و**المهامّ** (جديدة، مشتقّة).

---

## ٢ · البنية المقترحة — Task Inbox

### ٢.١ · المبدأ

> **المهمّة = حالة في القاعدة + شرط + صلاحية.** لا صفّ يُكتب، لا جدول `tasks`، لا «إغلاق مهمّة». حين تتغيّر الحالة تختفي المهمّة وحدها. هذا هو السبب في أن الشاشة **لن تكذب**: مصدرها نفس مصدر الشاشة التي تُنجَز فيها.

**من أين تُقرأ اليوم بلا أيّ تغيير في الخادم:** كل مهمّة في الجدول أدناه مبنيّة على نداء قائم بفلتر قائم (`GET /enrolments?status=NEW`، `GET /appointments?date=today&status=BOOKED`، `GET /invoices?status=ISSUED&to=yesterday`…). صندوق المهامّ الأوّل = **تجميع القراءات القائمة** في شاشة واحدة، بالضبط كما تفعل بطاقات الداشبورد اليوم (`limit=1 → total`) لكن بالقائمة لا بالعدّ.

**التحسين اللاحق (توصية R-06):** عرض `hbh.v_staff_tasks` بـ`security_invoker` يجمع الصفوف نفسها بعمود `task_kind` وصلاحية كل مهمّة — نداء واحد بدل 8–12، والصلاحية تُفحص في السياسة لا في الشاشة. **ليس شرطًا للمرحلة الأولى.**

### ٢.٢ · شكل العنصر (Task Item)

| الحقل | المصدر | مثال |
|---|---|---|
| **Type** (نوع المهمّة) | ثابت لكل صفّ في الكتالوج (§٢.٣) | `ENROLMENT_TRIAGE` |
| **Business Object** (الكيان + رقمه) | الصفّ المقروء | طلب التحاق `ENR-2026-01029` |
| **Parent / Child** (الأسرة/المستفيد) | أعمدة الصفّ (`parent_name_ar`, `child_name_ar` أو `child.full_name_ar`) | أحمد محمود · وليّ الأمر: محمود سعيد |
| **Current Status** | حالة الصفّ + تسميتها من ملفّ الترجمة | `NEW` — جديد |
| **Required Action** | نصّ ثابت لكل نوع | «راجع الطلب وتواصل مع الأسرة» |
| **Priority** | مشتقّة: عمر الصفّ مقابل عتبة (بارامتر `sys_params` حين يُبنى؛ حتى ذلك: ثابت لكل نوع) | عاجل / عادي |
| **Assigned Role / User** | الصلاحية التي تُظهر النوع (من `/me`)؛ للأخصائي: `therapist_id = me` | استقبال · أو: أنا |
| **Due Date** | إن كان للصفّ تاريخ (موعد: `starts_at` · فاتورة: `due_date` · قسط: `due_date`) وإلّا فراغ | اليوم 10:00 |
| **CTA** | زرّ واحد يفتح **نفس الحوار/الشاشة** التي تُنجِز الفعل اليوم | [فتح الطلب] · [تأكيد الموعد] · [بدء الجلسة] |
| **رابط الكيان** | دائمًا، إلى شاشة التفصيل (أو الصفّ المفلتر حتى تُبنى) | → `/enrolments/ENR-…` |

**قاعدتان:** (١) **لا مهمّة بلا CTA يُنجِزها** — عنصر يسمّي شيئًا ولا يفتحه هو الإشعار الذي رفضه الكود؛ (٢) **من أيّ مهمّة تصل إلى الكيان الأصلي** بنقرة واحدة (القاعدة ١٠ من التكليف).

### ٢.٣ · كتالوج المهامّ — من الحالات القائمة

| # | Type | المصدر (حالة + شرط) | الصلاحية (من يراها) | Required Action | CTA (يفتح ما هو موجود اليوم) | متاح الآن؟ |
|---|---|---|---|---|---|---|
| K-01 | `ENROLMENT_TRIAGE` | `enrolments.status = NEW` | `ENROLMENT.MANAGE` | مراجعة الطلب والتواصل | تغيير الحالة (حوار `ENROLMENTS_SPEC.status`) | ✅ |
| K-02 | `ENROLMENT_BOOK_ASSESSMENT` | `status = CONTACTED` | `ENROLMENT.MANAGE` + `APPOINTMENT.BOOK` | حجز موعد التقييم | حوار الحجز مسبوق التعبئة → ثم الحالة | ✅ (نداءان متتاليان؛ R-04 يربطهما) |
| K-03 | `ENROLMENT_CONVERT` | `status IN (CONTACTED, ASSESSMENT_BOOKED)` **و**(إن رُبط) موعد التقييم `COMPLETED` | `ENROLMENT.MANAGE` | التحويل إلى ملفّ | حوار `convert` | ✅ (الشرط الثاني بعد R-04) |
| K-04 | `APPOINTMENT_CONFIRM` | `appointments.date = today AND status = BOOKED` | `APPOINTMENT.BOOK` | تأكيد الموعد | حوار الحالة → `CONFIRMED` | ✅ (لوحة «بانتظار التأكيد» اليوم) |
| K-05 | `APPOINTMENT_CHECK_IN` | `status = CONFIRMED AND starts_at <= now + X min` | `APPOINTMENT.BOOK` | تسجيل الحضور | حوار الحالة → `CHECKED_IN` | ✅ |
| K-06 | `SESSION_START` | `status = CHECKED_IN AND session_id IS NULL AND therapist_id = me` | `SESSION.START` | بدء الجلسة | `POST /appointments/{id}/session` | ✅ (لوحة «يومك») |
| K-07 | `SESSION_CLOSE` | `sessions.status = IN_PROGRESS AND therapist_id = me` (أو المدير: الكلّ) | `SESSION.COMPLETE` | إغلاق الجلسة | حوار الإغلاق | ✅ |
| K-08 | `SESSION_NOTE` | `sessions.status = COMPLETED AND note IS NULL AND therapist_id = me` | `SESSION.NOTES.EDIT` | كتابة ملاحظة الجلسة | حوار الملاحظة | ✅ (يحتاج `GET /sessions` أن يُرجع وجود الملاحظة — إن لم يكن، توصية صغيرة) |
| K-09 | `REPORT_FINISH` | `reports.status = DRAFT` (الأخصائي: تقاريره؛ المدير: الكلّ) | `REPORT.WRITE` / `REPORT.PUBLISH` | إكمال ونشر | محرّر التقرير | ✅ |
| K-10 | `REQUEST_DECIDE` | `requests.status = NEW` | `REQUEST.MANAGE` | البتّ في الطلب | حوار القرار (+ الحجز عند قبول تغيير موعد) | ✅ |
| K-11 | `INVOICE_ISSUE` | `invoices.status = DRAFT` | `BILLING.MANAGE` | إصدار الفاتورة | حوار الإصدار | ✅ |
| K-12 | `INVOICE_OVERDUE` | `status IN (ISSUED, PARTIALLY_PAID) AND due_date < today` | `BILLING.MANAGE` (المدير) · `BILLING.VIEW` للمتابعة | تحصيل | حوار الدفعة | ✅ (`GET /invoices?status=&to=`) |
| K-13 | `INSTALLMENT_DUE` | `invoice_installments.status IN (DUE, OVERDUE)` | `BILLING.MANAGE` | تحصيل قسط | حوار الدفعة | 🟡 بعد مسار الأقساط (0142 بلا API) |
| K-14 | `PACKAGE_RENEW` | `child_packages.status = ACTIVE AND (sessions_left <= n OR expires_on <= today + d)` | `BILLING.MANAGE` | تجديد الباقة | حوار بيع باقة مسبوق التعبئة | ✅ (من دفتر «أرصدة الجلسات») |
| K-15 | `PLAN_APPROVE` | `plans.status = DRAFT` | `PLAN.MANAGE` (المدير) | اعتماد الخطّة | **لا فعل اليوم** — بعد R-02 | 🟡 |
| K-16 | `CHILD_ASSIGN_THERAPIST` | طفل `ACTIVE` بلا صفّ `caseload` (للخدمة المحجوزة) | `STAFF.MANAGE` | تعيين أخصائي | حوار إسناد (نفس CRUD `caseload`) مسبوق بالطفل | ✅ (يحتاج قراءتين) |
| K-17 | `GUARDIAN_GRANT_PORTAL` | وليّ أمر `user_id IS NULL` وله طفل نشط | `GUARDIAN.MANAGE` | منح حساب البوّابة | بعد R-05 | 🟡 |
| K-18 | `CONSENT_MISSING` | طفل يُطلب له بثّ/صورة بلا موافقة | `GUARDIAN.MANAGE` | تسجيل الموافقة | تبويب أولياء الأمور في الملفّ | ✅ (يظهر عند الرفض `CONSENT_REQUIRED`) |
| K-19 | `THERAPIST_PROFILE_CONSENT` | `therapists.profile_status = DRAFT AND consent IS NULL AND therapist_id = me` | (الأخصائي نفسه) | الموافقة على نشر الملفّ | `/therapists/{me}/profile` | ✅ |
| K-20 | `SCHEDULE_CONFLICT` | تداخل أخصائي/غرفة بين مواعيد اليوم الحيّة | `APPOINTMENT.BOOK` | فضّ التعارض | فتح اليوم على الموعدين | ✅ (لوحة «تداخلات») |
| K-21 | `PROFILE_INCOMPLETE` | `guardians.record_completeness <> COMPLETE` | `GUARDIAN.MANAGE` | استكمال بيانات الأسرة | تفصيل وليّ الأمر | 🟡 بعد `EN-06` |
| K-22 | 🔴 `CONSULTATION_ASSIGN` · `RECEIPT_REVIEW` · `HOLD_EXTEND` | FEAT 09/10 | `REQUEST.MANAGE` · `BILLING.RECEIPT_REVIEW` · `BILLING.HOLD_EXTEND` | تعيين · مراجعة (المتأخّر أوّلًا) · تمديد | حين تُبنى | 🔴 |
| K-23 | `SITE_PUBLISH` | `site_*.status = DRAFT` (اختياري، ثقل منخفض) | `SITE.PUBLISH` | نشر المحتوى | `/site` | ✅ |

**19 مهمّة متاحة الآن من القراءات القائمة، 4 بعد توصيات backend صغيرة، وفئة مخطَّطة.**

### ٢.٤ · الشاشة

- **المسار:** `/tasks` (عربي: **المهامّ**) · أوّل بند في القائمة بعد لوحة التحكم · **شارة بالعدد** في القائمة (مجموع المهامّ التي أراها).
- **التجميع الافتراضي:** حسب الدور تلقائيًّا (من `/me`): الاستقبال يرى الالتحاق/المواعيد/الطلبات أوّلًا؛ الأخصائي يرى جلساته وملاحظاته وتقاريره؛ المدير يرى الاعتمادات والتحصيل والإسناد — **بلا منطق عمل**: الشاشة تعرض ما تسمح به الصلاحيات، والترتيب تفضيل عرض.
- **الفلاتر:** النوع · العاجل فقط · «لي» (الأخصائي) · اليوم/هذا الأسبوع.
- **الترتيب:** العاجل ثم الأقدم (المتأخّر أوّلًا — القاعدة نفسها المكتوبة لطابور الإيصالات في `09` `FE-13`).
- **الحالات الأربع الإلزامية:** تحميل · فشل (مع إعادة) · **فارغ إيجابي** («لا شيء ينتظرك الآن») · بيانات. فارغ ≠ خطأ.
- **العدّ في الداشبورد** يبقى (بطاقات) لكنه يربط إلى `/tasks?type=`، ولوحة «التنبيهات والمتابعة» تصير **معاينة أوّل 5 مهامّ** من نفس المصدر — مصدر واحد، لا نسختان.
- **لوحة «بانتظار التأكيد» و«تداخلات»** في المواعيد تبقى كما هي (السياق نفسه)، لكنها تقرأ من نفس التعريفات (K-04, K-20).

### ٢.٥ · مثالان بالشكل النهائي

```
┌──────────────────────────────────────────────────────────────┐
│ ● طلب التحاق جديد                                 منذ ٣ ساعات │
│   المستفيد: أحمد محمود · وليّ الأمر: محمود سعيد · 01012345678 │
│   الحالة: جديد                                                 │
│   المطلوب: مراجعة الطلب والتواصل مع الأسرة                    │
│   [فتح الطلب]                              [تمّ التواصل ▾]     │
└──────────────────────────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────────┐
│ ● موعد بانتظار التأكيد                          اليوم ١٠:٠٠  │
│   سارة علي · تخاطب · أ. منى · غرفة ٢                          │
│   الحالة: محجوز                                                │
│   المطلوب: تأكيد الموعد مع الأسرة                              │
│   [تأكيد]  [إلغاء…]                        → عرض في المواعيد   │
└──────────────────────────────────────────────────────────────┘
```

---

## ٣ · المهامّ مقابل الإشعارات — الفصل

| | **المهامّ** `/tasks` | **الإشعارات** `/notifications` (الوارد الحالي) |
|---|---|---|
| السؤال الذي تجيبه | ماذا **عليّ** أن أفعل الآن؟ | ماذا **حدث** ويخصّني؟ |
| المصدر | حالة + شرط في جداول العمل (مشتقّة) | صفوف `notifications` (مكتوبة بالمشغّلات والصيانة) |
| تنكمش؟ | نعم — حين تتغيّر الحالة | لا — تُعلَّم مقروءة فقط |
| هل لها CTA يُنجِز؟ | **دائمًا** | رابط للقراءة (قد لا يوجد) |
| العدّ | مهامّ مفتوحة | غير مقروء |
| من يراها | بالصلاحية (وللأخصائي: صفوفه) | صاحبها فقط (`user_id`) |
| مثال | «فاتورة `INV-…` متأخّرة ١٢ يومًا — [سجّل دفعة]» | «نُشر تقرير لسارة» · «أُسند إليك طفل جديد» |
| ما لا يدخلها | حدث وقع بلا فعل مطلوب | شيء لم يُنجَز بعد |

**اختبار العضوية:** «هل تختفي وحدها حين أُنجِز شيئًا في مكان آخر؟» نعم → مهمّة. لا → إشعار.

**ما يُطلب تغييره في الوارد الحالي (واجهة فقط):** الاسم «الإشعارات»؛ إصلاح رابط `INVOICE`؛ الإبقاء على كل شيء آخر. **ولا يُنقل** أيّ إشعار إلى المهامّ — الإشعارات الخمسة بلا مُنتِج (R-08) ستُغني الإشعارات حين تُبنى، ولن تكون مهامّ.

---

## ٤ · صندوق مهامّ الأسرة (البوّابة)

نفس المبدأ بحجم أصغر — موجود جزئيًّا باسم «ما يحتاج انتباهك» في `/welcome` (INVOICE, ACTIVITY فقط تُنتج؛ REPORT/REQUEST مصمَّمة ولا تُنتج، وتتعطّل مع أكثر من طفل):

| مهمّة الأسرة | المصدر | CTA |
|---|---|---|
| فاتورة مستحقّة | `balance.outstanding > 0` | → الفواتير (حتى تُبنى `FE-07`: «تواصل مع المركز») |
| نشاط اليوم لم يُسجَّل | `activities` غير منجَز اليوم | → البرنامج المنزلي |
| تقرير جديد لم يُقرأ | `reports.unread` | → التقرير |
| موعد غدًا (تذكير) | `appointments` القادمة | → المواعيد |
| استشارة يفتح بابها الآن | موعد ONLINE + `CONFIRMED` + النافذة | → الباب |
| 🔴 استكمال الملفّ · 🔴 رفع إيصال قبل انتهاء المهلة | FEAT 09/10 | حين تُبنى |

تنتقل إلى **الرئيسية** (فوق الجلسة القادمة) وتعمل لكل أطفال الأسرة، ويبقى `/welcome` لاختيار الطفل فقط.

</details>

## Unified task table (2026-09-14)
The task screen now uses the shared table and pagination. Existing enrolment tasks remain scoped to ENROLMENT.MANAGE and parent requests to REQUEST.MANAGE, through their RLS-protected list endpoints. The new CHAT_READ source reads chat-contacts and includes one task per private peer with unread messages; it is personally assigned, opens communications?peer=<user_id>, and disappears after those messages are read. Read notification flags alone do not complete conversation tasks. Existing family history is not counted as a private incoming task. Shared-role tasks and personal tasks have separate filters. This adds no role conversation inbox or new assignment rule: messages sent to all staff arrive as private recipient copies, while enrolment and request work remains shared by the existing responsible permission.
