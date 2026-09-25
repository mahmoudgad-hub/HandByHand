# UX-SCREEN-INVENTORY — مراجعة الوضع الحالي

**2026-09-14 · تحليل فقط، لا تنفيذ معتمد.** القسم الأعلى هو المرجع الحالي. التحليل السابق محفوظ في آخر الملف للأرشفة ولا يمثل العمل المتبقي.

**العدد الحالي: 49 شاشة تطبيق = 31 للمركز + 18 للبوابة. المستهدف: 47 = 31 + 16، بدمجين مقترحين في البوابة.** نعد كل route يرسم شاشة بما فيه الدخول والرفض والطباعة ونمطا إنشاء/تحرير التقرير؛ لا نعد shell أو redirects أو wildcard. لذلك هذا عدد مسارات شاشات وليس عدد المكونات أو بنود القائمة. الموقع العام site يضيف صفحتين، فيصير الإجمالي الموسع 51 → 49. website/index.html وhtml/ وfigma/ مراجع منفصلة لا يثبت وجودها أنها تشغيل فعلي.

**صفر حالات مستخدمة كصفحات انتظار مستقلة.** /live أداة مشاهدة قائمة، لا حالة متنكرة في شاشة. /my-day كان فلترًا بمسار وأصبح redirect بالفعل. لا صفحات انتظار ولي أمر/إسناد أخصائي في routes الحالية.

**حدود الإثبات:** جرد ساكن لكل routes ومصادر النماذج والأفعال وAPI، وتحليل للمنطق في Go والمهاجرات المتاحة، مع مشاهدة حية للدخول ولوحة المدير والمهام. لم تُختبر كل شاشة وكل دور عمليًا، ولم تُنفذ كتابة أعمال أو إرسال رسائل. تعذرت قراءة 0005_scheduling.up.sql و0006_plans_and_notes.up.sql بصلاحيات البيئة؛ لا ندعي اكتمال تدقيق SQL. تشغيل DB الحي قد يختلف عن ملفات الهجرة. تفاصيل الأدلة في [UX-AUDIT-SOURCE-INDEX.md](UX-AUDIT-SOURCE-INDEX.md)، والمسارات المحسوبة في [UX-AUDIT-ROUTES.json](UX-AUDIT-ROUTES.json).

## Screen Inventory الحالي

API المختصرة تبدأ بـ /api/v1؛ اسم مجموعة API مرجع لخدمتها في فهرس المصدر أدناه، وليس endpoint جديدًا. CRUD يشمل البحث والإضافة والتعديل والأرشفة/الاستعادة حسب حقوق المورد.


### ops

| Screen | Route | Role / Permission | Business Purpose | Main Entity | Actions | Statuses | Related Screens | Problem |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| دخول الموظفين | /login | مصادقة/ضيف وفق guard | دخول وإعداد كلمة المرور | User | دخول/إظهار كلمة المرور/رمز إعداد | guest/authenticated | /dashboard | أساسية؛ R10 |
| المحادثات | /communications | REQUEST.MANAGE | رسائل الأسر | FamilyMessage | بحث/قراءة/إرسال/قوالب/جماعي | read/unread | /guardians/:guardianId | أساسية؛ حافظ على سياق الأسرة |
| المهامّ | /tasks | PORTAL.VIEW | العمل المطلوب | DerivedTask | تصفية/فتح سجل أو drawer | حالة السجل المصدر | الطلبات والطفل والمواعيد والماليات | موجودة؛ R02/R04/R05 |
| الإشعارات | /notifications | PORTAL.VIEW | ما حدث للمستخدم | Notification | تحديث/مقروء/فتح هدف | read/unread | السجل المصدر | أساسية؛ فصلها منفذ |
| لوحة التحكم | /dashboard | PORTAL.VIEW | نظرة المركز | Aggregate | عدادات وروابط وتحديث | حالات مشتقة | /tasks;/appointments;/billing | أساسية؛ عدد الصادر لا يساوي المتأخر |
| أولياء الأمور | /guardians | GUARDIAN.MANAGE | دليل الأسر | Guardian | CRUD/بحث/استعادة | active/archived | /guardians/:guardianId | أساسية موجودة |
| ملفّ وليّ الأمر | /guardians/:guardianId | GUARDIAN.MANAGE | ملف الأسرة | Guardian | تعديل/اتصال/أبناء/طلبات/ماليات | حالات الكيانات المرتبطة | الطفل والطلب وdrawers | DETAIL PAGE؛ R03 |
| المستفيدون | /children | CHILD.VIEW_ALL | دليل المستفيدين | Child | CRUD/بحث/استعادة | ACTIVE/INACTIVE/GRADUATED/WITHDRAWN | /children/:childId | أساسية؛ أولياء الأمور منفصلون بالفعل |
| ملفّ المستفيد | /children/:childId | CHILD.VIEW_ALL | مركز تعامل المستفيد | Child | حجز/إسناد/فاتورة/تقرير/موافقات/drawers | حالات المرتبط | ملف الأسرة/التقرير/البطاقة | DETAIL PAGE بأفعال موجودة |
| تقرير تقدّم جديد | /children/:childId/reports/new | REPORT.WRITE | محرر تقرير | ProgressReport | حفظ آلي/معاينة/نشر | DRAFT/PUBLISHED | ملف الطفل;/reports | DETAIL PAGE؛ إنشاء وتعديل لنفس المكون |
| تعديل التقرير | /children/:childId/reports/:reportId | REPORT.WRITE | محرر تقرير | ProgressReport | حفظ آلي/معاينة/نشر | DRAFT/PUBLISHED | ملف الطفل;/reports | DETAIL PAGE؛ إنشاء وتعديل لنفس المكون |
| كرت هويّة الطفل | /children/:childId/card | CHILD.VIEW_ALL | بطاقة مطبوعة | Child | معاينة/طباعة | — | ملف الطفل | PAGE طباعة خارج القائمة |
| الأخصائيون | /therapists | STAFF.MANAGE | إدارة الفريق | Therapist/WorkingHours/Caseload/Service | CRUD/إسناد/مصفوفة خدمة | ACTIVE/ON_LEAVE/RESIGNED | /therapists/:therapistId/profile | أساسية؛ الخدمات تبويب منفذ؛ R05 |
| الغرف والكاميرات | /rooms | CATALOG.MANAGE | موارد المركز | Room/Camera | CRUD/فتح البث | ONLINE/OFFLINE/FAULT/DISABLED | /sessions/:sessionId/live | إعدادات أساسية |
| الخطط العلاجية | /plans | PLAN.MANAGE | العمل السريري | TreatmentPlan/Goal/Measurement/ChildActivity | CRUD وقياسات وأنشطة | DRAFT/ACTIVE/COMPLETED/CANCELLED; OPEN/MET/DROPPED | ملف الطفل | أساسية؛ R09؛ لا اعتماد وهمي |
| الخدمات والباقات | /catalog | CATALOG.MANAGE | كتالوج المركز | Service/Package/ActivityLibrary | CRUD | active/archived | /billing | أساسية؛ وضح جهة تعديل الأسعار |
| الموقع التعريفي | /site | SITE.EDIT | محتوى الموقع | SiteContent/SiteTeam | CRUD/رفع/نشر بحسب الحق | DRAFT/PUBLISHED | site/index.html | أساسية؛ الفريق تبويب منفذ |
| المواعيد | /appointments | APPOINTMENT.BOOK OR SESSION.START | جدول المركز/مواعيدي | Appointment | slots/validate/book/status/start/drawer | BOOKED/CONFIRMED/CHECKED_IN/COMPLETED/CANCELLED/NO_SHOW | /sessions;ملف الطفل | أساسية؛ R06 |
| الجلسات | /sessions | SESSION.START | الجلسات | TherapySession | ملاحظة/إغلاق/بث | IN_PROGRESS/COMPLETED/ABORTED | المواعيد والطفل | أساسية؛ R04 |
| التقارير | /reports | REPORT.VIEW | دفتر التقارير | ProgressReport | فلتر/نشر/تصدير | DRAFT/PUBLISHED | محرر التقرير والطفل | أساسية؛ وحّد فتح المحرر |
| الفواتير والمدفوعات | /billing | BILLING.VIEW | الماليات | Invoice/Payment/ChildPackage | إنشاء/سطر/إصدار/دفعة/بيع باقة/drawer | DRAFT/ISSUED/PARTIALLY_PAID/PAID/CANCELLED | الطفل والأسرة | أساسية؛ قراءة لا تعني قبضًا |
| طلبات أولياء الأمور | /requests | REQUEST.MANAGE | قرار طلب الأسرة | ParentRequest | قبول/رفض وملاحظة | NEW/ACCEPTED/REJECTED | /appointments;/communications | أساسية؛ R07 |
| طلب الالتحاق | /enrolments/:applicationId | ENROLMENT.MANAGE | تفصيل طلب الالتحاق | EnrolmentApplication | 8 تبويبات/حالة/تحويل/اتصال | حالات الالتحاق | الطفل والأسرة بعد التحويل | DETAIL PAGE موجودة؛ R01 |
| طلبات الالتحاق | /enrolments | ENROLMENT.MANAGE | طابور الالتحاق | EnrolmentApplication | جدول/مراحل/حالة/تحويل/أرشفة | NEW/CONTACTED/ASSESSMENT_BOOKED/ENROLLED/REJECTED/DUPLICATE | /enrolments/:applicationId | أساسية؛ الحالات فلاتر؛ R01 |
| ملفّ الأخصائي | /therapists/:therapistId/profile | مصادقة/ضيف وفق guard | الملف العام للأخصائي | TherapistProfile | نبذة/لغات/شهادات/موافقة/نشر | DRAFT/PUBLISHED/WITHDRAWN | /therapists | DETAIL PAGE؛ ملكية الصف |
| البث المباشر | /sessions/:sessionId/live | LIVE.VIEW | بث حي | Session/Stream | مشاهدة/ملاحظة موقوتة | جلسة جارية | /sessions | PAGE أداة؛ لا تسجيل |
| المستخدمون والأدوار | /users | USER.MANAGE | الحسابات والحقوق | User/Role/StaffDocument | CRUD/أدوار/مستندات/إعداد كلمة مرور | ACTIVE/SUSPENDED/LOCKED | /settings | أساسية؛ الصلاحيات من الخادم |
| رضا الأسر | /satisfaction | NPS.MANAGE | الرضا | NpsSurvey/NpsResponse | تعريف استبيان/نتائج | active/archived | /dashboard | PAGE بتبويب REPORT؛ الدمج منفذ |
| سجلّ التشغيل | /ops-log | OPS.VIEW | رقابة التشغيل | RequestLog | فلاتر/ملخص/أخطاء/أداء | HTTP status | الإعدادات | REPORT تقني |
| الإعدادات | /settings | SETTINGS.MANAGE | بارامترات المركز | CenterParam | قراءة وتعديل المتاح | — | /users | أساسية؛ تعليق read-only قديم |
| لا تسمح صلاحيتك بفتح هذه الشاشة | /denied | مصادقة/ضيف وفق guard | شرح رفض الوصول | PermissionRefusal | عودة | denied | /dashboard | PAGE نظامية بلا قائمة |

| Route | API family / calls | Source |
| --- | --- | --- |
| /login | POST /auth/staff/login; /auth/password-setup | web/ops/src/app/app.routes.ts:54 |
| /communications | GET /family-contacts; GET/POST /family-messages/{id}; POST /read | web/ops/src/app/app.routes.ts:65 |
| /tasks | GET قوائم DayApi وchildren/caseload/therapists | web/ops/src/app/app.routes.ts:66 |
| /notifications | GET /notifications; POST /notifications/{id}/read | web/ops/src/app/app.routes.ts:75 |
| /dashboard | قراءات Dashboard وDayApi القائمة | web/ops/src/app/app.routes.ts:86 |
| /guardians | CRUD /guardians | web/ops/src/app/app.routes.ts:95 |
| /guardians/:guardianId | GET /guardians/{id}; /children?guardian_id=; /enrolments;/requests; child reads | web/ops/src/app/app.routes.ts:107 |
| /children | CRUD /children | web/ops/src/app/app.routes.ts:117 |
| /children/:childId | GET /children/{id} وملاحقه؛ أفعال DayApi/ResourceSpec | web/ops/src/app/app.routes.ts:127 |
| /children/:childId/reports/new | GET/POST/PATCH /reports; POST /reports/{id}/publish | web/ops/src/app/app.routes.ts:143 |
| /children/:childId/reports/:reportId | GET/POST/PATCH /reports; POST /reports/{id}/publish | web/ops/src/app/app.routes.ts:160 |
| /children/:childId/card | GET /children/{id}; /photo | web/ops/src/app/app.routes.ts:167 |
| /therapists | CRUD /therapists,/working-hours,/caseload; therapist services | web/ops/src/app/app.routes.ts:177 |
| /rooms | CRUD /rooms,/cameras | web/ops/src/app/app.routes.ts:194 |
| /plans | CRUD /plans,/goals,/measurements,/child-activities | web/ops/src/app/app.routes.ts:204 |
| /catalog | CRUD /services,/packages,/activity-library | web/ops/src/app/app.routes.ts:218 |
| /site | CRUD site-*; POST /site-media | web/ops/src/app/app.routes.ts:230 |
| /appointments | GET /appointments,/appointments/slots,/service-therapists; POST /appointments/validate,/appointments; PATCH /appointments/{id}/status; POST /session | web/ops/src/app/app.routes.ts:271 |
| /sessions | GET /sessions; PUT /sessions/{id}/note; PATCH /close | web/ops/src/app/app.routes.ts:308 |
| /reports | GET /reports; POST /reports/{id}/publish | web/ops/src/app/app.routes.ts:317 |
| /billing | GET /invoices,/payments,/child-packages; POST /invoices وملحقاته; POST /children/{id}/packages | web/ops/src/app/app.routes.ts:326 |
| /requests | GET /requests; PATCH /requests/{id} | web/ops/src/app/app.routes.ts:335 |
| /enrolments/:applicationId | GET/PATCH /enrolments/{id}; POST /convert; child appointments/plans | web/ops/src/app/app.routes.ts:344 |
| /enrolments | GET /enrolments; PATCH /enrolments/{id}; POST /convert | web/ops/src/app/app.routes.ts:354 |
| /therapists/:therapistId/profile | therapists/{id}/profile,languages,certificates,consent,publish | web/ops/src/app/app.routes.ts:366 |
| /sessions/:sessionId/live | POST /sessions/{id}/stream; PUT /note | web/ops/src/app/app.routes.ts:389 |
| /users | GET/POST /users; PATCH/DELETE /users/{id}; PUT /roles; password-setup/documents; GET /roles,/permissions | web/ops/src/app/app.routes.ts:398 |
| /satisfaction | CRUD /nps-surveys; NPS reads | web/ops/src/app/app.routes.ts:410 |
| /ops-log | OpsLog API | web/ops/src/app/app.routes.ts:428 |
| /settings | Settings API; GET /me | web/ops/src/app/app.routes.ts:437 |
| /denied | لا كتابة | web/ops/src/app/app.routes.ts:449 |

### portal

| Screen | Route | Role / Permission | Business Purpose | Main Entity | Actions | Statuses | Related Screens | Problem |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| بوابة ولي الأمر | /login | ولي أمر؛ ضيف للدخول والتقديم | طلب الدخول | Session | طلب رمز | SENT/NOT_REGISTERED/ENROLMENT_PENDING | /login/otp | أساسية |
| أدخل رمز التحقّق | /login/otp | ولي أمر؛ ضيف للدخول والتقديم | التحقق | Session | تحقق/إعادة رمز | valid/expired | /welcome | مرحلة دخول مسار فرعي |
| طلب التحاق | /apply | ولي أمر؛ ضيف للدخول والتقديم | طلب بلا حساب | EnrolmentApplication | معالج تقديم/إرسال/طفل آخر | NEW عند النجاح | الموقع ثم الدخول | أساسية؛ لا account فوري مفترض |
| أهلاً بك | /welcome | ولي أمر؛ ضيف للدخول والتقديم | اختيار الطفل | ChildContext | اختيار | selected/unselected | /home | أساسية أول دخول |
| المحادثات | /communications | ولي أمر؛ ضيف للدخول والتقديم | رسائل المركز | FamilyMessage | قراءة/إرسال | read/unread | /requests | دمج TAB تحت requests؛ بلا شرط طفل |
| الرئيسية | /home | ولي أمر؛ ضيف للدخول والتقديم | ملخص طفلي | ChildSummary | فتح موعد/تقرير/خدمة | حالات الملخص | /schedule;/reports;/billing | أساسية |
| المواعيد | /schedule | ولي أمر؛ ضيف للدخول والتقديم | جدول الطفل | Appointment | قادمة/سابقة/طلب تعديل/استشارة | حالات الموعد | /requests;consultation | أساسية |
| التقدّم | /progress | ولي أمر؛ ضيف للدخول والتقديم | متابعة التقدم | Goal/Measurement | قراءة أهداف/قياسات | الخطة/الهدف | /reports | تصبح متابعة طفلي مع tabs |
| البرنامج المنزلي | /activities | ولي أمر؛ ضيف للدخول والتقديم | البرنامج المنزلي | ChildActivity/ActivityLog | تسجيل الإنجاز | done/not-done | /home | أساسية للعمل اليومي |
| بث مباشر | /live | ولي أمر؛ ضيف للدخول والتقديم | مشاهدة الطفل | Stream | بث حي | جلسة مؤهلة وموافقة | /home | PAGE أداة لا STATUS |
| استشارة أونلاين | /consultation/:appointmentId | ولي أمر؛ ضيف للدخول والتقديم | دخول الاستشارة | Meeting/Appointment | طلب إذن ودخول | موعد مؤهل ونافذة دخول | /schedule | أداة PAGE دون childSelectedGuard |
| التقارير والملاحظات | /reports | ولي أمر؛ ضيف للدخول والتقديم | التقارير والملاحظات | ProgressReport/SessionNote | قراءة وفتح تقرير | PUBLISHED | /reports/:reportId | دمج TAB في progress |
| التقرير | /reports/:reportId | ولي أمر؛ ضيف للدخول والتقديم | قراءة التقرير | ProgressReport | عرض/طباعة | PUBLISHED | /reports | DETAIL PAGE تبقى؛ تحديث العودة |
| الفواتير والباقات | /billing | ولي أمر؛ ضيف للدخول والتقديم | ماليات الأسرة | Invoice/ChildPackage | عرض فواتير وباقات | حالات الفاتورة | /home | أساسية؛ لا دفع إلكتروني مفترض |
| طلباتي | /requests | ولي أمر؛ ضيف للدخول والتقديم | طلبات الأسرة | ParentRequest | تعديل/إلغاء/مكالمة ومتابعة | SUBMITTED/ACCEPTED/DECLINED عبر adapter | /schedule;/communications | PAGE؛ يضاف tab رسائل؛ UNDER_REVIEW ليس حالة خادم |
| ملفّ الأخصائي | /therapists/:therapistId | ولي أمر؛ ضيف للدخول والتقديم | التعرف على الأخصائي | TherapistProfile | قراءة منشور | PUBLISHED | /schedule | DETAIL PAGE |
| الإشعارات | /notifications | ولي أمر؛ ضيف للدخول والتقديم | أحداث للأسرة | Notification | قراءة/فتح هدف | read/unread | السجل الهدف | أساسية عابرة للأطفال |
| حسابي | /profile | ولي أمر؛ ضيف للدخول والتقديم | حسابي | Guardian | قراءة/تعديل المتاح/خروج | — | /welcome | أساسية؛ عقد API يحدد الأفعال |

| Route | API family / calls | Source |
| --- | --- | --- |
| /login | Auth OTP API | web/portal/src/app/app.routes.ts:15 |
| /login/otp | Auth verify API | web/portal/src/app/app.routes.ts:20 |
| /apply | POST /enrolments | web/portal/src/app/app.routes.ts:26 |
| /welcome | GET /children; welcome reads | web/portal/src/app/app.routes.ts:39 |
| /communications | GET /family-contacts; GET/POST /family-messages/{id} | web/portal/src/app/app.routes.ts:50 |
| /home | GET /children/{id}/home | web/portal/src/app/app.routes.ts:51 |
| /schedule | GET /children/{id}/appointments | web/portal/src/app/app.routes.ts:57 |
| /progress | GET child plans/measurements | web/portal/src/app/app.routes.ts:64 |
| /activities | GET /children/{id}/activities; POST /children/{id}/activities/{id}/log | web/portal/src/app/app.routes.ts:71 |
| /live | POST /sessions/{id}/stream | web/portal/src/app/app.routes.ts:78 |
| /consultation/:appointmentId | Meeting API الحالية | web/portal/src/app/app.routes.ts:84 |
| /reports | GET child reports/notes | web/portal/src/app/app.routes.ts:104 |
| /reports/:reportId | GET /reports/{id} | web/portal/src/app/app.routes.ts:111 |
| /billing | PortalApi billing reads | web/portal/src/app/app.routes.ts:121 |
| /requests | GET/POST /children/{id}/requests | web/portal/src/app/app.routes.ts:127 |
| /therapists/:therapistId | therapist profile API | web/portal/src/app/app.routes.ts:134 |
| /notifications | GET /notifications; POST /notifications/{id}/read | web/portal/src/app/app.routes.ts:148 |
| /profile | PortalApi profile/auth | web/portal/src/app/app.routes.ts:158 |

## الموقع والروابط القديمة

| Screen | Route/file | Role | Purpose | Entity | Actions | Statuses | Related | Problem |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| الرئيسية العامة | site/index.html | زائر | تعريف المركز | SiteContent | أقسام/اتصال/تقديم | published | portal /apply | أقسام الصفحة ليست pages |
| الخصوصية | site/privacy.html | زائر | سياسة الموقع | Policy | عودة | — | site/index.html | صفحة فعلية |
| مرجع HTML | website/index.html | مصمم | نسخة تصميم منفصلة | Marketing | Popup/روابط | — | website/README.md | غير مثبتة كواجهة تشغيل |
| نماذج التصميم | html/;figma/ | مصمم | مرجع | Mockups | معاينة | — | التصاميم | لا تثبت workflows من أسمائها |

| App | Legacy route | Redirect |
| --- | --- | --- |
| ops | /inbox | 'notifications' |
| ops | /therapist-services | movedTo('/therapists', { tab: 'services' }) |
| ops | /site/team | movedTo('/site', { tab: 'team' }) |
| ops | /my-day | movedTo('/appointments', { view: 'mine' }) |
| ops | /access | 'users' |
| ops | / | '/dashboard' |
| ops | /** | '/dashboard' |
| portal | /otp | 'login/otp' |
| portal | / | '/welcome' |
| portal | /** | '/welcome' |

تفاصيل النماذج والحقول والتبويبات وأفعال API في [UX-AUDIT-SOURCE-INDEX.md](UX-AUDIT-SOURCE-INDEX.md). محركات ResourceScreen/DayScreen توسّع تعريفات الموارد؛ عدد مكوناتها ليس عدد الشاشات.

<details>
<summary>أرشيف التحليل السابق — غير معتمد كوصف للحالة الحالية أو تكليف تنفيذ</summary>

# UX Screen Inventory — Hand By Hand (new)

**المرحلة ٢ من تدقيق المنتج/التجربة.** جرد كل شاشة قائمة فعلًا في التطبيقين — كونسول المركز `web/ops` وبوّابة وليّ الأمر `web/portal` — من الكود لا من أسماء الملفّات: المسارات (`app.routes.ts`)، القائمة (`layout/shell/nav.ts`)، محرّكا الشاشات العامّان (`core/resource/resource-spec.ts` و`core/ops/day-spec.ts`)، وخدمات الـAPI (`core/api/*`, `core/ops/day-api.ts`)، مقابل الموجّه في `api/internal/http/server.go` والسكيما في `db/migrations`.

**التاريخ:** 2026-09-13 · **المؤلّف:** محلّل الأعمال / مصمّم المنتج · **القاعدة:** لا تعديل كود في هذه المرحلة.

> **ما ليس في هذا الجرد:** شاشات مخطَّطة لم تُبنَ (`FE-01`…`FE-14` في `09`، `FE-P1`…`FE-P4` و`FE-C1`…`FE-C9` في `11`). تُذكر في خريطة التدفّق حيث تقع، لا هنا. **الجرد يصف الموجود.**

---

## ٠ · الأرقام أوّلًا

| | كونسول المركز | بوّابة وليّ الأمر | المجموع |
|---|---|---|---|
| مسارات حقيقية (بلا إعادة توجيه) | **31** | **17** | **48** |
| منها في القائمة/شريط التبويب | 22 (قائمة جانبية مسطّحة) | 5 هاتف / 6 عريض + 3 أدوات | — |
| تبويبات داخل الشاشات | 22 (موارد) + 10 (ملفّ الطفل) + 4 (الفواتير) + 3 (الصلاحيات) + 5 (الفريق) + 3 (سجلّ التشغيل) = **47** | 2 (المواعيد) + 2 (التقارير) = **4** | 51 |
| مكوّنات شاشة مميّزة | 18 (اثنان منها محرّكان عامّان يخدمان 13 مسارًا) | 15 + 1 مشترك | — |
| حوارات (modals) | 8 | 3 | 11 |
| أفعال بنداء API | 15 في `day-spec` + ~45 مخصّصة | ~10 | — |
| نقاط API يبلغها المستخدم | ~85 | ~40 | من 295 مسارًا في الخادم |

**ما يقوله الرقم:** الكونسول عنده **22 مدخل قائمة لطبقة واحدة** بلا تجميع، و**47 تبويبًا** خلفها — أي أن ثلثي الشاشات مخفيّ تحت تبويبات لا تظهر في القائمة، بينما القائمة نفسها طويلة. البوّابة عكس ذلك: 5 تبويبات على الهاتف تُخفي **6 شاشات** لا يصل إليها إلّا برابط داخل صفحة.

---

## ١ · كونسول المركز — `web/ops`

### ١.١ · جدول الجرد

الأعمدة: **Screen** (الاسم على الشاشة) · **Route** · **Role** (الصلاحية على المسار — ليست الدور؛ الأدوار تُشتقّ من مصفوفة `db/seed/0002_rbac.sql`: A = مدير المركز، R = استقبال، T = أخصائي) · **Business Purpose** · **Main Entity** · **Actions** (ما يستطيع المستخدم فعله ← نقطة الـAPI) · **Statuses** (ما يُعرض أو يُفلتر) · **Related Screens** (روابط الدخول والخروج) · **Problem** (التصنيف: أساسية؟ مكرّرة؟ تُدمج؟ حالة لا شاشة؟ مهمّة لا شاشة؟ فلتر؟ تبويب؟ الاسم واضح؟).

| # | Screen | Route | Role (permission) | Business Purpose | Main Entity | Actions | Statuses | Related Screens | Problem |
|---|---|---|---|---|---|---|---|---|---|
| C1 | دخول الموظفين | `/login` | ضيف | دخول باسم مستخدم وكلمة مرور + استرداد رمز إعداد كلمة المرور | user session | `POST /auth/staff/login` · `POST /auth/password-setup` | — | → `/dashboard` | **أساسية.** واضحة. |
| C2 | صندوق الوارد | `/inbox` | `PORTAL.VIEW` (الجميع) | سجلّ إشعارات **الشخص** (لا المركز): ما حدث ويخصّك | notification | تعليم مقروء `POST /notifications/{id}/read` · فتح الهدف (تنقّل) · فلتر «غير المقروء فقط» · تحديث | — (مقروء/غير مقروء) | ← القائمة · → `/children/{id}` · `/reports` · `/requests` · `/appointments` · **`/invoices` (مسار غير موجود → يسقط على `/dashboard`)** | **اسم مضلِّل.** هو **Notifications** لا **Task Inbox** — الكود نفسه يقول «سجلّ يكبر ولا ينكمش، وليس لوحة». لا يحوي «ما يحتاج إجراءً». رابط الفاتورة ميّت. **يُعاد تسميته «الإشعارات» ويُبنى «المهام» مكانه.** |
| C3 | لوحة التحكم | `/dashboard` | `PORTAL.VIEW` | أوّل شاشة: 8 بطاقات عدّ · لوحة «يومك» للأخصائي · حلقة جدول اليوم · الغرف · التنبيهات · مؤشّرات سفلية | — (مجمّع) | فتح كل بطاقة بفلتر حالتها (`?status=`) · بدء جلسة من لوحة «يومك» `POST /appointments/{id}/session` · تحديث | مواعيد اليوم · حضروا الآن · جلسات جارية · التحاق جديد · طلبات جديدة · تقارير مسودّة · فواتير غير مسدّدة · الأطفال | → 7 شاشات بفلتر · `/my-day` · `/rooms` · `/satisfaction` · `/billing` | **أساسية.** لكن لوحة «التنبيهات والمتابعة» فيها هي **البذرة الوحيدة لصندوق مهامّ** — 4 بطاقات `wantsAction` (التحاق جديد، طلبات جديدة، تقارير مسودّة، فواتير غير مسدّدة) وهي عدّ لا قائمة. بطاقة الغرف والتنبيهات «بلا قراءة خلفها» (`04-app-notes` N-102). |
| C4 | الأطفال | `/children` | `CHILD.VIEW_ALL` (A R T) | قائمة الأطفال **وأولياء الأمور** (تبويبان) | child · guardian | إضافة/تعديل/أرشفة عبر CRUD `/{res}` · بحث · تبويب أولياء الأمور: master-detail مخصّص (أبناء الوليّ `GET /children?guardian_id=`) | child: ACTIVE/GRADUATED/WITHDRAWN (وINACTIVE في القاعدة **بلا تسمية** في الواجهة) | → `/children/{id}` | **اسم ناقص:** المسار اسمه «الأطفال» ويحمل أولياء الأمور تبويبًا أوّل. وليّ الأمر **لا مسار له ولا شاشة تفصيل** — تفصيله لوحة مضمَّنة داخل تبويب. → يُفكّ إلى «أولياء الأمور» و«المستفيدون» تحت «العملاء». |
| C5 | ملفّ الطفل | `/children/:childId` | `CHILD.VIEW_ALL` | الملفّ الكامل: رأس + 3 مؤشّرات مالية + نظرة عامّة + 9 تبويبات | child | **للقراءة بقصد** إلّا اثنين: نشر ملاحظة `POST /notes/{id}/publish` · تبديل موافقة البثّ `POST/DELETE /guardians/{gid}/consent` · «إنشاء تقرير» → المحرّر | appointment · session · plan · report · package · invoice · note.visibility | ← `/children` · القائمة · الإشعارات · → `/children/{id}/card` · `/children/{id}/reports/new` | **أساسية — وهي الـDetail Page الوحيدة الحقيقية في الكونسول.** المشكلة أنها بلا **CTA أساسي** ولا أفعال (حجز موعد، فاتورة، إسناد أخصائي، بيع باقة كلّها على شاشات أخرى)، فالاستقبال يقفز 3 شاشات لخدمة أسرة على الهاتف. تبويب `activity-log` **فخّ تسمية** (الالتزام بالبرنامج المنزلي، لا تاريخ الحالة). لا تبويب «الخطّ الزمني» (`v_case_timeline` مبنيّ بلا مسار، `HBH-045`). |
| C6 | كرت هويّة الطفل | `/children/:childId/card` | `CHILD.VIEW_ALL` | بطاقة مطبوعة (وجهان) | child | طباعة واحدة / ورقة A4 · `GET /children/{id}/photo` | — | ← `/children/{id}` | **أساسية.** هي **ACTION** (طباعة) بمعاينة، لا شاشة تصفّح. تبقى مسارًا لأن الطباعة تحتاج صفحة كاملة، لكنها لا تدخل القائمة. |
| C7 | محرّر التقرير | `/children/:childId/reports/new` · `/:reportId` | `REPORT.WRITE` (A T) | كتابة تقرير تقدّم، حفظ آلي، معاينة، نشر | progress report | `POST /reports` · `PATCH /reports/{id}` (نسخة متوقَّعة، `REPORT_CHANGED`) · `POST /reports/{id}/publish` | DRAFT / PUBLISHED | ← `/children/{id}` · `/reports` | **أساسية.** واضحة. ملاحظة: يُفتح من الطفل لا من قائمة التقارير (القائمة تنشر فقط). |
| C8 | الأخصائيون | `/therapists` | `STAFF.MANAGE` (A) | 3 تبويبات: الأخصائيون · ساعات العمل · **إسناد الحالات** (caseload) | therapist | CRUD على الثلاثة · صفّ الأخصائي → محرّر ملفّه | ACTIVE / ON_LEAVE / RESIGNED | → `/therapists/{id}/profile` | **إسناد الحالات** هنا CRUD عامّ (ثلاثة `ref` رقمية) — وهو **مهمّة إدارية** («عيّن أخصائيًا لهذا الطفل») تُتّخذ من ملفّ الطفل لا من جدول الأخصائيين. الأخصائي **لا يستطيع فتح هذه الشاشة** ليرى ساعاته (الصلاحية `STAFF.MANAGE`). |
| C9 | ملفّ الأخصائي | `/therapists/:therapistId/profile` | **بلا حارس** (سؤال عن الصفّ) | الملفّ العامّ: نبذة، لغات، شهادات، **موافقة النشر**، نشر | therapist profile | `PATCH /therapists/{id}/profile` · لغات · شهادات · `POST/DELETE …/consent` (الذات فقط) · `POST …/publish` | profile_status DRAFT / PUBLISHED / WITHDRAWN | ← `/therapists` · **لا مدخل للأخصائي نفسه في القائمة** | **Detail Page** صحيحة. لكن الأخصائي يصل إليها **بالرابط فقط** — لا «ملفّي» في قائمته. |
| C10 | خدمات الأخصائيين | `/therapist-services` | `STAFF.MANAGE` | مصفوفة أخصائي × خدمة (بدونها لا حجز: `THERAPIST_SERVICE_MISMATCH`) | therapist_services | خلية = زرّ `POST/DELETE /therapists/{t}/services/{s}` | — | القائمة فقط | **TAB لا PAGE:** هي تبويب رابع طبيعي في «الأخصائيون». صارت مسارًا مستقلًّا لأن `navKey` كان يُضيء البند الخطأ (`HBH-047`) — علاج عرض لا قرار هيكلي. |
| C11 | الغرف والكاميرات | `/rooms` | `CATALOG.MANAGE` (A) | تبويبان: الغرف · الكاميرات + عرض كروت بجلسة جارية | room · camera | CRUD · كرت الغرفة → البثّ | camera: ONLINE/OFFLINE/FAULT/DISABLED | → `/sessions/{id}/live` | **إعداد** (Settings) لا تشغيل. واضحة. |
| C12 | الخطط العلاجية | `/plans` | `PLAN.MANAGE` (A T) | 4 تبويبات: الخطط · الأهداف · القياسات · البرنامج المنزلي | treatment_plan | CRUD (الحالة **لا تُحدَّث** من هنا — آلة حالة) | plan DRAFT/ACTIVE/COMPLETED/CANCELLED · goal OPEN/MET/DROPPED | القائمة فقط | **شاشة مفهرسة بالكيان لا بالطفل:** أربعة منتقيات رقمية متتالية (`BL-32`). الخطّة **تخصّ طفلًا** — مكانها الطبيعي تبويب «الخطّة» في ملفّ الطفل، مع الأهداف والقياسات تحتها. **الاعتماد** (`approved_by`) لا زرّ له (`LC-09`). |
| C13 | الخدمات والباقات | `/catalog` | `CATALOG.MANAGE` | 4 تبويبات: الخدمات · الباقات · مكتبة الأنشطة · **استبيانات الرضا** | service · package · activity · nps_survey | CRUD | — | القائمة فقط | **إعداد.** الاستبيانات هنا **وإجاباتها في `/satisfaction`** — كيان واحد على شاشتين بصلاحيتين. |
| C14 | رضا الأسر | `/satisfaction` | `CATALOG.MANAGE` (**القاعدة تسأل `NPS.MANAGE`** — C-13) | نتائج الاستبيانات: مؤشّرات + رسم + جدول | nps_response | تحديث | — | ← لوحة التحكم | **REPORT** لا PAGE. تُدمج مع استبياناتها في شاشة واحدة «رضا الأسر» (تبويبان: الاستبيانات · النتائج). الحارس يسمّي صلاحية غير التي تفحصها القاعدة. |
| C15 | الموقع التعريفي | `/site` | `SITE.EDIT` (A) | 7 تبويبات لمحتوى الموقع العامّ | site_* | CRUD · النشر يحتاج `SITE.PUBLISH` (يرفضه الخادم) | DRAFT / PUBLISHED | → `/site/team` | **إعداد.** واضحة. |
| C16 | فريق العمل | `/site/team` | `SITE.EDIT` | master-detail لأعضاء فريق الموقع (5 تبويبات) | site_team | CRUD + رفع وسائط `POST /site-media` + موافقة النشر | DRAFT / PUBLISHED | ← `/site` | **TAB لا PAGE:** تبويب ثامن في «الموقع». مسار مستقلّ ومدخل قائمة مستقلّ لمحتوى موقع. ثلاث `ResourceSpec` معلَنة له وغير موجَّهة. |
| C17 | المواعيد | `/appointments` | `APPOINTMENT.BOOK` (A R) | يوميّة المركز: جدول/تقويم أسبوعي · فلاتر أخصائي/غرفة/خدمة/يوم/حالة · لوحة متابعة (بانتظار التأكيد · تداخلات) | appointment | حجز (تحقّق `POST /appointments/validate` ثم `POST /appointments`) · تغيير حالة `PATCH …/status` · بدء جلسة | BOOKED / CONFIRMED / CHECKED_IN / COMPLETED / CANCELLED / NO_SHOW | ← لوحة التحكم · الإشعارات · → `/sessions` | **أساسية — أقوى شاشة في النظام.** لوحة «متابعة مواعيد اليوم» فيها هي **ثاني بذرة لصندوق مهامّ** (بانتظار التأكيد = مهمّة). لا تفصيل للموعد ولا تاريخ حالاته (`appointment_status_history` موجود بلا قارئ). |
| C18 | يومي | `/my-day` | `SESSION.START` (A T) | **نفس شاشة المواعيد** بفلتر `mine=1` وصلاحية مسار مختلفة — كي يصل الأخصائي لزرّ «بدء الجلسة» | appointment | بدء الجلسة فقط (بقيّة الأفعال مخفيّة بصلاحياتها) | نفس الحالات | ← لوحة التحكم | **FILTER صار PAGE.** مبرَّر ومكتوب (الصلاحية على المسار كانت الخطأ)، لكنه من جهة المستخدم بند قائمة ثانٍ لنفس الشيء. الهدف: «المواعيد» ببند فرعي «مواعيدي» (فلتر افتراضي للأخصائي)، وحارس المسار `APPOINTMENT.BOOK` **أو** `SESSION.START`. المدير/الاستقبال يفتحها فيرى «لا ملفّ أخصائي». |
| C19 | الجلسات | `/sessions` | `SESSION.START` | جلسات اليوم: مشاهدة · ملاحظة · إغلاق | therapy_session | مشاهدة → البثّ · ملاحظة `PUT /sessions/{id}/note` · إغلاق `PATCH /sessions/{id}/close` | IN_PROGRESS / COMPLETED / ABORTED | → `/sessions/{id}/live` | **أساسية.** الأخصائي **يبدأ** من «يومي» و**يغلق** من «الجلسات» — عمل واحد على شاشتين. الملاحظة **بلا نشر** من هنا (النشر في ملفّ الطفل). |
| C20 | البثّ المباشر | `/sessions/:sessionId/live` | `LIVE.VIEW` (A T) | مشاهدة جلسة جارية + «لحظة مهمّة» كملاحظة موقوتة | session | `POST /sessions/{id}/stream` · `PUT …/note` | — | ← `/sessions` · `/rooms` | **أساسية.** هي **حالة** (IN_PROGRESS) بفعل (شاهد) — تبقى مسارًا لأنها ملء الشاشة. |
| C21 | التقارير | `/reports` | `REPORT.VIEW` (A T) | دفتر التقارير بنافذة من/إلى + فلتر حالة + نشر + تصدير CSV | progress_report | نشر `POST /reports/{id}/publish` | DRAFT / PUBLISHED | ← لوحة التحكم (`?status=DRAFT`) | **أساسية.** لكنها **لا تفتح** التقرير — التحرير من الطفل فقط. صفّ التقرير ينبغي أن يربط بالمحرّر. |
| C22 | الفواتير والمدفوعات | `/billing` | `BILLING.VIEW` (A R) | 4 تبويبات: الفواتير (DayScreen + ملخّص + عدّادات حالة) · المدفوعات · الباقات والأسعار · أرصدة الجلسات (دفتر) + CSV | invoice · payment · package | فاتورة جديدة · بيع باقة · إضافة سطر · إصدار · دفعة — كلّها `BILLING.MANAGE` (A فقط) | DRAFT/ISSUED/PARTIALLY_PAID/PAID/CANCELLED · package ACTIVE/EXHAUSTED/EXPIRED/CANCELLED | ← لوحة التحكم | **أساسية.** الاستقبال يرى ولا يقبض (`OQ-13` مفتوح). **لا تفصيل للفاتورة** (سطورها ودفعاتها في حوار). حذف سطر موجود في الـAPI **ولا شاشة تناديه**. تبويب «الباقات والأسعار» = الكتالوج نفسه من زاوية ثانية. |
| C23 | طلبات أولياء الأمور | `/requests` | `REQUEST.MANAGE` (A R) | دفتر طلبات الأسر (تغيير/إلغاء موعد، مكالمة) + قرار | parent_request | قرار `PATCH /requests/{id}` (ACCEPTED/REJECTED + ملاحظة) | NEW / ACCEPTED / REJECTED · kind RESCHEDULE/CANCEL/CALLBACK | ← لوحة التحكم (`?status=NEW`) · الإشعارات | **أساسية — وطلب `NEW` هو مهمّة بذاته.** قبول «تغيير موعد» **لا يغيّر الموعد** (يحتاج حجزًا مستقلًّا من شاشة أخرى) — عمل واحد على شاشتين بلا رابط. |
| C24 | المحادثات | `/communications` | `REQUEST.MANAGE` | رسائل داخل النظام مع الأسر + إرسال جماعي + قوالب | family_message | `GET /family-contacts` · `GET/POST /family-messages/{gid}` · قراءة | — (غير مقروء) | القائمة فقط | **أساسية.** نفس الأيقونة ونفس الصلاحية مع «الطلبات» — بندان متجاوران يبدوان واحدًا. مكوّن مشترك **مثبَّت أيضًا في بوّابة الأسرة** (P16). كلّه عربي مضمَّن بلا ترجمة. |
| C25 | طلبات الالتحاق | `/enrolments` | `ENROLMENT.MANAGE` (A R) | طابور الأسر الجديدة: جدول أو **لوحة مراحل** (kanban بالحالة) + أرشفة | enrolment_application | تغيير حالة `PATCH /enrolments/{id}` · **تحويل** `POST …/convert` (يُنشئ وليّ الأمر والطفل والحساب) | NEW / CONTACTED / ASSESSMENT_BOOKED / ENROLLED / REJECTED / DUPLICATE | ← لوحة التحكم (`?status=NEW`) | **أساسية — والحالة `NEW` مهمّة.** **لا شاشة تفصيل للطلب**: كل شيء في صفّ وحوار. «حجز التقييم» (الانتقال إلى `ASSESSMENT_BOOKED`) يُختار من قائمة **بلا حجز موعد فعلي** — الحجز على شاشة أخرى. لوحة المراحل صحيحة الاتجاه (الحالات فلاتر/أعمدة لا شاشات). |
| C26 | الصلاحيات والشاشات | `/access` | **`PORTAL.VIEW`** (الجميع) | 3 تبويبات: الأشخاص (إنشاء مستخدم، أدوار، حالة، رمز كلمة مرور، **بيانات شخصية ومستندات**) · الأدوار (مصفوفة الصلاحيات) · الشاشات (أيّ صلاحية لأيّ شاشة) | user · role · staff_profile | `POST/PATCH/DELETE /users` · `PUT /users/{id}/roles` · `PUT /roles/{code}/permissions` · مستندات وصورة | user ACTIVE / SUSPENDED / LOCKED | القائمة فقط | **اسم لا يقول ما تفعل:** هي **إدارة المستخدمين** وبيانات الموظّفين، واسمها «الصلاحيات والشاشات» وحارسها صلاحية الجميع (`OQ-19`). يُفكّ إلى «المستخدمون والأدوار» (`USER.MANAGE`) + «ملفّات الموظّفين» (`STAFF.PII`) + تبويب «الشاشات» يبقى أداة تشخيص. |
| C27 | سجلّ التشغيل | `/ops-log` | `OPS.VIEW` (A) | صحّة الخدمة · الأخطاء · نشاط المستخدمين | request_log | تبويب · تحديث | — | القائمة فقط | **REPORT** تقني. مكانه تحت «الإعدادات/النظام». |
| C28 | الإعدادات | `/settings` | `CATALOG.MANAGE` (**القاعدة تسأل `SETTINGS.MANAGE`** — C-13) | صفّ المركز + بارامترات النظام | center · sys_param | `PATCH /settings/center` · `PATCH/DELETE /settings/params/{code}` | — | القائمة فقط | **أساسية.** الحارس يسمّي صلاحية غير التي تفحصها القاعدة. تُصبح مظلّة لكل ما هو «إعداد» (الكتالوج، الغرف، الموقع، الاستبيانات، النظام). |
| C29 | الرفض | `/denied` | — | «لا تسمح صلاحيتك» | — | → `/dashboard` | — | ← أيّ حارس | خدمية. لا تعرض `?need=CODE` رغم أنه يصلها. |
| — | *(محوَّل)* | `/` · `**` | — | → `/dashboard` | | | | | |

### ١.٢ · ما تولّده المحرّكات — ليس شاشات مستقلّة

- **`ResourceScreen`** (6 مسارات · 22 تبويبًا): كل تبويب = `ResourceSpec` (قائمة + بحث + حوار إنشاء/تعديل + أرشفة/استرجاع). القاعدة المكتوبة في المشروع: **«مورد جديد = صفّ Spec، لا شاشة»** — وأيّ اقتراح شاشة في هذا التدقيق يمرّ بهذا السؤال أوّلًا.
- **`DayScreen`** (7 مسارات · 6 `DaySpec`): قراءات مفهرسة بالمركز واليوم؛ الأفعال حوارات؛ الحالة **فلتر `?status=`** لا شاشة — وهذا صحيح ويُحافَظ عليه. لكن المحرّك (1472 سطرًا) نما فيه 6 استثناءات باسم المورد (التقويم، لوحة المراحل، لوحة المتابعة، عدّادات الفواتير، CSV، تبويبات الفوترة).

---

## ٢ · بوّابة وليّ الأمر — `web/portal`

**قاعدة البوّابة:** لا معرّف طفل في أيّ مسار؛ الطفل المختار في `ChildContextService`. الخادم هو الذي يقرّر ما يُرى.

| # | Screen | Route | Role | Business Purpose | Main Entity | Actions | Statuses | Related Screens | Problem |
|---|---|---|---|---|---|---|---|---|---|
| P1 | بوابة ولي الأمر | `/login` | ضيف | إدخال الجوال → رمز | session | `POST /auth/otp/request` (`SENT`/`NOT_REGISTERED`/`ENROLMENT_PENDING`) | — | → `/login/otp` · `/apply` | **أساسية.** واضحة. |
| P2 | أدخل رمز التحقّق | `/login/otp` | ضيف | 6 خانات، إرسال تلقائي، إعادة إرسال | session | `POST /auth/otp/verify` | wrong/expired/locked/… | → `/welcome` | **MODAL** فعلًا (`<dialog>` فوق شاشة الدخول) له مسار. سليم. |
| P3 | طلب التحاق | `/apply` | **بلا حارس** (عامّ) | معالج 4 خطوات (~25 حقلًا) → طلب | enrolment_application | `POST /enrolments` (الكتابة المجهولة الوحيدة) · مسودّة محلّية 7 أيام · «طلب لطفل آخر» | — | ← `/login` | **أساسية.** الحقول الإضافية للمعالج **تُسطَّح نصًّا** في عمودين. النصوص عربية مضمَّنة خارج الترجمة. تاريخ الميلاد `<input type=date>` رغم وجود منتقي الأجزاء. خطوة الرمز (`OD-01`) **لم تُبنَ بعد** (`HBH-070`). |
| P4 | أهلًا بك | `/welcome` | مصادَق | **منتقي الطفل** + «ما يحتاج انتباهك» + خروج | child | اختيار طفل → `/home` · صفوف انتباه (INVOICE/ACTIVITY فقط تُنتج) | — | → `/home` · `/billing` · `/requests` · `/activities` | **SELECTOR صار PAGE** خارج الغلاف. لأسرة بطفل واحد خطوة زائدة كل دخول. تُدمج في رأس الغلاف (مبدّل طفل) وتبقى صفحة الانتباه في الرئيسية. |
| P5 | الرئيسية | `/home` | + طفل مختار | لوحة الطفل: الجلسة القادمة · البثّ · المتابعة · نشاط اليوم · 3 مواعيد · الرصيد · اختصارات | child | «طلب تغيير الموعد» → `/requests` · بثّ · استشارة | — | → 8 شاشات | **أساسية.** واضحة. |
| P6 | المواعيد | `/schedule` | + طفل | تبويبان القادمة/السابقة (نقطة واحدة تُقسم محلّيًّا) | appointment | **لا إلغاء ولا تغيير** — «طلب تغيير أو إلغاء» → `/requests` · صفّ ONLINE → `/consultation/{id}` · IN_PROGRESS → `/live` | BOOKED/CONFIRMED/IN_PROGRESS/COMPLETED/CANCELLED/NO_SHOW (**`CHECKED_IN` غائبة من تعداد البوّابة**) | → `/requests` · `/live` · `/consultation` · `/therapists/{id}` | **أساسية.** الفعل «اطلب تغييرًا» يُغادر إلى شاشة أخرى بلا ربط الموعد (الطلب يُقيَّد على **أوّل طفل** دائمًا). |
| P7 | استشارة أونلاين | `/consultation/:appointmentId` | مصادَق | الدخول من الباب إلى غرفة Jitsi + عدّاد + 8 حالات رفض | appointment (ONLINE) | `POST /appointments/{id}/consultation` | door-closed · not-confirmed (**«لم تُسدَّد» → `/billing` حيث لا سبيل للدفع**) · … | ← `/schedule` · `/home` | **ACTION** («ادخل») بمسار — مبرَّر (ملء الشاشة). حالة «غير مسدَّدة» تُحيل إلى طريق مسدود حتى تُبنى `FE-07`. |
| P8 | التقدّم | `/progress` | + طفل | الخطّة الفعّالة وأهدافها + آخر تقرير | plan · goal | — | — | → `/reports` | **أساسية.** الرسم البياني **لا يُرسم أبدًا** (لا نقطة للسلسلة). تُدمج مع «التقارير» في «متابعة طفلي» بتبويبات (التقدّم · التقارير · ملاحظات الجلسات). |
| P9 | البرنامج المنزلي | `/activities` | + طفل | مهامّ الأسبوع + حلقة الالتزام | child_activity | تعليم منجَز `POST …/log` (**إلغاء التعليم لا يُكتب** — يبدو ناجحًا ويعود) | — | — | **أساسية.** إحدى كتابتَي الأسرة الوحيدتين. |
| P10 | بثّ مباشر | `/live` | + طفل | مشاهدة الجلسة الجارية | session | `POST /sessions/{id}/stream` · «لحظة مهمّة» (**يفشل دائمًا 403 محلّيًّا**) | no-session · consent → `/profile` · … | ← `/home` · `/schedule` | **STATUS** (جلسة جارية) صار **PAGE** — مبرَّر لملء الشاشة، لكن لا عنصر فيديو فعلي في الكود اليوم. |
| P11 | التقارير والملاحظات | `/reports` | + طفل | تبويبان: التقارير · ملاحظات الجلسات | report · note | فتح تقرير → `/reports/{id}` (**صفوف الملاحظات لا تُفتح**) | — | → `/reports/{id}` | تُدمج في «متابعة طفلي». غير مرئية على شريط الهاتف. |
| P12 | التقرير | `/reports/:reportId` | + طفل | تقرير واحد: ملخّص + لقطة الأهداف | report | — (لا تنزيل/طباعة) | — | ← `/reports` | **DETAIL** صحيحة. |
| P13 | الفواتير والباقات | `/billing` | مصادَق (على مستوى الأسرة) | المستحقّ · الباقات · الفواتير | invoice · package | «طرق الدفع» = **toast** «سيتواصل معك الاستقبال» | DUE/PAID/PARTIAL/VOID (**مفردات مختلفة عن القاعدة**: ISSUED/PARTIALLY_PAID/CANCELLED) | ← `/home` · `/consultation` | **أساسية.** لا دفع، لا إيصال، لا تفصيل فاتورة (كلّها مخطَّطة `FE-07`, `FE-P2`). غير مرئية على شريط الهاتف. |
| P14 | طلباتي | `/requests` | مصادَق | 3 أنواع طلب (نصّ حرّ) + قائمة الطلبات | parent_request | `POST /children/{children[0]}/requests` · `?kind=` | SUBMITTED/UNDER_REVIEW/ACCEPTED/DECLINED (**القاعدة: NEW/ACCEPTED/REJECTED** — `UNDER_REVIEW` و`SUBMITTED` لا مصدر لهما) | ← `/home` · `/schedule` · `/profile` · → `/communications` (**`<a href>` خام = إعادة تحميل**) | **أساسية.** الطلب لا يعرف الطفل ولا الموعد. لا سحب للطلب. |
| P15 | الإشعارات | `/notifications` | مصادَق | سجلّ الإشعارات + فتح الهدف | notification | `POST /notifications/{id}/read` | مقروء/غير | ← الجرس (**العريض فقط — لا مدخل على الهاتف**) | صحيحة كـNotifications. غير قابلة للوصول على الهاتف إلّا برابط داخلي. |
| P16 | المحادثات | `/communications` | مصادَق | **مكوّن الموظّفين المشترك** داخل بوّابة الأسرة: بحث في الأسر، إرسال جماعي (محجوب بـ`can_manage`)، قوالب | family_message | `GET /family-contacts` … | — | ← `/requests` · `/profile` | **خطأ منتج:** شاشة استقبال مثبَّتة في بوّابة أسرة. الأسرة تحتاج **محادثة واحدة** مع المركز، لا قائمة أسر. الخادم يحمي البيانات (`can_manage=false`)، لكن الشاشة تعرض هيكلًا ليس لها. |
| P17 | ملفّ الأخصائي | `/therapists/:therapistId` | مصادَق | قراءة الملفّ المنشور | therapist | — | draft → محجوب | ← صفّ الموعد | **DETAIL** سليمة. `back: true` يُمرَّر كرابط. |
| P18 | حسابي | `/profile` | مصادَق | بيانات التواصل (بريد + مدينة فقط) · بيانات المركز · أطفالي · الموافقات · روابط | guardian · consent | `PATCH /me/contact` · **تبديل الموافقات يفشل دائمًا 405 محلّيًّا** | — | → `/requests` · `/communications` · `/billing` · `/home` | **أساسية.** «الموافقات» تعرض مفتاحين بلا مصدر في السكيما (`sms_notifications`, `activity_photos`). «استكمال الملفّ» (`FE-09`) سيسكن هنا. |
| — | NPS card | (حوار جذري) | مصادَق | استبيان الرضا حين يستحقّ | nps | `POST /nps/{id}/response` · `/skip` | — | — | **MODAL** سليم. |

---

## ٣ · قراءة الجرد — إجابات الأسئلة الثمانية

| السؤال | الكونسول | البوّابة |
|---|---|---|
| **شاشات أساسية** (تبقى كصفحات) | لوحة التحكم · الأطفال (تُفكّ) · ملفّ الطفل · المواعيد · الجلسات · التقارير · الفواتير · الطلبات · المحادثات · طلبات الالتحاق · الأخصائيون · الإعدادات (+ كتالوج/غرف/موقع/استبيانات تحتها) · المستخدمون | الدخول · طلب التحاق · الرئيسية · المواعيد · متابعة طفلي (مدمجة) · البرنامج المنزلي · الفواتير · طلباتي · حسابي |
| **مكرّرة** | لا تكرار نصّي (موثَّق). **تكرار مفهومي:** `/appointments`+`/my-day` (شاشة بفلتر) · `/requests`+`/communications` (أيقونة وصلاحية واحدة) · `/catalog`(استبيانات)+`/satisfaction` · لوحة «التنبيهات» في الداشبورد + «صندوق الوارد» | `/progress`+`/reports` (متابعة واحدة) · `/requests`+`/communications` (قناتان لطلب واحد) · `/welcome`+مبدّل «تبديل» في `/home` |
| **تُدمج** | `/therapist-services` → تبويب في الأخصائيين · `/site/team` → تبويب في الموقع · `/satisfaction` + استبيانات الكتالوج → «رضا الأسر» · `/my-day` → فلتر «مواعيدي» · الخطط/الأهداف/القياسات → تبويب «الخطّة» في ملفّ الطفل (وتبقى `/plans` كقائمة عبر الأطفال للأخصائي) | `/progress`+`/reports`+ملاحظات → «متابعة طفلي» · `/welcome` → مبدّل في الرأس · `/communications` → «محادثتي مع المركز» داخل «طلباتي»/«التواصل» |
| **حالة لا شاشة** | لا حالة صارت شاشة في الكونسول — الحالات فلاتر `?status=` (صحيح). الاستثناء: `/my-day` = **فلتر** (mine) صار مسارًا | `/live` = حالة `IN_PROGRESS` صارت مسارًا (مبرَّر: ملء الشاشة) |
| **مهمّة لا شاشة** | 4 بطاقات `wantsAction` في الداشبورد + «بانتظار التأكيد» في المواعيد + «تداخلات» = **مهامّ بلا صندوق**. إسناد الحالات = مهمّة تُدار من CRUD | «ما يحتاج انتباهك» في `/welcome` = مهامّ الأسرة (فاتورة مستحقّة، نشاط اليوم) |
| **فلتر داخل شاشة أخرى** | `/my-day` · «غير المقروء» في الوارد · عدّادات حالة الفواتير (صحيحة كفلتر) | تبويبا القادمة/السابقة (صحيح) |
| **تبويب داخل شاشة تفصيل** | `/therapist-services` · `/site/team` · `/children/:id/card` (فعل) · `/plans` (يخصّ الطفل) | `/reports`, `/progress` تبويبات لشاشة واحدة |
| **الاسم غير واضح** | «صندوق الوارد» (=إشعارات) · «الأطفال» (يحمل أولياء الأمور) · «الصلاحيات والشاشات» (=المستخدمون) · «الخدمات والباقات» (يحمل الاستبيانات) · «يومي» · تبويب `activityLog` · «إسناد الحالات» تحت «الأخصائيون» | «أهلًا بك» (=اختر طفلًا) · «التقدّم» مقابل «التقارير» · «المحادثات» (شاشة موظّفين) |

**الاستنتاج الذي يحمل بقيّة التدقيق:** المشكلة ليست «حالات صارت شاشات» — المشروع تجنّب ذلك فعلًا بفلتر الحالة. المشكلة **ثلاثية**: (١) **لا صندوق مهامّ** — ما يحتاج إجراءً موزَّع على بطاقات عدّ ولوحات جزئية وصفوف؛ (٢) **قائمة مسطّحة من 22 بندًا** لا تعكس النطاقات ولا دورة العمل، وثلث الشاشات تبويبات لا يراها أحد؛ (٣) **كيانان محوريّان بلا شاشة تفصيل** (طلب الالتحاق، وليّ الأمر) وملفّ الطفل الوحيد **بلا أفعال**، فالمستخدم يقفز بين الشاشات لخدمة أسرة واحدة.

</details>
