# UX-REDESIGN-IMPLEMENTATION-PROMPT — مراجعة الوضع الحالي

**2026-09-14 · تحليل فقط، لا تنفيذ معتمد.** القسم الأعلى هو المرجع الحالي. التحليل السابق محفوظ في آخر الملف للأرشفة ولا يمثل العمل المتبقي.

## Prompt جاهز بعد اعتماد المالك

أنت Frontend Developer AI Agent على Hand By Hand: Angular ops/portal وGo وPostgreSQL. هذا تكليف لاحق فقط بعد اعتماد المالك. اقرأ الأقسام الحالية أعلى وثائق UX المؤرخة 2026-09-14. لا تنفذ الأرشيف كتذاكر جديدة.

## النطاق والممنوع

49 route شاشة → 47 عبر دمجين بالبوابة؛ تبقى شاشات المركز 31. لا تعديل api/ أو db/ أو Schema أو PL/pgSQL أو عقود HTTP أو صلاحيات أو قواعد عمل. لا حذف feature ولا React. النصوص العربية عبر i18n والتعليقات بالإنجليزية. لا تنشر ولا تبدأ تنفيذًا قبل اعتماد التحليل.

## المنفذ الذي يجب الحفاظ عليه

/tasks و/notifications منفصلتان، Sidebar مجمعة، تفاصيل الطلب/الأسرة والطفل وActionDialogService وRecordDrawer موجودة. حافظ على /my-day→/appointments?view=mine، /therapist-services→/therapists?tab=services، /site/team→/site?tab=team، /inbox→/notifications، /access→/users. لا تنشئها ثانية.

## الدمج والNavigation

1. اجعل /progress متابعة طفلي بتبويبات progress/reports/notes باستعمال المكونات وPortalApi القائمة. /reports redirect إلى /progress?tab=reports؛ احفظ طلب notes إن وجد. /reports/:reportId باق مع back link مناسب.
2. ادمج /communications تحت /requests?tab=messages. حافظ على can_manage/can_send وrequest_id ومنع تكرار الإرسال. الرسائل عائلية بلا ChildContext؛ طبّق اختيار الطفل على تبويب الطلبات وإجراء إرسالها بدل منع الصفحة كلها.
3. شريط الهاتف خمسة عناصر كما في IA، مع قائمة المزيد للفواتير والطلبات والإشعارات وتغيير الطفل دون route جديد. Sidebar حسب UX-TARGET-INFORMATION-ARCHITECTURE؛ لا menu باسم STATUS ولا شاشة تقييم بلا API.
4. احذف مداخل الشاشات المدمجة من التنقل فقط بعد توفير البديل؛ لا تحذف الأكواد التي تستعملها التبويبات أو الروابط القديمة. كل route غير المذكور KEEP وفق UX-CURRENT-TO-TARGET.

## Deep links

حافظ على status/focus/tab/view/open، وreturnUrl داخلي متحقق. action allowlist يفتح dialog ولا ينفذ mutation. لا تضع الجوال/الاسم في query. R06: احتفظ بتاريخ وسياق آمن لdrawer الموعد وpagination في النطاق؛ لا تدّع not-found من أول 100 موعد اليوم، ولا تستدع GET /appointments/{id} غير الموجود. الروابط القديمة ونسخ URL وReload وBack حالات قبول إلزامية.

## Task Inbox

حسّن core/tasks الحالي؛ كتالوج الأنواع الأربعة عشر في UX-TASK-INBOX هو baseline. المهمة تحمل النوع والسجل والمعرف وParent/Child إن توفر والحالة والإجراء والأولوية والدور المؤهل والمسند الحقيقي إن وجد وdueDate الحقيقي أو غير محدد وCTA ورابط أصل السجل. permission ليس تكليفًا بمستخدم. إشعار غير مقروء ليس مهمة.

عالج R02: DayApi يدعم page/limit، وOpsApi حسب عقده؛ استخدم total واقرأ الصفحات أو أظهر incomplete وعددًا جزئيًا. لا تستنتج الطفل بلا أخصائي من عينة caseload. failed/incomplete/empty ثلاث حالات مستقلة. لا تفرض SLA جديدًا. اجعل الخدمة واحدة للشارة والداشبورد والشاشة وتجنب اشتراك load المكرر. R04: غط جلسات مفتوحة أقدم ضمن نطاق معلن؛ لا ادعاء all-time بلا دليل.

CTA الإسناد يفتح ملف الطفل ثم ActionDialogService الحالي مسبوقًا بمعرف الطفل. BILLING.VIEW فقط يتيح المتابعة بالماليات؛ لا مهمة تحصيل بلا إجراء ولا منح حق دفع. اقرأ السجل قبل عرض الفعل ولا تفترض أن حالة البطاقة ما زالت حديثة. لا زر إغلاق مهمة منفصل؛ تختفي بعد تغير السجل.

## التفاصيل والنماذج

Application موجودة بoverview/beneficiary/family/appointments/assessment/recommendations/notes/activity. حافظ على الرأس وCTA وبيانات الطلب الأصلية. قبل converted_child_id لا appointment وهمي. تبويب assessment يبين عدم إتاحة API. CONTACTED يعرض التحويل المتاح ويوضح R01؛ لا تفرض Assessment شرطًا جديدًا. activity ملخص طوابع لا سجل تدقيق شامل.

Guardian بتبويباته السبعة يبقى؛ عالج أول 100 طلب قبل قول «كل طلبات الأسرة». Child مركز العمل؛ اجعل plan→goal→measurement ضمن السياق، واستبدل إدخال IDs بمنتقيات أسماء تبعث نفس IDs والعقد. أبق /plans عبر الأطفال. الفاتورة والموعد drawers لا routes جديدة. لا Course Enrollment entity مخترع؛ /enrolments هو EnrolmentApplication وChildPackage تحت الطفل/الماليات.

## الأدوار

استعمل /me والحق الخاص بالفعل لا if(role===...). المدير إدارة وإسناد وفوترة ونشر حسب حقوقه دون كتابة ملاحظة نيابة عن الأخصائي. الاستقبال تواصل وتحويل وحجز وحضور وقرار وقراءة ماليات دون قبض بلا BILLING.MANAGE. الأخصائي مواعيده وجلساته وخططه وتقاريره وملفه، مع إبقاء حقوق دوره الآخر إن وجدت. الأسرة ترى السجلات الخاصة بها والرسائل/الماليات العابرة للأطفال حسب العقد. RLS لا يتغير.

## العقود التي لا تمس

POST /enrolments/{id}/convert معاملة ذرية؛ PATCH /enrolments/{id} بنفس الحقول؛ validate ثم POST /appointments؛ POST /appointments/{id}/session؛ PATCH /sessions/{id}/close؛ PUT /sessions/{id}/note؛ POST /notes/{id}/publish و/reports/{id}/publish؛ POST /invoices/{id}/payments. حافظ على expected version للتقرير وrequest_id للرسائل وtimezone المركز وUTC والموافقات وعدم التسجيل والأرشفة الناعمة وأخطاء 403/404/409 وvalidation ok:false.

قبول ParentRequest لا يعدل Appointment تلقائيًا. اشرح القرار وأضف رابط حجز سياقيًا بقصد منفصل؛ لا سلسلة كتابة خفية ولا status جديدة. نفس حوار وأفعال DaySpec/ResourceSpec من كل السياقات، دون إعادة منطق العمل في الواجهة.

## توصيات Backend فقط

قبل أي عمل على رحلة الالتحاق، اقرأ [UX-ENROLMENT-JOURNEY-REVIEW.md](UX-ENROLMENT-JOURNEY-REVIEW.md). OD-01 قرار سابق بإنشاء الناقص بعد تحقق الجوال والمطابقة؛ لا تحوّل وصف الكود الحالي إلى سياسة نهائية تخالفه. OD-39 يبقي تفعيل التحقق متدرجًا ومتوافقًا مع الاستمارة الحالية. لا تبدل submit/convert من Frontend؛ نفذ عقد الخلفية المعتمد حين يصبح متاحًا. اكتمال paging وسياق مهمة الإسناد مستقلان عن هذه التغييرات.

R01: 0110 تشترط assessment_at وEnrolmentUpdate لا يقبله. أبلغ فريق الخلفية بعقد مستقل؛ لا ترسل حقلًا غير مدعوم ولا تزل القيد ولا تدّع حجزًا ناجحًا. Assessment وInstallment/PaymentPlan وconsultation assignment وreceipt review ليست رحلات واجهة جاهزة بالعقود الحالية. مصدر Tasks جامع وGET موعد منفرد توصيات خارج النطاق.

## القبول

تحقق من >100 سجل و>200 caseload، مصدر فاشل ومصدر جزئي، جلسة أمس المفتوحة، رابط موعد خارج اليوم وصفحة أولى، تبويب رسائل دون طفل، تقرير وملاحظة بعد الدمج، صلاحية عرض بلا كتابة، load دون تكرار HTTP، إلغاء dialog دون mutation، Back/Reload، RTL والهاتف ولوحة المفاتيح واستعادة التركيز. اختبارات Angular الحالية المناسبة وbuild، ومراجعة diff تثبت عدم تغيير api/db. لا حجز أو دفع أو رسائل على بيانات حقيقية. سلم التغييرات وأدلة الاختبارات والفجوات؛ لا تزعم إصلاح عقد يحتاج backend من الواجهة وحدها.

<details>
<summary>أرشيف التحليل السابق — غير معتمد كوصف للحالة الحالية أو تكليف تنفيذ</summary>

# UX Redesign — Implementation Prompt for the Frontend Developer Agent

> **حالة هذا الملفّ:** مسودّة بانتظار موافقة المالك على التحليل (`UX-*.md`). **لا يُنفَّذ شيء منه قبل الموافقة.** حين يُوافَق، يُعطى هذا الملفّ كاملًا لوكيل تطوير الواجهة.

---

## Prompt

أنت **Frontend Developer** على مشروع **Hand By Hand (new)** — Angular 20 (standalone, signals, OnPush, RTL عربي) في `web/ops` (كونسول المركز) و`web/portal` (بوّابة وليّ الأمر)، خلف Go API في `api/` وPostgreSQL هو مصدر الحقيقة. مهمّتك **إعادة تنظيم الشاشات والتنقّل وتجربة المستخدم** وفق التحليل المعتمَد في:

- `docs/UX-SCREEN-INVENTORY.md` — ما هو موجود
- `docs/UX-BUSINESS-FLOW-MAP.md` — التدفّق الحقيقي ومن ينتظر ماذا
- `docs/UX-PROBLEMS.md` — المشاكل بالدليل + التوصيات التي **ليست لك** (`R-xx`)
- `docs/UX-TASK-INBOX.md` — صندوق المهامّ: الشكل والكتالوج والفصل عن الإشعارات
- `docs/UX-TARGET-INFORMATION-ARCHITECTURE.md` — القائمة والمسارات المستهدفة
- `docs/UX-DETAIL-PAGES.md` — شاشات التفصيل
- `docs/UX-ROLE-BASED-VIEWS.md` — ما يراه كل دور
- `docs/UX-SCREEN-CLASSIFICATION.md` · `docs/UX-CURRENT-TO-TARGET.md` — التصنيف والخريطة

اقرأ أوّلًا `CLAUDE.md` (القواعد الخمس ودروس الواجهة) و`docs/04-frontend-guide.md` و`docs/02-api-contract.md`. **الوثائق تحكم عند أيّ خلاف مع هذا الـPrompt.**

### ٠ · ما يُمنع منعًا باتًّا

1. **لا تغيير في `api/` ولا في `db/`** ولا في أيّ عقد API. كل ما تحتاجه موجود؛ ما ليس موجودًا (`R-01`…`R-12` في `UX-PROBLEMS.md` §و) **لا تبنيه ولا تحاكيه في الواجهة** — تترك مكانه فارغًا غير مرسوم أو تُخفي الزرّ.
2. **لا منطق عمل في الواجهة.** الانتقالات القانونية تبقى نسخة `day-spec.ts` الحرفية من السكيما ولا يُضاف إليها؛ «متأخّرة» تُعرض من `due_date` ولا تُخزَّن؛ «الحالة التالية» تُقرأ من القائمة لا تُحسب؛ المطابقة والاكتمال والمهل تُقرأ من الخادم حين تُبنى.
3. **لا حذف لأيّ Feature ولا لأيّ مسار.** المسارات القديمة تبقى بإعادة توجيه (§٨). ما «يُحذف» هو **من الواجهة فقط** وهو محدَّد بالاسم في §٦.
4. **لا نسخة ثانية من أيّ نموذج.** حوارات `DayScreen` و`ResourceScreen` تُعاد فتحها من أماكن جديدة مسبوقة التعبئة — لا حوار حجز ثانٍ، لا حوار دفعة ثانٍ.
5. **لا معرّف طفل في مسارات البوّابة**؛ **الهوية تفشل مقفولة**؛ **401 ينهي الجلسة و403 لا**؛ **`sessionStorage`** لا `localStorage`؛ **الحالات الأربع** (تحميل · فشل مع إعادة · فارغ · بيانات) في كل قالب؛ **لا نصّ واجهة خارج ملفّ الترجمة** (`assets/i18n/ar.json`) — ولا رمز تعبيري في كود يُشحن.
6. **إخفاء زرّ ليس ضابطًا:** الأفعال تُفلتر بـ`auth.can()` كما اليوم، والخادم يرفض. لا تضف شرطًا في الواجهة يقرّر ما يُرى من بيانات.
7. **لا تلمس `web/shared/src/ui/family-messages.ts` الحالي** (يخدم الكونسول) — تبني مكوّن الأسرة الجديد بجواره.

### ١ · الشاشات التي ستُدمج (تصير تبويبًا أو عرضًا)

| من | إلى | كيف |
|---|---|---|
| `/my-day` | `/appointments?view=mine` | `DayScreen` يقبل `view=mine` يرسل `mine=1` (كما يفعل `/my-day` اليوم)؛ الافتراضي `mine` حين يكون لصاحب الجلسة `therapistId`. حارس `/appointments` يقبل **أيًّا** من `APPOINTMENT.BOOK` أو `SESSION.START` (وسّع `permissionGuard` ليقبل مصفوفة — **بلا** تغيير في الأفعال: تبقى مفلترة بصلاحيتها). `subKey/emptyKey` تتبع العرض. |
| `/therapist-services` | `/therapists?tab=services` | `ResourceScreen` يقبل تبويبًا بمكوّن مخصّص (`TherapistServices`) إلى جانب الـ`Spec`s. |
| `/site/team` | `/site?tab=team` | نفس الآلية بمكوّن `TeamScreen`. |
| استبيانات الرضا (`NPS_SURVEYS_SPEC` في `/catalog`) | `/satisfaction?tab=surveys` | «رضا الأسر» = تبويبان: الاستبيانات (`ResourceScreen` بالـ`Spec` نفسه) · النتائج (المكوّن الحالي). حارس المسار `NPS.MANAGE`. |
| الأهداف · القياسات · البرنامج المنزلي (`/plans`) | تبويب «الخطّة» في `/children/:id` | نفس `GOALS_SPEC`/`MEASUREMENTS_SPEC`/`CHILD_ACTIVITIES_SPEC` مع `plan_id`/`child_id` مثبَّتين في الحوار وفلتر القائمة. `/plans` يبقى قائمة الخطط عبر الأطفال (`PLANS_SPEC` وحده). |
| البوّابة: `/progress` + `/reports` | `/progress?tab=progress|reports|notes` «متابعة طفلي» | ثلاثة تبويبات؛ `/reports/:reportId` يبقى كما هو. |
| البوّابة: `/communications` | `/requests?tab=messages` «رسائل المركز» | مكوّن أسرة **جديد** `FamilyThread`: محادثة واحدة مع المركز على `GET /api/v1/family-contacts` (يعيد صفّ الأسرة نفسها) + `GET/POST /family-messages/{guardian_id}` + `/read`. **بلا** بحث في الأسر، **بلا** إرسال جماعي، **بلا** قوالب. |

### ٢ · ما يُحذف من التنقّل فقط (يبقى الكود والمسار)

`/inbox` (يصير `/notifications`)، `/my-day`، `/therapist-services`، `/site/team`، `/access` (يصير `/users`) — كلّها تُزال من `nav.ts` وتُعاد توجيهها (§٨). لا يُحذف مكوّن.

### ٣ · الحالات التي تصير فلاتر (تأكيد ما هو قائم)

الحالات **فلاتر أصلًا** (`?status=`) — **حافظ** على ذلك. الجديد فقط: `?view=day|week|mine` للمواعيد، `?tab=` للتبويبات، `?open=:id` للدرج الجانبي. **لا مسار جديد لأيّ حالة.** المفردات العربية للحالات من `ar.json`؛ أضف `status.appointment.CHECKED_IN` في البوّابة و`status.child.INACTIVE` في الكونسول.

### ٤ · الأفعال التي تصير مهامّ — بناء `/tasks`

**المسار:** `/tasks` · `titleKey: nav.tasks` («المهامّ») · حارس `PORTAL.VIEW` · أوّل بند بعد لوحة التحكم · **شارة بالعدد** في القائمة.

**المصدر — بلا نقطة API جديدة:** خدمة `TasksService` تُنفّذ كتالوج `UX-TASK-INBOX.md` §٢.٣ (K-01…K-23) **كقراءات قائمة**:

| Type | النداء القائم | الشرط في الشاشة (عرض فقط) |
|---|---|---|
| ENROLMENT_TRIAGE | `day.list('enrolments',{status:'NEW'})` | — |
| ENROLMENT_BOOK_ASSESSMENT | `…{status:'CONTACTED'}` | — |
| ENROLMENT_CONVERT | `…{status:'ASSESSMENT_BOOKED'}` | — |
| APPOINTMENT_CONFIRM | `day.list('appointments',{date:today,status:'BOOKED'})` | — |
| APPOINTMENT_CHECK_IN | `…{date:today,status:'CONFIRMED'}` | `starts_at <= now + 15min` (عرض) |
| SESSION_START | `…{date:today,status:'CHECKED_IN', mine:1}` | `session_id == null` |
| SESSION_CLOSE | `day.list('sessions',{date:today,status:'IN_PROGRESS'})` (+`mine` للأخصائي) | — |
| SESSION_NOTE | `day.list('sessions',{date:today,status:'COMPLETED', mine:1})` | إن أعاد الصفّ مؤشّر الملاحظة؛ وإلّا **لا تبنِ هذا النوع** |
| REPORT_FINISH | `day.list('reports',{status:'DRAFT'})` | — |
| REQUEST_DECIDE | `day.list('requests',{status:'NEW'})` | — |
| INVOICE_ISSUE | `day.list('invoices',{status:'DRAFT'})` | — |
| INVOICE_OVERDUE | `day.list('invoices',{status:'ISSUED'})` + `PARTIALLY_PAID` | `due_date < today` (عرض) |
| PACKAGE_RENEW | `GET /billing/ledger?kind=balances` | `sessions_left <= 2` أو `expires_on <= today+14d` (**عرض؛ العتبتان ثابتتان مؤقّتًا وتُقرآن من `/settings/params` حين تُضاف**) |
| CHILD_ASSIGN_THERAPIST | `crud.list('children')` × `crud.list('caseload')` | طفل نشط بلا صفّ إسناد |
| CONSENT_MISSING | يظهر **عند** رفض `CONSENT_REQUIRED`/`PHOTO_CONSENT_MISSING` فقط | — |
| THERAPIST_PROFILE_CONSENT | `crud.get('therapists', me.therapistId)` | `profile_status='DRAFT'` وبلا موافقة |
| SCHEDULE_CONFLICT | نفس حساب لوحة «تداخلات» الحالي | — |
| SITE_PUBLISH | `crud.list('site-*')` بـ`status=DRAFT` (اختياري) | — |

**لا تبنِ** K-13 (أقساط)، K-15 (اعتماد الخطّة)، K-17 (منح الحساب)، K-21 (الاكتمال)، K-22 (الاستشارة/الإيصالات) — **لا مسار لها**. اترك أنواعها معرَّفة في الكتالوج بعلامة `available: false` ولا تُرسم.

**العنصر:** `Type · Business Object (رقم + اسم) · Parent/Child · Current Status (badge) · Required Action · Priority (عاجل إن تجاوز العمر عتبة النوع) · Assigned (الصلاحية/أنا) · Due (إن وُجد تاريخ) · CTA · رابط الكيان`. **CTA يفتح الحوار القائم نفسه** (`DayScreen` action dialog مستخرج إلى خدمة `ActionDialogService` تستقبل `spec + action + row` — إعادة استعمال لا نسخ). **رابط الكيان** إلى شاشة التفصيل (§٥) أو الصفّ المفلتر.

**الفلاتر:** النوع · العاجل فقط · «لي» · اليوم/الأسبوع. **الترتيب:** العاجل ثم الأقدم. **الحالات الأربع** إلزامية، والفارغ إيجابي: «لا شيء ينتظرك الآن».

**الداشبورد:** بطاقات `wantsAction` تربط إلى `/tasks?type=…`؛ لوحة «التنبيهات والمتابعة» تصير معاينة أوّل 5 من `TasksService` (مصدر واحد). أخفِ بطاقتي «الغرف» و«التنبيهات» اللتين بلا قراءة.

**الشارة:** عدد المهامّ من نفس الخدمة، يُحدَّث عند `NavigationEnd` (كما تفعل البوّابة للجرس) — **لا استطلاع دوري**.

### ٥ · شاشات التفصيل

وفق `UX-DETAIL-PAGES.md` حرفيًّا:

- **`/enrolments/:applicationId`** (جديد): رأس + CTA حسب الحالة **مأخوذ من `ENROLMENT_NEXT` القائم** + تبويبات (نظرة عامّة · الأسرة · المستفيد · موعد التقييم · التواصل · السجلّ). التقييم: زرّ «احجز موعد التقييم» يفتح حوار الحجز ثم — عند نجاحه — يفتح حوار الحالة إلى `ASSESSMENT_BOOKED` (نداءان متتاليان، لا تجميع). قبل التحويل لا `child_id`، فتبويب الموعد يعرض «يُربط بعد التحويل».
- **`/guardians`** (جديد، `GUARDIANS_SPEC` + master-detail القائم) و**`/guardians/:guardianId`**: رأس + تبويبات (المستفيدون · البيانات · الموافقات **بأنواعها الأربعة** على `POST/DELETE /guardians/{id}/consent` · الفواتير · المحادثة · الطلبات). زرّ «منح حساب البوّابة» **لا يُرسم** (R-05).
- **`/children/:childId`** (موسَّع): أفعال الرأس (حجز · فاتورة · بيع باقة · تعيين أخصائي · خطّة جديدة · تقرير · رسالة · كرت) عبر `ActionDialogService` مع `child_id` مثبَّتًا ومقفولًا في الحوار؛ تبويب «الخطّة» كما في §١؛ تبويب «الأخصائي المسؤول» (`caseload` لهذا الطفل + زرّ التعيين)؛ إعادة تسمية `child.tab.activityLog` → «البرنامج المنزلي». **لا ترسم** تبويبَي «التقييمات» و«الخطّ الزمني».
- **الموعد:** درج جانبي على `/appointments?open=:id` — رأس + CTA الانتقال التالي (من `actionsFor(row)`) + التفاصيل + الجلسة المرتبطة + طلبات الأسرة عليه. **لا** سجلّ حالات (لا قراءة له).
- **الفاتورة:** درج جانبي على `/billing?open=:id` — السطور (+ **زرّ حذف السطر** على `DayApi.removeInvoiceLine` القائم، مسودّة فقط) · الدفعات · CTA (إصدار/دفعة). **لا** أقساط ولا إيصالات.

### ٦ · تنظيم التبويبات والقائمة

**الكونسول — `nav.ts` بمجموعات** (`UX-TARGET-INFORMATION-ARCHITECTURE.md` §١ حرفيًّا): لوحة التحكم · المهامّ · الإشعارات · **العملاء** (طلبات الالتحاق · أولياء الأمور · المستفيدون) · **التشغيل** (المواعيد · الجلسات · الخطط والأهداف · التقارير) · **الماليات** (الفواتير والمدفوعات) · **التواصل** (طلبات أولياء الأمور · المحادثات) · **الفريق** (الأخصائيون · ملفّي · المستخدمون والأدوار) · **الإعدادات** (الكتالوج · الغرف والكاميرات · رضا الأسر · الموقع التعريفي · بارامترات المركز · سجلّ التشغيل). المجموعة تظهر إن ظهر فيها بند. أيقونة «المحادثات» تختلف عن «الطلبات». **الحراس** بأسماء صلاحيات القاعدة: `/settings` → `SETTINGS.MANAGE`، `/satisfaction` → `NPS.MANAGE`، `/users` → `USER.MANAGE` (تبويب ملفّات الموظّفين يظهر بـ`STAFF.PII`).

**البوّابة — الغلاف:** مبدّل المستفيد في الرأس (يقرأ `ChildContextService` والقائمة من `/children`)؛ شريط الهاتف: الرئيسية · المواعيد · متابعة طفلي · البرنامج المنزلي · **المزيد** (الفواتير · طلباتي · رسائل المركز · الإشعارات · حسابي)؛ جرس في رأس الهاتف. «ما يحتاج انتباهك» ينتقل إلى الرئيسية ويعمل لكل الأطفال (أصلح التوجيه بالطفل). صفّ الموعد يفتح حوار طلب مربوطًا بـ`appointment_id` و`child_id` الصحيحين.

**يُحذف من واجهة البوّابة (لا من الكود العامّ):** «لحظة مهمّة» في `/live` · مفاتيح الموافقة في `/profile` (تصير قراءة بنصّ «تُدار من المركز») · إلغاء تعليم النشاط · رسم التقدّم الفارغ · `AlertsService` (ميّت). «طرق الدفع» → نصّ صادق «الدفع يتمّ في المركز»؛ رفض «غير مسدَّدة» في الاستشارة → «طلباتي» بنصّ «تواصل مع المركز للسداد».

### ٧ · ماذا يرى كل دور

لا كود للأدوار. الواجهة تقرأ `GET /me.permissions` **فقط** وترسم — والجداول في `UX-ROLE-BASED-VIEWS.md` هي **الناتج المتوقَّع** للتحقّق لا مدخلًا: تأكّد بعد التنفيذ أن حسابًا بدور `RECEPTION` يرى المجموعات الأربع الأولى دون الفريق والإعدادات، وأن `THERAPIST` يرى «مواعيدي» افتراضيًّا و«ملفّي»، وأن `CENTER_ADMIN` **لا** يرى زرّ كتابة ملاحظة الجلسة.

### ٨ · المسارات القديمة ← الجديدة (إعادة توجيه، لا حذف)

`/inbox → /notifications` · `/my-day → /appointments?view=mine` · `/therapist-services → /therapists?tab=services` · `/site/team → /site?tab=team` · `/access → /users` · البوّابة `/reports → /progress?tab=reports` (و`/reports/:id` يبقى) · البوّابة `/communications → /requests?tab=messages`. أصلح `inbox-api.ts target(INVOICE)` → `['/billing'], {open: id}` (كان `/invoices` — مسار غير موجود). كل رابط داخل الإشعارات والرسائل القديمة يجب أن يصل.

### ٩ · ما يُحافَظ عليه من منطق العمل (لا يُمسّ)

- الآلات المنسوخة في `day-spec.ts` (`APPOINTMENT_NEXT`, `SESSION_NEXT`, `ENROLMENT_NEXT` — `ENROLLED` تبقى غير قابلة للاختيار: `convert` وحده يصل إليها).
- `validate` قبل `book`، والفتحات من `GET /appointments/slots` (403 ليس يومًا فارغًا).
- placeholders المتعمَّدة في الحوارات («اختر…» — لا نموذج مُجاب سلفًا).
- «الصفوف تتحرّك بآلة الحالة لا بتعديل عمود» — لا حقل حالة قابل للتحرير في أيّ محرّر.
- تفريق «مرفوض» عن «صفر» في الداشبورد (الشرطة).
- الحفظ الآلي والنسخة المتوقَّعة في محرّر التقرير (`REPORT_CHANGED`).
- الكرت بلا رقم قومي ولا عنوان ولا بيانات صحّية.

### ١٠ · الحفاظ على الـAPI ومنع كسر الخادم

- **صفر تغيير** في `core/api/*.ts` و`core/ops/day-api.ts` عدا إضافة `?view=` في طبقة التوجيه (لا في النداء) وإصلاح `target(INVOICE)`. `TasksService` و`ActionDialogService` **تستهلكان** الخدمات القائمة.
- لا استدعاء لنقطة غير موجودة في `docs/02-api-contract.md` أو `server.go`. إن وجدت نفسك تحتاج نقطة: **توقّف واكتب توصية** في `docs/UX-PROBLEMS.md` §و بدل بنائها أو محاكاتها.
- كل رفض `businessRefusal` القائم يبقى مترجَمًا بالاسم (`error.{CODE}`) — أضف مفاتيح للرموز التي تُظهرها الشاشات الجديدة (`CONSENT_REQUIRED`, `PHOTO_CONSENT_MISSING`, `MOBILE_NOT_A_GUARDIAN`, `MOBILE_HELD_BY_GUARDIAN`, `REPORT_CHANGED`).
- الفارغ لا يصير صفرًا في أيّ حقل رقمي (درس `INVOICE_REQUIRE_CATALOGUE_PRICE`).

### ١١ · التسليم والقبول

- **قبل البدء:** اطبع قائمة الملفّات التي ستمسّها؛ إن ظهر فيها ملفّ تحت `api/` أو `db/` أو `web/shared/src/ui/family-messages.ts` فقد أخطأت.
- **الترتيب:** (١) القائمة والحراس وإعادة التوجيه → (٢) الإشعارات (تسمية + الرابط) → (٣) `TasksService` + `/tasks` + الشارة + الداشبورد → (٤) `ActionDialogService` + أفعال ملفّ المستفيد → (٥) `/enrolments/:id` → (٦) `/guardians` + التفصيل → (٧) الدرجان → (٨) البوّابة (الغلاف، المزيد، الدمج، مكوّن الأسرة، الإخفاءات). كل خطوة تُبنى وتُشغَّل وتُقاس في المتصفّح قبل التالية.
- **الأدلّة المطلوبة لكل خطوة:** لقطة شاشة لكل دور (A/R/T) · كل مسار قديم يصل بإعادة التوجيه (اختبار توجيه) · `/tasks` على قاعدة فيها صفّ واحد على الأقل لكل نوع مبنيّ **وعلى قاعدة فارغة** (الفارغ الإيجابي) · **عدد الاختبارات التي نُفِّذت لا كود الخروج** (`ng test` أعاد صفرًا ثلاث مرّات بلا متصفّح — `HBH-046`).
- **لا تُغلق البطاقة عند اكتمال الشاشة** — تُغلق حين يمرّ المستخدم بالتدفّق: مهمّة → CTA → الحوار القائم → تنجح → تختفي المهمّة وحدها.
- **ما تجده ناقصًا في الخادم** يُكتب توصيةً باسمه ورقمه ولا يُبنى.

---

## ملحق — ما ينتظر قرار المالك قبل التنفيذ (لا يحجب البدء)

| القرار | أثره على التنفيذ |
|---|---|
| `OQ-13` هل يقبض الاستقبال؟ | إن نعم: `BILLING.MANAGE` للاستقبال في البذور (خارج الواجهة) فتظهر له أزرار الدفعة تلقائيًّا |
| `OQ-14` هل يرى الأخصائي كل الأطفال؟ | إن لا: فلتر «حالاتي» افتراضي في المستفيدين — بعد قرار في RLS لا في الواجهة |
| `BL-45` تسمية «مستفيد» | معتمَد للواجهة فقط (`OD-23`)؛ يُنفَّذ في `ar.json` |
| `R-06` عرض `v_staff_tasks` | إن بُني: `TasksService` يتحوّل إلى نداء واحد بلا تغيير في الشاشة |

</details>
