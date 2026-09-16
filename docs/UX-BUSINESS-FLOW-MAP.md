# UX-BUSINESS-FLOW-MAP — مراجعة الوضع الحالي

**2026-09-14 · تحليل فقط، لا تنفيذ معتمد.** القسم الأعلى هو المرجع الحالي. التحليل السابق محفوظ في آخر الملف للأرشفة ولا يمثل العمل المتبقي.

## الرحلة المصححة

**تحديث مراجعة الرحلة:** افصل الموجود أدناه عن المستهدف المعتمد سابقًا في OD-01: بعد التحقق من الجوال، مطابقة ثم إنشاء الناقص من ولي الأمر والمستفيد، دون منح حساب بوابة بمجرد التحقق. OD-39 يحدد التدرج والتوافق قبل تفعيل التحقق الإلزامي. لا نعتمد التحويل قبل الحجز كمسار مستهدف دائم. راجع [مراجعة رحلة الالتحاق](UX-ENROLMENT-JOURNEY-REVIEW.md) لترتيب الإصلاح ودليل R01؛ BL-34 الخاص بمن يحمل الطلب أولًا ما زال مفتوحًا في سجل القرارات.

الموقع → NEW → CONTACTED → تحويل مسموح من CONTACTED أو ASSESSMENT_BOOKED → طفل وولي أمر وربط وحساب في معاملة واحدة → إسناد/خطة/حجز/فوترة حسب العملية → حضور وجلسات → تقارير وأنشطة منزلية.

**ليست سلسلة إجبارية خطية.** لا يثبت ASSESSMENT_BOOKED وجود Appointment مربوط. 0110 تشترط تاريخًا لا يستقبله العقد الحالي. التقييم السريري DB بلا API، فلا يرسم كخطوة مكتملة. اسم /enrolments يخص EnrolmentApplication، ولا يثبت Course Enrollment مستقلًا. 0125 يسمح بتحويل CONTACTED مباشرة، فلا تفرض شرط تقييم جديدًا.

| Step | Current Status | Responsible Role | Actions | Next Status | Notifications | Required Data | Screen | API |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| تقديم | زائر | الأسرة | إرسال | NEW | لا إشعار موظف مثبت لمجرد وجود نوع | أسماء/جوال/صلة/طفل/شكوى | site → portal /apply | POST /enrolments |
| مراجعة | NEW | ENROLMENT.MANAGE | تواصل/رفض/تكرار | CONTACTED/REJECTED/DUPLICATE | لا إشعار مفترض | note_ar | /tasks → /enrolments/:id | PATCH /enrolments/{id} |
| تسجيل مقابلة محجوزة | CONTACTED | الاستقبال/المدير | اختيار الحالة | ASSESSMENT_BOOKED إن اكتملت قيود DB | 0110 ينتج SMS مشروطًا بالتاريخ | assessment_at غير متاح بالعقد الحالي | تفصيل الطلب | PATCH /enrolments/{id}؛ R01 |
| تحويل | CONTACTED أو ASSESSMENT_BOOKED | ENROLMENT.MANAGE + GUARDIAN.MANAGE لمنح الحساب | convert | ENROLLED | الحساب ينشأ ذريًا؛ لا رسالة تفعيل مفترضة | طلب صالح وجوال قابل للربط | تفصيل الطلب | POST /enrolments/{id}/convert |
| دخول الأسرة | حساب مرتبط | ولي الأمر | طلب/تحقق OTP واختيار طفل | مصادقة وChildContext | OTP مصادقة لا Task | جوال/رمز | /login → /login/otp → /welcome | Auth API; GET /children |
| إسناد | طفل موجود | STAFF.MANAGE | ربط طفل/خدمة/أخصائي | caseload row، لا status طلب جديد | STAFF_CHILD_ASSIGNED | child_id/service_id/therapist_id | ملف الطفل؛ therapists tab caseload | POST /caseload |
| خطة وقياس | DRAFT | PLAN.MANAGE/GOAL.MEASURE | CRUD وأهداف وقياسات | حسب آلة الخطة؛ لا اعتماد UI مفترض | لا plan approval delivery مفترض | طفل/خدمة/أخصائي/أهداف | /plans؛ ملف الطفل | CRUD /plans,/goals,/measurements,/child-activities |
| حجز | طفل موجود | APPOINTMENT.BOOK | slots ثم validate ثم book | BOOKED | APPOINTMENT_BOOKED بحسب المنتج/التسليم | طفل/أخصائي/خدمة/وقت UTC/نمط/غرفة عند اللزوم | /appointments؛ ملف الطفل | GET /appointments/slots; POST /appointments/validate; POST /appointments |
| تأكيد وحضور | BOOKED ثم CONFIRMED | الاستقبال | تغيير حالة | CONFIRMED ثم CHECKED_IN؛ إلغاء/غياب حسب الآلة | إلغاء/تذكير وفق المشغلات والصيانة | سبب عندما يلزم | المواعيد أو drawer | PATCH /appointments/{id}/status |
| بدء جلسة | CHECKED_IN بلا session | SESSION.START | بدء | IN_PROGRESS | لا نفترض إنتاج SESSION_STARTED لمجرد تعريفه | موعد/إسناد مسموح | /tasks;/appointments | POST /appointments/{id}/session |
| إغلاق وملاحظة | IN_PROGRESS | SESSION.COMPLETE منفصلة عن SESSION.NOTES.EDIT | إغلاق/إجهاض/ملاحظة | COMPLETED/ABORTED؛ note INTERNAL | NOTE_PUBLISHED عند النشر | body_ar/سبب حسب الفعل | /sessions؛ ملف الطفل | PATCH /sessions/{id}/close; PUT /note; POST /notes/{id}/publish |
| فاتورة | DRAFT | BILLING.MANAGE | سطور ثم إصدار | ISSUED | INVOICE_ISSUED | طفل/سطور/أسعار كما يقرر الخادم | /billing؛ drawer | POST /invoices; POST /invoices/{id}/lines; POST /issue |
| دفعة/باقة | ISSUED/PARTIALLY_PAID | BILLING.MANAGE | دفعة أو بيع باقة | PARTIALLY_PAID/PAID؛ باقة ACTIVE | لا إشعار دفع مفترض؛ أقساط DB جزئية | مبلغ/طريقة أو باقة | /billing | POST /invoices/{id}/payments; POST /children/{id}/packages |
| منزل | نشاط مسند | الأسرة | تسجيل الإنجاز | ActivityLog | لا إشعار مفترض | child/activity | portal /activities | POST /children/{id}/activities/{id}/log |
| تقرير | DRAFT | REPORT.WRITE/REPORT.PUBLISH | حفظ بنسخة متوقعة/نشر | PUBLISHED | REPORT_PUBLISHED | عنوان/فترة/ملخص/لقطة أهداف | محرر التقرير → بوابة | POST/PATCH /reports; POST /reports/{id}/publish |
| طلب أسرة | NEW | الأسرة ثم REQUEST.MANAGE | إرسال وقرار | ACCEPTED/REJECTED؛ لا تعديل موعد تلقائي | REQUEST_DECIDED | kind/body والحقول المقبولة | portal /requests → ops /requests | POST /children/{id}/requests; PATCH /requests/{id} |
| بث/استشارة | جلسة/موعد مؤهل | الأسرة أو موظف وفق الصف | دخول | رمز مؤقت؛ لا تسجيل | لا إشعار مفترض | موافقة ونافذة دخول | /live;/consultation/:appointmentId | Stream/Meeting API |
| رسائل | FamilyMessage | الأسرة/REQUEST.MANAGE | إرسال/قراءة | read/unread | عداد رسائل لا task | body/request_id لمنع التكرار | /communications | GET /family-contacts; GET/POST /family-messages/{id}; POST /read |
| رضا | NpsSurvey | الأسرة تجيب/المدير يقرأ | إجابة/إدارة/نتائج | NpsResponse | حسب منتج الاستبيان، لا وعد تسليم | أسئلة/إجابات | NPS dialog;/satisfaction | NPS API; CRUD /nps-surveys |
| موقع وفريق | DRAFT | SITE.EDIT/PUBLISH؛ الأخصائي لموافقته | محتوى/ملف/موافقة/نشر | PUBLISHED أو WITHDRAWN حسب الكيان | لا إشعار مفترض | حقول المورد والموافقة | /site; therapist profile | CRUD site-*; therapist profile/consent/publish |
| إدارة | User/Role/Param | USER.MANAGE/SETTINGS.MANAGE/OPS.VIEW | حساب/صلاحية/مستند/إعداد/رقابة | حالات الحساب وحقوقه | رمز إعداد وفق الخادم | حقول الإدارة | /users;/settings;/ops-log | Identity/Settings/OpsLog API |

## قدرات جزئية ومخططة

assessments وجداول أدواته وبنوده/درجاته موجودة في DB ودوال نشره، دون route في server.go. payment_plans وinvoice_installments في 0142 دون رحلة UI/API مكتملة. consultation_requests/payment_receipts وطوابير انتظار الإسناد في وثائق التخطيط لا تضاف للجرد الحالي. لا Task table مستخدم؛ follow-up/renewal ليس workflow آليًا مثبتًا. وجود permission أو migration لا يكفي لإعلان feature.

مصادر المنطق: 0018 legal_enrolment_transition؛ 0110 assessment_at؛ 0125 convert_enrolment؛ 0099 decide_request؛ 0142 payment_plans؛ server.go؛ day-spec.ts؛ http-portal-api.ts. حالات الطلبات بالبوابة تُحوّل NEW→SUBMITTED وREJECTED→DECLINED؛ UNDER_REVIEW غير منتجة من الخادم، لا تضفها لآلة الحالة.


<details>
<summary>أرشيف التحليل السابق — غير معتمد كوصف للحالة الحالية أو تكليف تنفيذ</summary>

# UX Business Flow Map — Hand By Hand (new)

**المرحلة ٣.** التدفّقات كما هي **مبنيّة فعلًا** — من آلات الحالة في `db/migrations` (المشغّلات `legal_*_transition`)، والموجّه `server.go`، والشاشات في `web/ops` و`web/portal`. ما هو مخطَّط (FEAT 09/10/11) يُذكر في مكانه بعلامة 🔴 حتى يعرف مصمّم الواجهة أين ستلتحم الشاشات القادمة، **ولا يُبنى له شيء الآن**.

**الرموز:** 🟢 مبنيّ كاملًا (قاعدة + API + شاشة) · 🟡 نصف مبنيّ (قاعدة بلا API أو بلا شاشة) · 🔴 مخطَّط · ⛔ قرار مالك مفتوح.

---

## ١ · رحلة الأسرة والمستفيد — من أوّل دخول حتى بدء الخدمة

### ١.١ · التدفّق كما هو اليوم (الالتحاق الرسمي)

```
الموقع التعريفي  ──►  البوّابة /apply (بلا حساب)
       │
       ▼
[1] enrolment_applications = NEW                     ◄── الكتابة المجهولة الوحيدة
       │  الاستقبال: PATCH status
       ├──► CONTACTED  (تمّ التواصل)
       │       │  الاستقبال: حجز موعد التقييم (شاشة أخرى!) ثم PATCH status
       │       ├──► ASSESSMENT_BOOKED
       │       │       │  الحضور ← appointments: BOOKED → CONFIRMED → CHECKED_IN → COMPLETED
       │       │       │  التقييم نفسه: 🔴 لا مسار ولا شاشة (assessments مبنيّة في القاعدة فقط)
       │       │       ▼
       │       └──► ENROLLED  ◄── convert_enrolment: يُنشئ وليّ الأمر + الطفل + حساب البوّابة (0125)
       │
       ├──► REJECTED · DUPLICATE (نهائي)
       ▼
[2] الطفل في الملفّ  ──►  إسناد أخصائي (caseload)  🟡 CRUD عامّ بلا مهمّة
       │
       ▼
[3] الخطّة العلاجية DRAFT → ACTIVE  🟡 الاعتماد بلا زرّ (approved_by بلا مُنفِّذ)
       │
       ▼
[4] الجدول: book_appointment (validate → book) 🟢
       │
       ▼
[5] الفوترة: create_invoice → add_invoice_line → issue → payments 🟢
    أو بيع باقة sell_package 🟢 (الرصيد لا يُستهلك — C-01 🟡)
       │
       ▼
[6] الجلسات: CHECKED_IN → start_session → IN_PROGRESS → close (COMPLETED/ABORTED) 🟢
       │    ملاحظة الجلسة INTERNAL → نشر للأسرة 🟢
       │    البثّ المباشر بموافقة LIVE_VIEW 🟢
       ▼
[7] التقدّم: القياسات 🟢 · البرنامج المنزلي (الأسرة تسجّل) 🟢 · التقارير DRAFT → PUBLISHED 🟢
       │
       ▼
[8] المتابعة/إعادة التقييم/التجديد  🔴 لا وجود له إطلاقًا (BL-38 · BL-39)
```

### ١.٢ · جدول الخطوات

| # | الخطوة | الحالة الحالية (الكيان) | المسؤول | الأفعال المتاحة | الحالة التالية الممكنة | الإشعارات | البيانات المطلوبة | الشاشة المستعمَلة | الـAPI | البناء |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | الأسرة تملأ طلب الالتحاق | `enrolment_applications = NEW` | زائر (مجهول) | إرسال · «طلب لطفل آخر» | `NEW` | **لا شيء للموظّفين** (`STAFF_ENROLMENT_NEW` معلَن بلا مُنتِج) · لا شيء للأسرة | اسم وليّ الأمر · جوال · صلة · اسم الطفل · ميلاده · نوعه · الشكوى · علاج سابق · `center_code` | البوّابة `/apply` | `POST /api/v1/enrolments` | 🟢 · خطوة الرمز `OD-01` 🔴 (`HBH-070`) |
| 2 | الاستقبال يراجع ويتواصل | `NEW` | استقبال / مدير (`ENROLMENT.MANAGE`) | تغيير الحالة + ملاحظة · أرشفة | `CONTACTED` · `REJECTED` · `DUPLICATE` | لا شيء (لا `REQUEST_DECIDED` للالتحاق) | ملاحظة اختيارية | الكونسول `/enrolments` (جدول أو لوحة مراحل) | `PATCH /enrolments/{id}` | 🟢 |
| 2b | إسناد الطلب لموظّف | `assigned_to` عمود بلا حالة | مدير | — لا فعل | — | — | — | — | — | ⛔ `BL-34` (قبل التواصل أم بعده) |
| 3 | حجز موعد التقييم | `CONTACTED` → `ASSESSMENT_BOOKED` · `appointments = BOOKED` | استقبال (`APPOINTMENT.BOOK`) | (أ) حجز من شاشة المواعيد: تحقّق ثم حجز · (ب) **يدويًّا** تغيير حالة الطلب إلى `ASSESSMENT_BOOKED` — **بلا رابط بين الفعلين** | `ASSESSMENT_BOOKED` | `APPOINTMENT_BOOKED` للأسرة (إن كان لها حساب — وليس لها بعد) · `STAFF_APPOINTMENT_BOOKED` للأخصائي | الطفل (**غير موجود بعد!**) · الخدمة · الأخصائي · الفتحة | `/appointments` ثم `/enrolments` | `POST /appointments/validate` · `POST /appointments` · `PATCH /enrolments/{id}` | 🟢 لكن **الطفل لا يوجد قبل التحويل**: التقييم يُحجز لطفل لم يُنشأ — ثغرة تدفّق حقيقية (تُحلّ بـ`OD-01`: الكيانات تُنشأ عند الإرسال الموثَّق — `HBH-058`/`0144` 🔴) |
| 4 | التحويل إلى ملفّ | `ASSESSMENT_BOOKED`/`CONTACTED` → `ENROLLED` | استقبال (`ENROLMENT.MANAGE` + `GUARDIAN.MANAGE`) | «تحويل» + ملاحظة | `ENROLLED` (نهائي) | لا شيء (الحساب يُمنح صامتًا) | — | `/enrolments` (حوار) | `POST /enrolments/{id}/convert` → `{guardian_id, child_id, child_no}` | 🟢 (0125: الحساب مع التحويل) |
| 5 | حضور موعد التقييم | `appointments`: `BOOKED → CONFIRMED → CHECKED_IN → COMPLETED` | استقبال | تغيير الحالة (كل قفزة صفّ في `appointment_status_history`) · الإلغاء يشترط سببًا | حسب الآلة · `CANCELLED` · `NO_SHOW` | `APPOINTMENT_CANCELLED` · `APPOINTMENT_RESCHEDULED` (صفّان مربوطان) · `APPOINTMENT_REMINDER` (بارامتر الساعات **غير مبذور** — لا تذكير يُرسل) | سبب عند الإلغاء/الغياب | `/appointments` (لوحة «بانتظار التأكيد» + «تداخلات») | `PATCH /appointments/{id}/status` | 🟢 «أقوى خطوة في الدورة» |
| 6 | التقييم | `assessments: DRAFT → COMPLETED → PUBLISHED` | أخصائي (`ASSESSMENT.RECORD`/`.PUBLISH`) | — | — | `ASSESSMENT_PUBLISHED` (الدالّة جاهزة) | أداة · بنود · درجات · توصية نصّية | **لا شاشة** | **لا مسار** (4 جداول · 6 دوالّ · 0 مسار) | 🔴 `HBH-041` — أسوأ فجوة في الرحلة |
| 6b | التوصية | `recommendation_ar` نصّ حرّ | أخصائي | — | — | — | خدمات مقترحة · عدد جلسات | — | — | ⛔ `BL-35` |
| 7 | إسناد الأخصائي | `caseload` صفّ | مدير (`STAFF.MANAGE`) | إضافة صفّ (أخصائي، طفل، خدمة) من CRUD | — | `STAFF_CHILD_ASSIGNED` للأخصائي (مشغّل) | الثلاثة | `/therapists` › تبويب «إسناد الحالات» | `POST /caseload` (CRUD عامّ) | 🟡 يعمل، لكنه **مهمّة تُدار من جدول خطأ** — بلا «هذا الطفل بلا أخصائي» في أيّ مكان |
| 8 | الخطّة العلاجية | `treatment_plans: DRAFT → ACTIVE` | أخصائي يكتب · مدير يعتمد (`PLAN.MANAGE`) | CRUD الخطّة/الأهداف/القياسات — **الحالة لا تُغيَّر من الشاشة** | `ACTIVE` · `COMPLETED` · `CANCELLED` | `STAFF_PLAN_APPROVED` معلَن بلا مُنتِج | عنوان · طفل · خدمة · أخصائي · فترة · أهداف بخطّ أساس وهدف | `/plans` (4 تبويبات، 4 منتقيات رقمية) | CRUD `/plans` `/goals` `/measurements` | 🟡 `LC-09`: لا زرّ اعتماد، ولا قاعدة تفرض المُعتمِد (أُسقطت في 0090) |
| 9 | الجدول (الجلسات المنتظمة) | `appointments = BOOKED` | استقبال | حجز (تحقّق ← حجز) · **الحجز المتكرّر** `book_recurring` | `BOOKED` | `APPOINTMENT_BOOKED` · `STAFF_APPOINTMENT_BOOKED` | طفل · خدمة+أخصائي · نمط التقديم · فتحة · غرفة | `/appointments` (تقويم أسبوعي بساعة) | `GET /appointments/slots` · `POST /appointments` | 🟢 · المتكرّر 🟡 (بلا مسار، M-03) · قائمة الانتظار 🟡 (بلا مسار، M-02) |
| 10 | نموذج الفوترة: باقة أو بالجلسة | `child_packages = ACTIVE` · `invoices: DRAFT → ISSUED` | مدير (`BILLING.MANAGE` — **الاستقبال لا يقبض**) | بيع باقة · فاتورة جديدة ← سطر ← إصدار | `ISSUED` | `INVOICE_ISSUED` للأسرة | طفل · باقة / سطور بسعر | `/billing` (حوارات) | `POST /children/{id}/packages` · `POST /invoices` · `/lines` · `/issue` | 🟢 · الأسعار من الكتالوج 🟢 (0135/0136) · النُّسخ والتجميد والتعويض 🔴 (`11`) |
| 11 | الدفع | `ISSUED → PARTIALLY_PAID → PAID` | مدير | إضافة دفعة (نقد/بطاقة/تحويل/محفظة) | حسب `recalc_invoice` | `INSTALLMENT_DUE`/`OVERDUE` (0142) · لا إشعار «دُفع» | مبلغ · طريقة | `/billing` › دفعة | `POST /invoices/{id}/payments` | 🟢 · خطط الدفع `0142` مبنيّة بلا مسار API 🟡 · الإيصالات (InstaPay) 🔴 |
| 12 | الجلسة | `CHECKED_IN` → `therapy_sessions = IN_PROGRESS` → `COMPLETED`/`ABORTED` | أخصائي (`SESSION.START`/`COMPLETE`) — المدير يغلق أيضًا | بدء (من «يومي») · إغلاق (من «الجلسات») · ملاحظة داخلية | `COMPLETED` | `SESSION_STARTED` معلَن بلا مُنتِج · إغلاق الجلسة يستهلك الباقة نظريًّا (**لا نداء** — C-01) · NPS يستحقّ | — / سبب عند الإجهاض | `/my-day` → `/sessions` | `POST /appointments/{id}/session` · `PATCH /sessions/{id}/close` · `PUT …/note` | 🟢 (شاشتان لعمل واحد) |
| 13 | البثّ المباشر | جلسة `IN_PROGRESS` + موافقة `LIVE_VIEW` | الأسرة / الأخصائي / المدير | فتح البثّ · لحظة مهمّة (الكونسول: ملاحظة موقوتة ✅ · البوّابة: **يفشل دائمًا**) | — | — | موافقة مسجَّلة | `/live` (البوّابة) · `/sessions/{id}/live` (الكونسول) | `POST /sessions/{id}/stream` | 🟢 |
| 14 | نشر الملاحظة للأسرة | `session_notes.visibility INTERNAL → PARENT` | أخصائي (`NOTE.PUBLISH`) | نشر | — | `NOTE_PUBLISHED` | — | ملفّ الطفل › تبويب الملاحظات | `POST /notes/{id}/publish` | 🟢 (الكتابة في «الجلسات» والنشر في «الطفل») |
| 15 | البرنامج المنزلي | `child_activities` · `activity_log` | أخصائي يسند · **الأسرة تسجّل** | تعليم منجَز | — | — | — | `/plans` › البرنامج المنزلي · البوّابة `/activities` | `POST /children/{id}/activities/{a}/log` | 🟢 |
| 16 | تقرير التقدّم | `progress_reports: DRAFT → PUBLISHED` | أخصائي / مدير (`REPORT.WRITE`/`PUBLISH`) | كتابة (حفظ آلي) · نشر (يشترط لقطة الأهداف) | `PUBLISHED` (وإلغاء نشر → `DRAFT`) | `REPORT_PUBLISHED` | عنوان · فترة · ملخّص | ملفّ الطفل → المحرّر · `/reports` للنشر · البوّابة `/reports/{id}` | `POST/PATCH /reports` · `POST /reports/{id}/publish` | 🟢 |
| 17 | طلبات الأسرة | `parent_requests: NEW → ACCEPTED/REJECTED` | الأسرة تُرسل · استقبال يقرّر (`REQUEST.MANAGE`) | تغيير موعد / إلغاء / مكالمة (نصّ) · قرار + ملاحظة | حسب القرار | `REQUEST_DECIDED` للأسرة · `STAFF_REQUEST_NEW` **بلا مُنتِج** | نصّ ≤500 | البوّابة `/requests` · الكونسول `/requests` | `POST /children/{id}/requests` · `PATCH /requests/{id}` | 🟢 · **قبول «تغيير موعد» لا يغيّر شيئًا** — الحجز الجديد يدويّ على شاشة أخرى (`HBH-043`) |
| 18 | المتابعة / إعادة التقييم / التجديد | — | — | — | — | — | — | — | — | 🔴 لا عدّاد جلسات، لا «مراجعة مطلوبة»، لا حالة تجديد (`BL-38`, `BL-39`, `LC-14`) |

### ١.٣ · الفرع المخطَّط — الاستشارة الأونلاين (FEAT 09/10) 🔴

يُذكر هنا كي تُترك له أماكنه في الهيكل (لا يُبنى الآن):

```
الموقع: نموذج استشارة قصير ──► رمز تحقّق جوال (mobile_verifications ✅ 0131)
   ──► مطابقة وليّ الأمر/المستفيد (find_* ✅ 0132) ──► إنشاء الناقص بمصدره ✅ 0129
   ──► consultation_requests: NEW → WAITING_FOR_ASSIGNMENT → ASSIGNED → SLOT_CHOSEN → CLOSED  (🔴 HBH-059)
   ──► book_consultation: موعد BOOKED + فاتورة ISSUED + مهلة سداد (🔴 HBH-061)
   ──► payment_receipts: REVIEW_PENDING → APPROVED | REJECTED  (🔴 HBH-060 · مراجعة بـ BILLING.RECEIPT_REVIEW · SLA ساعتان)
   ──► PAID ⇒ مشغّل: الموعد CONFIRMED + الغرفة READY (🔴)
   ──► الباب: /consultation/:id ✅ مبنيّ (P7) ──► CHECKED_IN → COMPLETED + ملخّص مكتوب
```

**ما يعنيه للواجهة:** تظهر لاحقًا (أ) طابور «طلبات الاستشارة» + تعيين أخصائي، (ب) طابور «مراجعة الإيصالات» مرتَّبًا بالمتأخّر أوّلًا، (ج) شارات المصدر واكتمال الملفّ — كلّها **مهامّ** تنزل في صندوق المهامّ لا شاشات مستقلّة (انظر `UX-TASK-INBOX.md`).

---

## ٢ · التدفّقات الجانبية المبنيّة (FL) — مختصرة

| التدفّق | الحالات | المسؤول | الشاشة | الملاحظة |
|---|---|---|---|---|
| **دخول الأسرة** | `request_otp` → `SENT` / `NOT_REGISTERED` / `ENROLMENT_PENDING` → `verify_otp` → جلسة | الأسرة | `/login` → `/login/otp` → `/welcome` | `ENROLMENT_PENDING` يُكشف لصاحب الرقم بقصد (`OD-24`) |
| **دخول الموظّف** | كلمة مرور · رمز إعداد أوّل | موظّف | `/login` | إصدار الرمز من `/access` |
| **منح حساب البوّابة لأسرة قائمة** | `grant_portal_access` | استقبال | **لا شاشة ولا زرّ** (`HBH-011`/`012`) | 11 وليّ أمر قدامى بلا حساب (`BL-55` → قرار: واحد بعد تأكيد المركز) |
| **الموافقات** | `LIVE_VIEW` · `PHOTO_USE` · `SMS_NOTIFY` · `WHATSAPP_NOTIFY` | استقبال (`GUARDIAN.MANAGE`) | ملفّ الطفل › تبويب أولياء الأمور (`LIVE_VIEW` فقط) | صورة الطفل تُرفض بلا `PHOTO_USE` ولا مكان لتسجيلها من الشاشة |
| **الرسائل** | `family_messages` | استقبال ↔ الأسرة | `/communications` (كلاهما) | مكوّن واحد للطرفين — خطأ في جهة الأسرة |
| **الإشعارات** | `notifications` (18 نوعًا؛ 5 بلا مُنتِج) | النظام | `/inbox` · `/notifications` | لا مسار يُنشئ إشعارًا — كلّها مشغّلات وصيانة |
| **رضا الأسر** | `nps_surveys` → `nps_responses` | الأسرة تجيب · المدير يقرأ | حوار NPS · `/satisfaction` · إعداد في `/catalog` | كيان على شاشتين |
| **الموقع التعريفي** | `site_*: DRAFT → PUBLISHED` | مدير (`SITE.EDIT`/`PUBLISH`) | `/site` · `/site/team` | إعداد |
| **الفريق** | `therapists` · `profile_status` · خدمات · ساعات · لغات · شهادات | مدير / الأخصائي لملفّه | `/therapists` · `/therapist-services` · `/therapists/{id}/profile` | ثلاثة مسارات لكيان واحد |
| **المستخدمون** | `users: ACTIVE/SUSPENDED/LOCKED` · أدوار · صلاحيات · مستندات | مدير (`USER.MANAGE`, `STAFF.PII`) | `/access` | اسم الشاشة لا يقول ذلك |
| **الصيانة** | انتهاء الباقات · تذكيرات · أقساط · عروض الانتظار · SMS | الساعة | **لا شاشة** (صحّة النسخ/الصيانة بلا قارئ) | `OPS.VIEW` |

---

## ٣ · مَن ينتظر ماذا — الخريطة الزمنية للمسؤوليات

هذه هي الإجابة على «المستخدم لا يعرف: أين يذهب؟ ماذا ينتظر؟ ما المطلوب منه؟» — مستخرجة من الحالات أعلاه. كل صفّ هنا هو **مهمّة** مرشَّحة لصندوق المهامّ:

| حين يكون… | المنتظِر | المطلوب منه | أين اليوم | أين ينبغي |
|---|---|---|---|---|
| طلب التحاق `NEW` | الاستقبال | مراجعة + تواصل | بطاقة عدّ في الداشبورد → `/enrolments?status=NEW` | صندوق المهامّ ← تفصيل الطلب |
| طلب `CONTACTED` بلا موعد تقييم | الاستقبال | حجز التقييم | **لا إشارة** (فلتر يدوي) | مهمّة «احجز تقييمًا» بزرّ يفتح الحجز مسبوق التعبئة |
| طلب `ASSESSMENT_BOOKED` وموعده `COMPLETED` | الاستقبال | التحويل إلى ملفّ | **لا إشارة** | مهمّة «حوّل إلى ملفّ» |
| طلب أسرة `NEW` | الاستقبال | قرار | بطاقة عدّ → `/requests?status=NEW` | صندوق المهامّ ← قرار + (إن قُبل تغيير الموعد) حجز مربوط |
| موعد اليوم `BOOKED` | الاستقبال | تأكيد | لوحة «بانتظار التأكيد» داخل `/appointments` | صندوق المهامّ («مواعيد اليوم بانتظار التأكيد») |
| موعد `CONFIRMED` حان وقته | الاستقبال | تسجيل حضور | فلتر يدوي | مهمّة «سجّل الحضور» |
| موعد `CHECKED_IN` بلا جلسة | الأخصائي | بدء الجلسة | لوحة «يومك» في الداشبورد + `/my-day` | مهمّة «ابدأ الجلسة» (موجودة جزئيًّا) |
| جلسة `IN_PROGRESS` | الأخصائي | إغلاق + ملاحظة | `/sessions` بفلتر | مهمّة «أغلق الجلسة» |
| جلسة `COMPLETED` بلا ملاحظة | الأخصائي | كتابة الملاحظة | **لا إشارة** | مهمّة «اكتب ملاحظة الجلسة» |
| ملاحظة `INTERNAL` | الأخصائي | نشر أو إبقاء | تبويب في ملفّ الطفل | مهمّة اختيارية «انشر للأسرة» |
| تقرير `DRAFT` | الأخصائي / المدير | إكمال ونشر | بطاقة عدّ → `/reports?status=DRAFT` | صندوق المهامّ |
| فاتورة `DRAFT` | المدير | إصدار | فلتر | مهمّة «أصدر الفاتورة» |
| فاتورة `ISSUED`/`PARTIALLY_PAID` (تجاوزت `due_date`) | المدير | تحصيل | بطاقة عدّ + عدّاد حالة | مهمّة «متأخّرة عن السداد» (المتأخّر أوّلًا) |
| قسط `DUE`/`OVERDUE` (0142) | المدير | تحصيل | **لا شاشة** | مهمّة |
| باقة `ACTIVE` توشك على النفاد/الانتهاء | المدير / الاستقبال | تجديد | **لا شاشة** | مهمّة «تجديد مطلوب» |
| خطّة `DRAFT` | المدير | اعتماد | **لا زرّ** (`LC-09`) | مهمّة «اعتمد الخطّة» — تحتاج مسار اعتماد (توصية backend) |
| طفل `ENROLLED` بلا `caseload` | المدير | إسناد أخصائي | CRUD في `/therapists` | مهمّة «عيّن أخصائيًا» تُفتح من ملفّ الطفل |
| وليّ أمر بلا حساب بوّابة | الاستقبال | منح الحساب | **لا شاشة** (`HBH-011`) | مهمّة (بعد بناء المسار/الزرّ) |
| ملفّ الأخصائي `DRAFT` بلا موافقة | الأخصائي | موافقة النشر | `/therapists/{id}/profile` بالرابط فقط | مهمّة للأخصائي «وافق على نشر ملفّك» |
| تداخل أخصائي/غرفة في اليوم | الاستقبال | فضّ التعارض | لوحة «تداخلات» داخل `/appointments` | مهمّة |
| إشعار غير مقروء | الشخص | قراءة | `/inbox` | **يبقى إشعارًا** — ليس مهمّة |

**قاعدة الفصل التي ستحكم `UX-TASK-INBOX.md`:** المهمّة **تنكمش حين يُنجَز العمل** (تشتقّ من حالة في القاعدة)، والإشعار **يكبر ولا ينكمش** (سجلّ). المصدر واحد لكل مهمّة: حالة + شرط، لا صفّ يُكتب.

</details>
