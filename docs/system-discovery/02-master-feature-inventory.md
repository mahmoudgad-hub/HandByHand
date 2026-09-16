# 02 — MASTER FEATURE INVENTORY

**٤٤ ميزة** `F-01`…`F-44`. كل ميزة مُثبتة بموضعها في الكود.

## مفتاح «Current Status»

| الرمز | المعنى |
|---|---|
| 🟢 **LIVE** | القاعدة + المسار + الشاشة موجودة وموصولة، ومُشيت في المتصفّح أو في مجموعة قبول |
| 🟡 **PARTIAL** | موجودة وناقصة نصفًا محدَّدًا (مسار أو شاشة أو منادٍ) — النصف مذكور بالاسم |
| 🔴 **DB-ONLY** | القاعدة كاملة ومختبَرة، **ولا مسار ولا شاشة تصلها** |
| ⚫ **DORMANT** | بنية موجودة ولا قارئ ولا كاتب في أي طبقة |

## فهرس سريع

| ID | الميزة | الوحدة | الحالة |
|---|---|---|---|
| F-01 | دخول وليّ الأمر برمز OTP | Identity | 🟢 |
| F-02 | دخول الموظّف بكلمة مرور | Identity | 🟢 |
| F-03 | تهيئة كلمة المرور برابط | Identity | 🟢 |
| F-04 | تغيير كلمة المرور الذاتية | Identity | 🟢 |
| F-05 | إدارة المستخدمين والأدوار | Access | 🟢 |
| F-06 | كتابة صلاحيات الأدوار | Access | 🟢 |
| F-07 | منح حساب البوّابة للأسرة | Access | 🟡 |
| F-08 | طلب الالتحاق (عامّ) | Intake | 🟢 |
| F-09 | بتّ الطلب وتحويله إلى سجلّات | Intake | 🟢 |
| F-10 | ملفّ الطفل وكارته | Child | 🟢 |
| F-11 | صورة الطفل وموافقتها | Child | 🟢 |
| F-12 | أولياء الأمور وربطهم بالأطفال | Family | 🟢 |
| F-13 | بيانات تواصل وليّ الأمر الذاتية | Family | 🟢 |
| F-14 | الموافقات المسجَّلة | Consent | 🟡 |
| F-15 | كتالوج الخدمات والغرف والكاميرات والباقات | Catalog | 🟡 |
| F-16 | الأخصائيون · ساعاتهم · خدماتهم · لغاتهم | Staff | 🟢 |
| F-17 | ملفّ الأخصائي العامّ ونشره | Staff | 🟢 |
| F-18 | الإسناد (caseload) | Clinical | 🟡 |
| F-19 | الفتحات المتاحة والتحقّق من فتحة | Scheduling | 🟢 |
| F-20 | حجز موعد | Scheduling | 🟢 |
| F-21 | انتقالات حالة الموعد | Scheduling | 🟢 |
| F-22 | الحجز المتكرّر (كورس) | Scheduling | 🔴 |
| F-23 | قائمة الانتظار والعرض | Scheduling | 🔴 |
| F-24 | إغلاق الجدول (إجازات وحجوزات) | Scheduling | 🟡 |
| F-25 | بدء الجلسة وإغلاقها | Session | 🟢 |
| F-26 | ملاحظة الجلسة ونشرها | Clinical | 🟢 |
| F-27 | البثّ المباشر | Live | 🟢 |
| F-28 | الخطة العلاجية والأهداف | Clinical | 🟡 |
| F-29 | قياسات التقدّم | Clinical | 🟢 |
| F-30 | البرنامج المنزلي وتسجيله | Home | 🟢 |
| F-31 | التقييمات (assessments) | Clinical | 🔴 |
| F-32 | تقارير التقدّم | Clinical | 🟢 |
| F-33 | المرفقات | Clinical | 🔴 |
| F-34 | الفواتير والبنود والدفعات | Billing | 🟢 |
| F-35 | الباقات ورصيدها | Billing | 🟡 |
| F-36 | الاستشارة الأونلاين (غرفة وبوّابة) | Consultation | 🟡 |
| F-37 | الإشعارات | Comms | 🟡 |
| F-38 | رسائل الأسرة | Comms | 🟢 |
| F-39 | صندوق صادر SMS/WhatsApp | Comms | 🟢 |
| F-40 | طلبات وليّ الأمر | Requests | 🟢 |
| F-41 | استبيان الرضا (NPS) | Satisfaction | 🟢 |
| F-42 | محتوى الموقع التعريفي ونشره | Site | 🟢 |
| F-43 | إعدادات المركز وبارامتراته | Settings | 🟢 |
| F-44 | سجلّ التشغيل والتدقيق والنسخ الاحتياطي | Ops | 🟡 |

---

# الهوية والوصول

## F-01 · دخول وليّ الأمر برمز OTP

| الحقل | القيمة |
|---|---|
| **Module** | Identity |
| **Description** | وليّ الأمر يُدخل جواله؛ يُصدَر رمز ويُسلَّم عبر صندوق الصادر؛ يتحقّق فيُنشأ توكن جلسة |
| **Actors** | GUARDIAN (غير مصادَق في الخطوة الأولى) |
| **Entry Point** | `web/portal` → `/login` ثم `/login/otp` |
| **Frontend Screens** | `features/login/login.ts` · `features/otp/otp.ts` |
| **Backend APIs** | `POST /api/v1/auth/otp/request` · `POST /api/v1/auth/otp/verify` · `POST /api/v1/auth/logout` |
| **DB** | `otp_codes` · `users` · `auth_sessions` · `sms_outbox` |
| **DB Functions** | `request_otp` (٥ نسخ) · `verify_otp` (٣) · `record_otp_delivery` (٢) · `create_auth_session` · `resolve_auth_session` · `revoke_auth_session` · `canonical_mobile` |
| **Statuses** | لا آلة حالة — عمر الرمز `OTP_TTL_MINUTES` (١٥) ومحاولاته `OTP_MAX_ATTEMPTS` (٥) وفاصل إعادته `OTP_RESEND_SECONDS` (٦٠) |
| **Permissions** | لا شيء قبل الدخول؛ بعده الدور `GUARDIAN` |
| **Notifications** | قالب SMS `OTP_LOGIN` (بلا صفّ إشعار في البوّابة — رمز ليس حدثًا في تغذية أحد) |
| **Integrations** | Twilio / SMS HTTP / dev (F-39) |
| **Dependencies** | F-39 · F-43 (بارامترات) |
| **Related** | F-07 (بلا حساب لا دخول) · F-02 |
| **Status** | 🟢 LIVE |

**Business Flow — يُقرأ من هنا مباشرة:**
الجوال كما يكتبه المستخدم (`01XXXXXXXXX` أو دوليًّا) يُقيَّس بـ`canonical_mobile`
إلى `+20…` في **أوّل** الدالّة ثم يُقارَن — وهذا بالضبط ما نجا به هذا المسار حين
أُضيف مشغّل التقييس (`trg_canonical_mobile`) فسقطت مقارنات أخرى بصمت.
المسار **يسبق المصادقة**، فلا يستطيع قراءة جدول محميّ بـRLS: لذلك
`request_otp` هي `SECURITY DEFINER` وتُرجع `center_id` الذي وجدته بنفسها بدل أن
يقرأه المنادي (المهاجرة `0095`).

**قواعد مثبتة بالثمن:**
- كل مقارنة تقرّر سماحًا تُكتب `IS DISTINCT FROM` — `crypt(NULL, hash) = NULL`
  و`hash <> NULL` هي `UNKNOWN` لا `false`، وكان ذلك يعني أن **رمزًا فارغًا يُسجِّل
  الدخول** (المهاجرة `0097`).
- الدالّة **إمّا تعدّ وإمّا ترفض** — `UPDATE` ثم `RAISE` في نفس الدالّة يضيع مع
  المعاملة، أي محاولات بلا حدّ.
- `OTP_ECHO` أداة تطوير فقط، والخدمة **ترفض الإقلاع** إن كانت مضبوطة مع
  `APP_ENV != development`؛ وكذلك ترفض الإقلاع في الإنتاج بلا قناة تسليم حقيقية.

---

## F-02 · دخول الموظّف بكلمة مرور

| الحقل | القيمة |
|---|---|
| **Module** | Identity · **Actors** CENTER_ADMIN · RECEPTION · THERAPIST |
| **Entry Point** | `web/ops` → `/login` |
| **Screens** | `ops/features/login/login.ts` |
| **APIs** | `POST /api/v1/auth/staff/login` · `POST /api/v1/auth/logout` |
| **DB** | `users` · `auth_sessions` · `audit_log` |
| **Functions** | `verify_password` · `create_auth_session` · `current_user_is_staff` |
| **Statuses** | `users.status` — راجع 05 |
| **Integrations** | لا شيء |
| **Dependencies** | F-03 (لا كلمة مرور = لا دخول) · F-05 |
| **Status** | 🟢 LIVE |

**Flow:** اسم مستخدم + كلمة مرور → `verify_password` → `create_auth_session` →
توكن Bearer عمره `SESSION_TTL_MINUTES` (٤٨٠). حدّ المعدّل `AUTH_RATE_PER_MINUTE`
على IP، وكل رفض يُسجَّل `ActionDeny` في التدقيق.
**ملاحظة أمنية مثبتة:** البحث عن المستخدمين يستعمل `LIKE ... ESCAPE '\'` مع تهريب
عند الربط، لأن **كل اسم مستخدم في هذه السكيما فيه شرطة سفلية** — و`_` بلا تهريب
تعني «أي حرف»، فبحثٌ يبدو سليمًا كان يرجّع الزميلة الخطأ.

---

## F-03 · تهيئة كلمة المرور برابط · F-04 · تغيير كلمة المرور الذاتية

| الحقل | القيمة |
|---|---|
| **Module** | Identity · **Actors** CENTER_ADMIN (يُصدِر) · أي موظّف (يستهلك) |
| **Screens** | `ops/features/access/access.ts` (إصدار) · شاشة استهلاك الرابط |
| **APIs** | `POST /api/v1/users/{user_id}/password-setup` (إصدار) · `POST /api/v1/auth/password-setup` (استهلاك) · `POST /api/v1/auth/password` (تغيير ذاتي) |
| **DB** | `password_setups` · `users` |
| **Functions** | `issue_password_setup` · `redeem_password_setup` · `set_password` · `change_own_password` |
| **Statuses** | صلاحية الرابط `PASSWORD_SETUP_TTL_MINUTES` (١٤٤٠) |
| **Permissions** | `USER.MANAGE` للإصدار · لا شيء للاستهلاك (الرمز هو الاعتماد) |
| **Status** | 🟢 LIVE |

> `set_password` كانت من **ثماني دوالّ** أخذت معرّفًا خامًّا وسألت `has_permission`
> وحدها بلا فحص مركز — أي **استيلاء على حساب موظّف في مركز آخر**. أُصلحت بالترتيب
> الملزم: **اقرأ الصفّ ← موجود ← لي ← يحقّ لي ← الحالة تسمح ← اكتب**، والفحص الآلي
> في `tests/db/p00_verify.sql` يمنع عودة الصنف كلّه.

---

## F-05 · إدارة المستخدمين والأدوار · F-06 · كتابة صلاحيات الأدوار

| الحقل | القيمة |
|---|---|
| **Module** | Access · **Actors** CENTER_ADMIN |
| **Entry Point** | `web/ops` → `/access` |
| **Screens** | `ops/features/access/access.ts` (شاشة واحدة تخدم: المستخدمون · الأدوار · الصلاحيات · مستندات الموظّف · صورته) |
| **APIs** | `GET/POST /api/v1/users` · `PATCH/DELETE /api/v1/users/{id}` · `PUT /api/v1/users/{id}/roles` · `GET /api/v1/roles` · `PUT /api/v1/roles/{code}/permissions` · `GET /api/v1/permissions` · `POST/GET /api/v1/users/{id}/photo` · `POST /api/v1/users/{id}/documents` · `GET /api/v1/staff-documents/{id}/file` |
| **DB** | `users` · `roles` · `permissions` · `role_permissions` · `user_roles` · `staff_profiles` · `staff_documents` · `auth_sessions` |
| **Functions** | `create_user` · `update_user` · `archive_user` (٢) · `set_user_roles` · `set_role_permissions` · `guard_last_admin` · `trg_revoke_sessions_on_offboard` |
| **Statuses** | `users.status` (راجع 05) |
| **Permissions** | `USER.MANAGE` · و`STAFF.PII` للبيانات الشخصية · وقراءة سجلّك أنت لا تحتاج الرمز (السياسة تُدخل المالك) |
| **Status** | 🟢 LIVE |

**حرّاس مثبتون:**
- `guard_last_admin` — لا يُسمح بترك المركز بلا مدير واحد على الأقلّ.
- إسقاط `USER.MANAGE` عن **آخر** دور يملكها مرفوض في الشاشة وفي القاعدة.
- أرشفة موظّف **تُبطل جلساته** (`trg_revoke_sessions_on_offboard`, `0105`) — وإلّا
  بقي توكن من قبل الإيقاف يعمل.
- `STAFF.PII` **رمز مستقلّ وليس `USER.MANAGE`**: من يمنح الأدوار ليس بالضرورة من
  يقرأ رقم قومي زميله وعنوان بيته.

> ⚠️ **تعارض مسجَّل:** تعليق المسار في `web/ops/src/app/app.routes.ts:350` يقول
> «NOT user administration: users, roles and permissions are five tables with no
> endpoint of any kind» — والشاشة نفسها تنادي تسعة مسارات منها. راجع 18 · C-19.

---

## F-07 · منح حساب البوّابة للأسرة

| الحقل | القيمة |
|---|---|
| **Module** | Access · **Actors** CENTER_ADMIN · RECEPTION (ضمن التحويل) |
| **Entry Point** | **لا نقطة دخول مباشرة** — يحدث فقط داخل `POST /api/v1/enrolments/{id}/convert` |
| **Screens** | لا شاشة |
| **APIs** | لا مسار مستقلّ |
| **DB** | `users` · `user_roles` · `guardians.user_id` · `audit_log` |
| **Functions** | `grant_portal_access` (٣ نسخ · `0085` · `0086` · `0125`) |
| **Permissions** | تُستمدّ من `convert_enrolment` (`ENROLMENT.MANAGE`) |
| **Status** | 🟡 PARTIAL |

**Flow:** `convert_enrolment` → `grant_portal_access(guardian_id)` → ينشئ
`users` بالجوال المقيَّس، يمنح دور `GUARDIAN`، ويملأ `guardians.user_id`، ويكتب
صفّ تدقيق مختومًا بـ`current_app_user()` — أي **باسم الموظّف الذي ضغط «تحويل»**،
لا باسم «الالتحاق».

**النصف الناقص:** وليّ أمر أُنشئ من **داخل المركز** (لا من طلب التحاق) لا يمرّ
بهذه الدالّة أبدًا ولا يملك حسابًا، **ولا يوجد مسار ولا زرّ يمنحه واحدًا**.
راجع 20 · M-02 · والباكلوج `HBH-010`/`HBH-011`/`HBH-012`.

---

# الالتحاق والأسرة

## F-08 · طلب الالتحاق (عامّ · غير مصادَق)

| الحقل | القيمة |
|---|---|
| **Module** | Intake · **Actors** زائر (مجهول) |
| **Entry Point** | `site/index.html` → رابط البوّابة → `web/portal` `/apply` |
| **Screens** | `portal/features/apply/apply.ts` |
| **APIs** | `POST /api/v1/enrolments` — **المسار الوحيد غير المصادَق الذي يكتب** |
| **DB** | `enrolment_applications` وحده |
| **Functions** | `submit_enrolment` (٢) · `next_number(…,'ENROL')` · `canonical_mobile` |
| **Statuses** | يولد `NEW` — راجع 05 |
| **Permissions** | لا شيء للإرسال · `ENROLMENT.MANAGE` للقراءة |
| **Notifications** | قالب SMS `ENROLMENT_SUBMITTED` / `ENROLMENT_PENDING` |
| **Integrations** | F-39 |
| **Related** | F-09 · F-12 · F-16 |
| **Status** | 🟢 LIVE |

**أربع قواعد بُني عليها (من رأس `0018`):**
1. **الطلب ليس طفلًا.** الإرسال يكتب صفًّا في **جدول واحد** ولا شيء غيره: لا وليّ
   أمر، لا طفل، لا رابط، لا حساب. وإلّا لأمكن لأي أحد على الإنترنت أن يُدخل طفلًا
   إلى السجلّ السريري.
2. **المُرسِل لا يستعيد إلّا رقمًا مرجعيًّا.** لا مسار قراءة لمجهول، فالنقطة لا
   تصلح لسؤال «هل هذا الجوال معروف للمركز؟».
3. **حدّ معدّل، والحدّ بيانات:** `ENROLMENT_MAX_PER_MOBILE_DAY` و
   `ENROLMENT_MAX_PER_IP_HOUR` من `sys_params`.
4. **قراءتها للموظّف وليس لكلّ موظّف** — `ENROLMENT.MANAGE`. ووليّ الأمر لا يرى
   طلبه، لأن «طلبه» غير قابل للإثبات قبل وجود الحساب.

> 🔴 **درس مدفوع:** حدّ «لكل جوال» صار **صفرًا أبدًا** يوم أُضيف `trg_canonical_mobile`
> — العدّ كان `WHERE parent_mobile = p_parent_mobile` بالرقم الخام، والمشغّل يخزّن
> `+20…`. أي أن الحدّ على **بوّابة الكتابة العامّة الوحيدة** كان مطفأً بلا أثر في
> أي لوج. أُصلح في `0122`.

`0093` أضاف للنموذج نفس مفردات قائمة الانتظار (أيام الأسبوع · نطاق ساعة · نطاق
تاريخ) لأن `preferred_contact_time` كان نصًّا حرًّا يُطابقه الاستقبال باليد؛ والعمود
**بقي** لأنه يجيب سؤالًا آخر (متى نهاتفهم).

---

## F-09 · بتّ الطلب وتحويله إلى سجلّات

| الحقل | القيمة |
|---|---|
| **Module** | Intake · **Actors** RECEPTION · CENTER_ADMIN |
| **Entry Point** | `web/ops` → `/enrolments` |
| **Screens** | `ops/features/resource/resource-screen.ts` بـ`ENROLMENTS_SPEC` |
| **APIs** | `GET /api/v1/enrolments` · `GET /api/v1/enrolments/{id}` · `PATCH /api/v1/enrolments/{id}` (الحالة) · `POST /api/v1/enrolments/{id}/convert` |
| **DB** | `enrolment_applications` · `guardians` · `children` · `guardian_children` · `users` · `user_roles` · `number_series` |
| **Functions** | `convert_enrolment` (٣) · `grant_portal_access` · `trg_enrolment_status` · `legal_enrolment_transition` |
| **Statuses** | `NEW → CONTACTED → ASSESSMENT_BOOKED → ENROLLED` · و`REJECTED`/`DUPLICATE` — راجع 05 |
| **Permissions** | `ENROLMENT.MANAGE` |
| **Notifications** | قالب `ENROLMENT_ASSESSMENT` عند `ASSESSMENT_BOOKED` (`0110`) · `STAFF_ENROLMENT_NEW` **معرَّف وغير مُرسَل** (راجع 10) |
| **Status** | 🟢 LIVE |

**Flow:** الطلب يُقرأ → الاستقبال يهاتف الأسرة ويحرّك الحالة إلى `CONTACTED` →
عندها فقط يُسمح بـ`convert` → تُنشأ `guardians` + `children` + `guardian_children`
+ يُمنح حساب البوّابة (F-07) → تُوسم الحالة `ENROLLED` وتُختم
(`0026` أضاف أختام الانتقال).
**التحويل مرفوض من أي حالة غير `CONTACTED` أو `ASSESSMENT_BOOKED`** (`HB091`) —
وهذا بالضبط ما جعل ضمّ منح الحساب إليه آمنًا: إنسان قد هاتف الأسرة وحرّك الصفّ
بيده قبل أن يصل التحويل.

> ⚠️ `registration_source` / `origin_source` أُضيفا في `0129` وبُنيا بأثر رجعي —
> و`convert_enrolment` **لا تختمهما للأمام**. راجع 18 · C-03.

---

## F-10 · ملفّ الطفل وكارته · F-11 · صورة الطفل وموافقتها

| الحقل | القيمة |
|---|---|
| **Module** | Child · **Actors** RECEPTION · CENTER_ADMIN · THERAPIST · GUARDIAN (قراءة طفله) |
| **Entry Point** | `/children` → `/children/:childId` → `/children/:childId/card` · وبوّابة: `/home` |
| **Screens** | `ops/features/child/child-profile.ts` · `ops/features/child-card/child-card.ts` · `portal/features/home/home.ts` |
| **APIs** | `GET /api/v1/children` · `GET /api/v1/children/{id}` · `.../profile` · `.../guardians` · `POST/GET /api/v1/children/{id}/photo` · و CRUD `POST/PATCH/DELETE /api/v1/children[/{id}]` |
| **DB** | `children` · `guardian_children` · `attachments` (الصورة) · `consents` · `number_series` |
| **Functions** | `can_access_child` · `set_child_photo` · `trg_child_photo_needs_consent` (٢) |
| **Statuses** | `children.status` — راجع 05 |
| **Permissions** | `CHILD.VIEW_ALL` · `CHILD.CREATE` · `CHILD.EDIT` · وللصورة موافقة `PHOTO_USE` |
| **Status** | 🟢 LIVE |

**بوّابة الصورة — والقصّة التي تشرح القاعدة:** البوّابة كانت تسأل عن
`consent_type = 'PHOTO'` **ولا وجود لهذا النوع** (السكيما تحمل `PHOTO_USE`). فكانت
**بوّابة بلا مفتاح**: كل صورة تُرفض والرسالة تطلب موافقة لا تكتبها أي دالّة.
وفحص «بلا موافقة يُرفض» **مرّ أخضر** وبدا أن البوّابة تعمل. **فحصُ رفضٍ بلا فحص
قبول بعده يثبت أن الباب مغلق، لا أنه يفتح.**

`children.photo_url` حُذف على **خطوتين** (`0077` القارئ أوّلًا ثمّ `0078` العمود) —
لأن الترتيب المعكوس مرّةً جعل **كل** قراءة طفل `42703` في البوّابة والكونسول معًا.

---

## F-12 · أولياء الأمور وربطهم بالأطفال · F-13 · بيانات التواصل الذاتية

| الحقل | القيمة |
|---|---|
| **Module** | Family |
| **Entry Point** | `/guardians` (كونسول) · `/profile` (بوّابة) |
| **Screens** | `resource-screen` بـ`GUARDIANS_SPEC` · `portal/features/profile/profile.ts` |
| **APIs** | CRUD `guardians` · `GET /api/v1/children/{id}/guardians` · `GET/PATCH /api/v1/me/contact` · `GET /api/v1/family-contacts` |
| **DB** | `guardians` · `guardian_children` · `users` |
| **Functions** | `update_own_guardian_contact` (`0107`) · `trg_canonical_mobile` · قيد **وليّ أمر أساسي واحد** (`0032`) |
| **Permissions** | `GUARDIAN.MANAGE` للكونسول · ووليّ الأمر يعدّل **بياناته هو** بلا رمز |
| **Status** | 🟢 LIVE |

**قواعد:** `guardians.mobile` هو **مفتاح الدخول**، ومقيَّس إلى E.164 بمشغّل
(`0112` · `0114` · `0128`). `users.mobile` فريد (`0098`)، وتصادم جوال عند منح
حساب البوّابة يُبلَّغ برمز مستقلّ (`0126`). و**وليّ أمر أساسي واحد لكل طفل** قيد
لا عُرف.

---

## F-14 · الموافقات المسجَّلة

| الحقل | القيمة |
|---|---|
| **Module** | Consent · **Actors** RECEPTION · CENTER_ADMIN · (والأخصائي لموافقته هو) |
| **Entry Point** | `/children/:id/card` (الكونسول) · `/therapists/:id/profile` |
| **Screens** | `child-card.ts` · `therapist-profile.ts` |
| **APIs** | `POST/DELETE /api/v1/guardians/{id}/consent` · `POST/DELETE /api/v1/therapists/{id}/consent` |
| **DB** | `consents` · `consent_events` (مضاف-فقط) |
| **Functions** | `grant_consent` · `withdraw_consent` (٢) · `has_consent` · `record_therapist_consent` · `withdraw_therapist_consent` |
| **Types** | `LIVE_VIEW` · `PHOTO_USE` · `SMS_NOTIFY` · `WHATSAPP_NOTIFY` (`0111`) |
| **Permissions** | `GUARDIAN.MANAGE` · والموافقة على وسائط الفريق مختومة (`0063`) |
| **Status** | 🟡 PARTIAL |

**ما ينقص:** لا شاشة واحدة تجمع «موافقات هذه الأسرة» — كل نوع يُدار من شاشته.
و`consents`/`consent_events` **لا يقرؤهما أي مسار قراءة** في Go: البوّابة لا تُظهر
لوليّ الأمر ما وافق عليه ولا متى. راجع 20 · M-08.

> **درس مسجَّل في التجهيزات:** تجهيزة أرادت «لا موافقة هنا» فكادت تنادي
> `withdraw_consent` — وهي تكتب حدث سحب في جدول **مضاف-فقط**، فيصير السجلّ يقول إن
> الأسرة سحبت موافقتها عشرين مرة. الحالة المبدئية تُبنى بـ`UPDATE` مباشر، لا بنداء
> دالّة المنتج.

---

# الكتالوج والفريق

## F-15 · كتالوج الخدمات والغرف والكاميرات والباقات

| الحقل | القيمة |
|---|---|
| **Module** | Catalog · **Actors** CENTER_ADMIN |
| **Entry Point** | `/catalog` · `/rooms` |
| **Screens** | `resource-screen` بـ`SERVICES_SPEC` · `ROOMS_SPEC` · `CAMERAS_SPEC` · `PACKAGES_SPEC` · `ACTIVITY_LIBRARY_SPEC` |
| **APIs** | CRUD على `services` · `rooms` · `cameras` · `service-packages` · `activity-library` |
| **DB** | `services` · `rooms` · `cameras` · `service_packages` · `activity_library` |
| **Functions** | `guard_service_needs_room` · `trg_touch` · وأعلام `0118`: `needs_caseload_flg` · `creates_session_flg` |
| **Permissions** | `CATALOG.MANAGE` — و**الكاميرات تحتاجها مع `LIVE.VIEW` معًا**، فمحرّر الكتالوج لا يستطيع توجيه كاميرا إلى غرفة أخرى |
| **Status** | 🟡 PARTIAL — **بلا بذور إنتاج** |

> 🔴 **خمسة جداول تشير إلى `services` وهو بلا كتالوج حقيقي.** `SERVICE_KIND` مبذور
> بثمانية أنواع (`SPEECH` · `OT` · `ABA` · `SKILLS` · `ASSESSMENT` · `MUSIC` ·
> `SENSORY` · `ACADEMIC`) لكن **مدّة كل خدمة وسعرها محجوبان على المالك**
> (الباكلوج `HBH-016`/`HBH-017`, `BL-14`). بلا كتالوج لا يُحجز موعد ببيانات حقيقية.

**قرار مثبت (`0118`):** السلوك **لا** يُفرَّع على `services.kind_code` لأنه نصّ حرّ
بلا `CHECK` ولا `lookup`: قاعدةٌ مفروضةٌ بتهجئة. فالعلمان صريحان
(`needs_caseload_flg` · `creates_session_flg`) و`kind_code` يبقى **لافتة لشاشة**.

---

## F-16 · الأخصائيون · ساعاتهم · خدماتهم · لغاتهم · F-17 · ملفّه العامّ ونشره

| الحقل | القيمة |
|---|---|
| **Module** | Staff · **Actors** CENTER_ADMIN · والأخصائي على ملفّه هو |
| **Entry Point** | `/therapists` · `/therapist-services` · `/therapists/:id/profile` |
| **Screens** | `THERAPISTS_SPEC` · `WORKING_HOURS_SPEC` · `therapist-services.ts` · `therapist-profile.ts` |
| **APIs** | CRUD `therapists` · `working-hours` · `therapist-qualifications` · `GET/POST/DELETE /api/v1/therapists/{id}/services` · `.../languages` · `.../certificates` · `PATCH /api/v1/therapists/{id}/profile` · `POST /api/v1/therapists/{id}/publish` · `PATCH /api/v1/certificates/{id}/image` · `GET /api/v1/service-therapists` · `GET /api/v1/services/{id}/therapists` |
| **DB** | `therapists` · `therapist_working_hours` · `therapist_services` · `therapist_languages` · `therapist_certificates` · `therapist_qualifications` |
| **Functions** | `update_therapist_profile` · `publish_therapist_profile` · `can_edit_therapist` · `trg_therapist_profile_status` |
| **Statuses** | `therapists.profile_status`: `DRAFT` · `PUBLISHED` · `WITHDRAWN` (`0033`) |
| **Permissions** | `STAFF.MANAGE` · و**مسار `/therapists/:id/profile` بلا حارس صلاحية بقصد** (الموافقة يسجّلها من يملك رمزًا آخر) |
| **Status** | 🟢 LIVE |

> **تحذير تسمية مسجَّل في `0129`:** `therapists.profile_status` تعني **هل الملفّ
> منشور على الموقع** — محور مختلف تمامًا عن «كم اكتمل السجلّ». ولذلك سُمّي عمود
> `0129` `record_completeness` ولم يُسمَّ `profile_status`: **اسم واحد بمعنيين على
> جدولين فخّ يكلّف أول من يقرأ الأول ويفترض الثاني.**

---

## F-18 · الإسناد (caseload)

| الحقل | القيمة |
|---|---|
| **Module** | Clinical · **Actors** CENTER_ADMIN · RECEPTION |
| **Entry Point** | `resource-screen` بـ`CASELOAD_SPEC` |
| **APIs** | CRUD `caseload` (٦ مسارات مولَّدة) |
| **DB** | `caseload` (therapist × child × service) |
| **Functions** | لا دالّة مخصَّصة — الإنشاء عبر CRUD مباشر |
| **Permissions** | سياسات `caseload` (٤) |
| **Notifications** | `STAFF_CHILD_ASSIGNED` — **يُرسَل فعلًا** |
| **Status** | 🟡 PARTIAL |

**لماذا PARTIAL:** الإسناد **شرط لبدء الجلسة** (`start_session` ترفض بلا صفّ
caseload بـ`HB023` للخدمات التي `needs_caseload_flg`)، ومع ذلك يُنشأ بـ`POST`
عامّ على المورد بلا دالّة تحمل قواعده (هل الأخصائي يقدّم هذه الخدمة؟ هل الطفل
نشط؟). الباكلوج يسمّيها `HBH-049` (**دالّة** إسناد) و`HBH-013` (مسار فوقها).

---

# الجدولة

## F-19 · الفتحات المتاحة والتحقّق من فتحة

| الحقل | القيمة |
|---|---|
| **Module** | Scheduling · **Actors** RECEPTION · CENTER_ADMIN |
| **Entry Point** | `/appointments` |
| **Screens** | `ops/features/day/day-screen.ts` |
| **APIs** | `GET /api/v1/appointments/slots` · `POST /api/v1/appointments/validate` |
| **DB** | `therapist_working_hours` · `rooms` · `appointments` · `schedule_blocks` · `services` |
| **Functions** | `available_slots` (٢ · `0100` · `0127`) · `validate_slot` (٤) · `block_conflicts` |
| **Statuses** | — · **Permissions** `APPOINTMENT.BOOK` |
| **Status** | 🟢 LIVE |

**القرار المعماري:** `available_slots` **لا تحتوي القواعد** — تعدّ المرشّحين وتسأل
`validate_slot` عن كل واحد، وهي نفس الدالّة التي يمرّ بها الحجز.
> **نسخة ثانية من «متى تجوز جلسة» تعني جوابًا ثانيًا، والاثنان يتّفقان حتى يوم
> يغيّر أحدٌ واحدًا** — فتعرض الشاشة فتحةً يرفضها الحجز، أو تخفي فتحةً كان سيقبلها،
> والفشل الثاني غير مرئي.

> 🔴 **وكادت الميزة تُشلّ بصمت:** `available_slots` كانت تلفّ على `hbh.rooms` وترجّع
> فتحةً فقط إن كانت غرفةٌ حرّة — والاستشارة الأونلاين **لا غرفة لها**. فكانت الميزة
> كاملةً وغير قابلة للوصول: السكيما والـAPI والشاشة و**١١٥٠ فحص قبول** كلّها خضراء،
> **ولم يسأل أحد: هل يستطيع أحد إنشاء الصفّ؟** أُصلح في `0127`.

---

## F-20 · حجز موعد · F-21 · انتقالات حالته

| الحقل | القيمة |
|---|---|
| **Module** | Scheduling |
| **Entry Point** | `/appointments` (كونسول) · `/schedule` (بوّابة · قراءة) |
| **Screens** | `day-screen.ts` · `portal/features/schedule/schedule.ts` · `portal/shared/ui/appointment-row.ts` |
| **APIs** | `POST /api/v1/appointments` · `PATCH /api/v1/appointments/{id}/status` · `GET /api/v1/appointments` · `GET /api/v1/children/{id}/appointments` |
| **DB** | `appointments` · `appointment_status_history` · `rooms` · `therapists` · `services` · `meetings` |
| **Functions** | `book_appointment` (٤) · `validate_slot` · `trg_appointment_status` · `trg_appointment_history` · `legal_appointment_transition` · `trg_appointment_meeting` · `trg_notify_booked` · `trg_notify_confirmed` · `trg_notify_cancelled` |
| **Statuses** | `BOOKED → CONFIRMED → CHECKED_IN → COMPLETED` · و`CANCELLED`/`NO_SHOW` — راجع 05 |
| **Permissions** | `APPOINTMENT.BOOK` · `APPOINTMENT.CANCEL` |
| **Notifications** | `APPOINTMENT_BOOKED` · `APPOINTMENT_RESCHEDULED` · `APPOINTMENT_CANCELLED` · `APPOINTMENT_REMINDER` · `STAFF_APPOINTMENT_BOOKED` |
| **Status** | 🟢 LIVE |

**الحجز المزدوج يُمنَع بقيد استبعاد `EXCLUDE USING gist`، لا بقفل صفوف** — وثلاث
حالات سباق حقيقية في مجموعة P3 تثبته. **وهذه هي الحجّة الكاملة ضدّ جدول استشارات
منفصل:** قيود الاستبعاد تعمل **داخل جدول واحد**، وجدول ثانٍ يمنح وقت الأخصائي
مصدرين لا يستطيع المحرّك التوفيق بينهما.

`delivery_mode` (`0117`): `IN_PERSON` يحتاج غرفة · `ONLINE` **يجب ألّا** يكون له
غرفة — والاتجاه الثاني هو الذي يمنع موعدًا أونلاين يحتجز غرفة فعلية.

---

## F-22 · الحجز المتكرّر (كورس) · F-23 · قائمة الانتظار والعرض

| الحقل | القيمة |
|---|---|
| **Module** | Scheduling |
| **Entry Point** | **لا شيء** |
| **Screens** | **لا شاشة** |
| **APIs** | **لا مسار** |
| **DB** | `waiting_list` · `appointments.recurrence_*` |
| **Functions** | `book_recurring` · `cancel_recurrence` (٢) · `add_to_waiting_list` (٢) · `offer_slot` (٢) · `accept_offer` (٢) · `waiting_candidates` · `release_expired_offers` |
| **Statuses** | `WAITING → OFFERED → BOOKED` · و`CANCELLED`/`EXPIRED` · و`OFFERED → WAITING` (عرض لاغٍ يحفظ الدور) |
| **Permissions** | معرَّفة في السياسات · غير مستعملة |
| **Status** | 🔴 **DB-ONLY** |

**القاعدة كاملة ومختبَرة في `tests/db/p11_verify.sql` (١٠٠ فحص)، و`grep` على
`api/` و`web/` يرجّع صفرًا لكل السبعة.** `release_expired_offers` وحدها موصولة —
عبر `run_maintenance`. الباكلوج: `HBH-024`.

**التصميم يستحقّ الحفظ:** قائمة الانتظار **ليست صفًّا من الأسماء** — الصفّ يحمل
**النافذة** التي تستطيع الأسرة الحضور فيها (أيام · نطاق ساعة · نطاق تاريخ)،
و`waiting_candidates` تجيب السؤال الوحيد المفيد: *هذه الفتحة فُتحت الآن — من
يناسبها فعلًا؟* وهي نفس المفردات التي أخذها نموذج الالتحاق في `0093`.

---

## F-24 · إغلاق الجدول (إجازات وحجوزات)

| الحقل | القيمة |
|---|---|
| **Module** | Scheduling · **DB** `schedule_blocks` (`0010`) |
| **Functions** | `block_conflicts` — تُنادى من `validate_slot` |
| **APIs / Screens** | **لا مسار ولا شاشة** — الجدول ليس في `store.Resources()` |
| **Status** | 🟡 PARTIAL — **تُقرأ ولا تُكتب** |

الحجوزات المغلقة تُحترَم عند التحقّق من الفتحة، ولا طريق لإنشاء واحدة إلّا
`INSERT` مباشر بدور المالك. أي أن **إجازات المركز غير قابلة للإدخال من أي شاشة**.
راجع 20 · M-05.

---

# الجلسة والسجلّ السريري

## F-25 · بدء الجلسة وإغلاقها

| الحقل | القيمة |
|---|---|
| **Module** | Session · **Actors** THERAPIST · CENTER_ADMIN |
| **Entry Point** | `/my-day` · `/sessions` |
| **Screens** | `day-screen.ts` · `resource-screen` بـ`SESSIONS_SPEC` |
| **APIs** | `POST /api/v1/appointments/{id}/session` (بدء) · `PATCH /api/v1/sessions/{id}/close` · `GET /api/v1/sessions` · `GET /api/v1/children/{id}/sessions` |
| **DB** | `therapy_sessions` · `session_status_history` · `appointments` · `caseload` |
| **Functions** | `start_session` (٤) · `close_session` · `can_start_session` (`0087`) · `can_close_session` · `trg_session_status` · `trg_session_history` · `legal_session_transition` |
| **Statuses** | `IN_PROGRESS → COMPLETED` أو `→ ABORTED` — راجع 05 |
| **Permissions** | `SESSION.START` · `SESSION.COMPLETE` |
| **Status** | 🟢 LIVE |

**الجلسة تُولد عند البدء، لا قبله.** لا صفّ `therapy_sessions` قبل ضغط «ابدأ» —
راجع 17 للفرق الكامل بين الموعد والجلسة.
`start_session` ترفض ما لم يكن الموعد `CHECKED_IN`، وما لم تكن الخدمة
`creates_session_flg`، وما لم يوجد `caseload` للخدمات التي تطلبه (`HB023`).
`close_session` يُكمل الموعد أيضًا إن كان `CHECKED_IN` — **لأن الزيارة حدثت وإن لم
يكتمل العمل السريري**.

> 🔴 **درس صلاحيات كلّف:** `can_close_session` كانت تسمح لمن يملك `CHILD.VIEW_ALL`
> **و**`SESSION.COMPLETE` — ودور `THERAPIST` يملك الاثنتين، فصار **أي أخصائي يغلق
> جلسة أي أخصائي آخر**. التجاوز الإداري صار مقيَّدًا بـ`user_type = 'STAFF'`.
> **الخط: الإكلينيكي يُغلق عمله هو، والإداري يُغلق عمل أي أحد.**

> ⛔ **فجوة حرجة:** `close_session` **لا تنادي `consume_package_session`**، ولا
> مشغّل ينادها، ولا Go. أي أن **رصيد الباقة لا يُخصم أبدًا**. راجع 18 · C-01.

---

## F-26 · ملاحظة الجلسة ونشرها

| الحقل | القيمة |
|---|---|
| **Module** | Clinical · **Actors** THERAPIST (يكتب وينشر) |
| **APIs** | `PUT /api/v1/sessions/{id}/note` · `POST /api/v1/notes/{id}/publish` · `GET /api/v1/children/{id}/notes` |
| **DB** | `session_notes` |
| **Functions** | `write_session_note` (٢) · `publish_session_note` (٢) · `can_edit_session` (٢) · `check_session_edit` · `trg_note_born_internal` · `trg_note_publish_guard` |
| **Statuses** | `visibility`: تولد `INTERNAL` → `PARENT` عند النشر — راجع 05 |
| **Permissions** | `SESSION.NOTES.EDIT` للكتابة · `NOTE.PUBLISH` للنشر — **رمزان وبوّابتان** |
| **Notifications** | `NOTE_PUBLISHED` |
| **Status** | 🟢 LIVE |

**`CENTER_ADMIN` لا يملك `SESSION.NOTES.EDIT` بقصد:** الملاحظة السريرية يكتبها من
كان في الغرفة، ولا يكتبها إداري بالنيابة.
> **حقّان لهما رمزان منفصلان يحتاجان بوّابتين منفصلتين.** بوّابة واحدة تخدم
> الاثنين تعيد تعريف أيّ المنحتين تتجاهلها بصمت — وهو عيبٌ وقع فعلًا في النظام
> القديم: الاستقبال يبدأ جلسةً لا يستطيع إغلاقها إلّا الأخصائي المسنَد.

`0030` أضاف **سبب التعديل** على ملاحظة جلسة، وفرّق رفض «لا صلاحية» من رفض «ليست
جلستك» — وتجهيزة فيها أخصائية واحدة **لا تستطيع التفريق بينهما أصلًا**، فتُمرّر أي
رمز يرجّعه الكود.

---

## F-27 · البثّ المباشر

| الحقل | القيمة |
|---|---|
| **Module** | Live · **Actors** GUARDIAN (بموافقة) · THERAPIST · CENTER_ADMIN |
| **Entry Point** | بوّابة `/live` · كونسول `/sessions/:sessionId/live` |
| **Screens** | `portal/features/live/live.ts` · `ops/features/live/live-view.ts` |
| **APIs** | `POST /api/v1/sessions/{id}/stream` · `POST /api/v1/stream/close` |
| **DB** | `cameras` · `stream_tokens` · `stream_views` · `consents` |
| **Functions** | `issue_stream_token` · `resolve_stream_token` · `revoke_stream_token` · `can_view_live` · `close_session_streams` · `trg_live_flag_needs_consent` |
| **Statuses** | لا آلة حالة — عمر التوكن `STREAM_TOKEN_TTL_MIN` (١٥) |
| **Permissions** | `LIVE.VIEW` + موافقة `LIVE_VIEW` للأسرة |
| **Status** | 🟢 LIVE |

**خمس قواعد ليست تفضيلات (رأس `0009`):**
1. **مباشر فقط. ولا تسجيل أبدًا.** لا جدول تسجيلات ولا عمود احتفاظ، ومجموعة
   المعايير تفشل على أي عمود اسمه فيه `recording` أو `clip` أو `video`.
2. **القاعدة لا تحمل سرّ كاميرا** — مسار بوّابة و**مرجع** اعتماد فقط. لا RTSP ولا
   IP ولا كلمة مرور، ولا مشفَّرة: **عمود يستطيع أن يحمل واحدة يحملها في النهاية.**
3. **المتصفّح يأخذ توكنًا معتِمًا لا عنوانًا** — ٣٢ بايتًا عشوائيًّا، SHA-256 عند
   التخزين، لا يسمّي البوّابة ولا الكاميرا. **رابط لا يُخمَّن ليس وصولًا مضبوطًا.**
4. التوكن ≤ ١٥ دقيقة، ومربوط بجلسة وكاميرا ومستخدم.
5. `D-24`: **التوكن لا يلمس JavaScript** — كوكي `HttpOnly` والخدمة تُرحّل البايتات.
   `close_session_streams` و`run_maintenance` يبطلان توكنات جلسة لم تبقَ
   `IN_PROGRESS`.

**١٨ فحصًا في مجموعة البثّ**، ومنها «وليّ أمران لنفس الطفل يفرّقهما علمٌ واحد»،
و«لا توكن ولا مسار كاميرا ولا عنوان في أي ردّ».
> وفحص التسريب نفسه كاد يعمى: كان يبحث عن `"mobile":"[0-9]` ثم صارت الأرقام
> `+20…` — **وكان سيمرّ أخضر لو حُذف القناع كلّه**. النمط الصحيح يسأل ما يعنيه
> الفحص: **هل هنا قيمة أصلًا؟** (`"mobile":"[^"]`).

---

## F-28 · الخطة العلاجية والأهداف · F-29 · قياسات التقدّم

| الحقل | القيمة |
|---|---|
| **Module** | Clinical · **Actors** THERAPIST · CENTER_ADMIN |
| **Entry Point** | `/plans` · وبوّابة `/progress` |
| **Screens** | `resource-screen` بـ`PLANS_SPEC` · `GOALS_SPEC` · `MEASUREMENTS_SPEC` · `portal/features/progress/progress.ts` |
| **APIs** | CRUD `plans` · `goals` · `measurements` · `GET /api/v1/children/{id}/plans` |
| **DB** | `treatment_plans` · `plan_goals` · `goal_measurements` · العرض `v_goal_progress` |
| **Functions** | `trg_plan_status` (٣) · `legal_plan_transition` |
| **Statuses** | `DRAFT → ACTIVE → COMPLETED` · و`CANCELLED` — راجع 05 |
| **Permissions** | `PLAN.MANAGE` · `GOAL.MEASURE` |
| **Notifications** | `STAFF_PLAN_APPROVED` — **معرَّف وغير مُرسَل** |
| **Status** | 🟡 PARTIAL |

**لماذا PARTIAL:**
1. `0088` أضاف **قاعدة اعتماد الخطة** (`HB210`: لا تُنشَّط خطة بلا هوية تُنسَب
   إليها) و`0090` **أسقطها** لأنها رفضت انتقالًا كان يعمل قبلها. الرمز `HB210`
   **متقاعد ولا يُعاد استعماله** — والقاعدة نفسها غير مفروضة الآن. الباكلوج
   `HBH-044`.
2. ترويسة الخطة ينقصها **خمسة حقول** طلبها المالك (`HBH-040`).
3. `plan_kind` — أنواع أم تسميات؟ محجوب على المالك (`HBH-020`).

---

## F-30 · البرنامج المنزلي وتسجيله

| الحقل | القيمة |
|---|---|
| **Module** | Home · **Actors** THERAPIST (يصف) · GUARDIAN (يسجّل) |
| **Entry Point** | بوّابة `/activities` |
| **Screens** | `portal/features/activities/activities.ts` · كونسول `CHILD_ACTIVITIES_SPEC` |
| **APIs** | `GET /api/v1/children/{id}/activities` · `GET .../activity-log` · `POST /api/v1/children/{id}/activities/{child_activity_id}/log` · CRUD `child-activities` · `activity-library` |
| **DB** | `activity_library` · `child_activities` · `activity_log` · العرض `v_activity_adherence` |
| **Functions** | `log_activity` |
| **Permissions** | لا رمز لتسجيل الأسرة — السياسة تُدخل وليّ الأمر على طفله |
| **Status** | 🟢 LIVE |

**ثلاث قواعد (رأس `0007`):**
1. **الأهل يسجّلون، والإكلينيكي يصف.** `child_activities` يكتبها الأخصائي و
   `activity_log` تكتبها الأسرة. وليّ أمر يستطيع تعديل الوصفة يستطيع أن يعيد كتابة
   البرنامج بهدوء ثم يبلّغ التزامًا كاملًا به.
2. **قيدٌ فريد: مدخل واحد لنشاط واحد في يوم واحد** — بالفهرس لا بالشاشة.
3. هذان وطلبات وليّ الأمر (F-40) هما **الموضعان الوحيدان** اللذان يكتب فيهما
   وليّ أمر.

---

## F-31 · التقييمات (assessments)

| الحقل | القيمة |
|---|---|
| **Module** | Clinical |
| **Entry Point** | **لا شيء** |
| **Screens** | **لا شاشة** |
| **APIs** | **لا مسار** |
| **DB** | `assessment_instruments` · `assessment_items` · `assessments` · `assessment_item_scores` (٤ جداول) |
| **Functions** | `record_assessment` · `publish_assessment` (٢) · `trg_assessment_guard` · `trg_assessment_total` · `trg_assessment_score_guard` · `legal_assessment_transition` |
| **Statuses** | `DRAFT → COMPLETED → PUBLISHED` · والسحب `PUBLISHED → COMPLETED` — راجع 05 |
| **Permissions** | `ASSESSMENT.RECORD` · `ASSESSMENT.PUBLISH` |
| **Notifications** | `ASSESSMENT_PUBLISHED` — يُرسَل من داخل `publish_assessment` |
| **Status** | 🔴 **DB-ONLY** — الباكلوج `HBH-041` |

**أربعة قرارات (رأس `0023`):** الأداة بيانات والتقييم حدث · يولد مسودّةً ويصل
الأسرة بقصد · المنشور **مجمَّد** (الملخّص والدرجات معًا) · وحدود الدرجة تخصّ
**الأداة** فيفحصها مشغّل.

> 🔴 **وهذه الميزة هي بالضبط الحالة التي علّمت القاعدة:** `publish_assessment` —
> وهي التي **تُشعر الأسرة** — لم يكن لها مسار، وكانت **ستسلّم رسالة عن طفل مركز
> آخر** في اليوم الذي يُضاف فيه واحد. **«لا مسار يصل إليها» خاصيّةُ الموجّه لا
> الدالّة**، والموجّه يتغيّر أسرع من السكيما بكثير.

---

## F-32 · تقارير التقدّم

| الحقل | القيمة |
|---|---|
| **Module** | Clinical · **Actors** THERAPIST · CENTER_ADMIN · GUARDIAN (قراءة المنشور) |
| **Entry Point** | `/children/:id/reports/new` · `/reports` · بوّابة `/reports` |
| **Screens** | `ops/features/report-editor/report-editor.ts` · `REPORTS_SPEC` · `portal/features/reports/reports.ts` · `portal/features/report/report.ts` |
| **APIs** | `POST /api/v1/reports` · `PATCH /api/v1/reports/{id}` · `POST /api/v1/reports/{id}/publish` · `GET /api/v1/reports` · `GET /api/v1/reports/{id}` · `GET /api/v1/children/{id}/reports` |
| **DB** | `progress_reports` · `number_series` (`REPORT`) |
| **Functions** | `create_report` · `update_report` · `publish_report` (٢) · `trg_report_guard` · `trg_notify_report` |
| **Statuses** | `DRAFT → PUBLISHED` (`HB033` يرفض تعديل المنشور — **تاريخٌ قرأته أسرة**) |
| **Permissions** | `REPORT.WRITE` (للمسودّة) · `REPORT.PUBLISH` (للنشر) · `REPORT.VIEW` |
| **Notifications** | `REPORT_PUBLISHED` |
| **Status** | 🟢 LIVE |

**`REPORT.WRITE` أصغر رمز يعمل:** إعادة استعمال `REPORT.PUBLISH` للصياغة تعني أن
كل من يكتب مسودّةً ينشرها — **فتنطوي خطوتان في واحدة**. وتوسيع `PLAN.MANAGE` أو
`ASSESSMENT.RECORD` يجعل الاثنين يعنيان «كتابة سريرية»، فلا يبقى شيء يُسحَب يوم
يريد المركز من يصوغ ولا ينشر.

> 🔴 **لكن منحة `REPORT.WRITE` مكتوبة في هجرة تقرأ `hbh.roles`** — وعلى قاعدة معاد
> بناؤها تكون فارغة، فالمنحة **لا تحدث** ولا تُبلَّغ. راجع 18 · C-02.

---

## F-33 · المرفقات

| الحقل | القيمة |
|---|---|
| **Module** | Clinical · **DB** `attachments` · العرض `v_attachment_index` |
| **Functions** | `attach_file` · `publish_attachment` (٢) · `trg_attachment_audit` · `trg_attachment_born_internal` · `trg_attachment_publish_guard` |
| **APIs** | **لا مسار عامّ** — الاستعمال الوحيد الموصول هو **صورة الطفل** (F-11) |
| **Permissions** | `ATTACHMENT.UPLOAD` · `ATTACHMENT.PUBLISH` |
| **Status** | 🔴 DB-ONLY (عدا مسار الصورة) |

**ثلاث قواعد (رأس `0024`):**
1. **لا فيديو. أبدًا. وصار الآن بنيويًّا** — `CHECK` يرفض أي `mime` يبدأ بـ`video/`.
   كانت جملةً في وثيقة، فصارت قيدًا **لا علاقة له بالمساحة ولم تكن له قطّ**.
2. **مشغّل التدقيق لا ينسخ الملفّ** — `to_jsonb(NEW)` هنا يضع كل بايت داخل
   `audit_log`، مرّتين عند التعديل وبـbase64. فللمرفقات مشغّل تدقيق خاصّ يطرح
   `content`. **أي جدول يحمل `bytea` كبيرًا يحتاج نفس المعالجة.**
3. التخزين عمود لا إعادة كتابة.

**الناقص:** مرفقات طلب الالتحاق (`HBH-042`) · ومسار رفع/نشر عامّ.

---

# المال

## F-34 · الفواتير والبنود والدفعات

| الحقل | القيمة |
|---|---|
| **Module** | Billing · **Actors** CENTER_ADMIN (إدارة) · RECEPTION (قراءة) · GUARDIAN (قراءة) |
| **Entry Point** | `/billing` (كونسول) · `/billing` (بوّابة) |
| **Screens** | `ops/features/day/billing-overview.ts` · `billing-ledger.ts` · `INVOICES_SPEC` · `portal/features/billing/billing.ts` |
| **APIs** | `POST /api/v1/invoices` · `POST .../lines` · `DELETE .../lines/{line_id}` · `POST .../issue` · `POST .../payments` · `GET /api/v1/invoices[/{id}]` · `GET /api/v1/children/{id}/invoices` · `GET /api/v1/billing/summary` · `GET /api/v1/billing/ledger` |
| **DB** | `invoices` · `invoice_lines` · `payments` · `number_series` (`INVOICE`) · العرض `v_child_balance` |
| **Functions** | `create_invoice` · `add_invoice_line` · `remove_invoice_line` · `issue_invoice` (٢) · `recalc_invoice` · `trg_line_recalc` · `trg_line_guard` · `trg_payment_recalc` (٢) · `trg_payment_guard` · `trg_invoice_status` · `trg_invoice_guard` · `legal_invoice_transition` · `trg_notify_invoice` |
| **Statuses** | `DRAFT → ISSUED → PARTIALLY_PAID → PAID` · و`CANCELLED` — راجع 05 |
| **Permissions** | `BILLING.MANAGE` · `BILLING.VIEW` |
| **Notifications** | `INVOICE_ISSUED` |
| **Status** | 🟢 LIVE |

**قاعدتان مثبتتان (رأس `0008`):**
1. **الإجمالي مشتقّ، لا يُدخَل أبدًا.** `subtotal` و`tax` و`total` يكتبها مشغّل من
   البنود، و`paid_amt` من الدفعات. **لا طريق — عبر API ولا `UPDATE` مباشر — يكتب
   إجماليًّا لا يتبع الصفوف تحته.**
2. **الضريبة محايدة الدولة:** `tax_rate` و`tax_amt` وافتراضٌ من `sys_params`. لا
   ZATCA ولا حمولة فاتورة إلكترونية ولا افتراض أن النسبة شيء بعينه.

> **ملاحظة اختبار مسجَّلة:** مشغّل `BEFORE` يعمل **قبل** فحص `WITH CHECK` في RLS،
> فقاعدة العمل تُجيب أوّلًا وتحجب رفض الصلاحية تمامًا: دفعةٌ على فاتورة مسوّدة
> تُرفض `HB052` لأي أحد، والاستقبال **لا يصل إلى السياسة أصلًا**.

---

## F-35 · الباقات ورصيدها

| الحقل | القيمة |
|---|---|
| **Module** | Billing |
| **APIs** | `GET /api/v1/children/{id}/packages` · `POST /api/v1/children/{id}/packages` (بيع) · `GET /api/v1/children/{id}/balance` |
| **DB** | `service_packages` · `child_packages` · `package_ledger` (مضاف-فقط) |
| **Functions** | `sell_package` (٢) · `consume_package_session` · `expire_packages` |
| **Statuses** | `child_packages.status`: `ACTIVE` · `EXHAUSTED` · `EXPIRED` · `CANCELLED` (وآخِرتان بلا كاتب — راجع 05) |
| **Permissions** | `BILLING.MANAGE` |
| **Status** | 🟡 PARTIAL — **البيع موصول، الخصم لا** |

**القاعدة:** رصيد الباقة **لا يصير سالبًا** — `CHECK` على الصفّ وقفل صفّ في
الدالّة، وكل حركة تخلّف قيدًا **مضاف-فقط** يحمل الرصيد بعدها. أسرة تسأل «أين ذهبت
جلساتي الاثنتا عشرة» تُجاب من الدفتر لا من التخمين.

> ⛔ **وهذا الدفتر لا يُكتب فيه شيء اليوم**: `consume_package_session` **بلا منادٍ**
> في أي طبقة. راجع 18 · C-01.
> **و`consume_package_session` لا تسأل عن الدفع إطلاقًا** — الجلسة تُخصم مسدَّدةً
> كانت أو لا، وهذا مبنيّ ومختبَر على ذلك (`BL-37 ج`).
> **والدرس الذي كلّفها:** كانت تعلّم الباقة `EXPIRED` ثم **ترفع** استثناءً — فلا
> تُعلَّم أبدًا، لأن الاستثناء يفكّ المعاملة. العلاج: الدالّة التي تعدّ **ترجع
> حالة**، والتعليم نداءٌ مستقلّ (`expire_packages`) لا يرفع شيئًا.

---

# الاستشارة الأونلاين

## F-36 · الاستشارة الأونلاين (غرفة وبوّابة)

| الحقل | القيمة |
|---|---|
| **Module** | Consultation · **Actors** GUARDIAN (هو الحاضر، لا الطفل) · THERAPIST |
| **Entry Point** | بوّابة `/consultation/:appointmentId` |
| **Screens** | `portal/features/consultation/consultation.ts` |
| **APIs** | `POST /api/v1/appointments/{appointment_id}/consultation` |
| **DB** | `appointments` (`delivery_mode = 'ONLINE'`) · `meetings` · `meeting_tokens` |
| **Functions** | `authorize_meeting_entry` (٣) · `record_meeting_token` · `trg_appointment_meeting` |
| **Statuses** | يتبع حالة الموعد · وبوّابة الدخول ترفض `NOT_YET_OPEN` (`HB252`) و`NOT_CONFIRMED` (`HB253`) |
| **Permissions** | RLS + `authorize_meeting_entry` |
| **Integrations** | **Jitsi JaaS** (إنتاج · JWT بمفتاح RSA) · **Jitsi public** (تطوير فقط) |
| **Status** | 🟡 PARTIAL |

**القرار الذي سجّلته `0120` لأنه يصطدم بقاعدة:** `CLAUDE.md` يقول «لا بيانات
اعتماد في أي مكان يبلغه عميل»، ومسار البثّ يحترمه حرفيًّا. لكن **الوسائط الحيّة
ليست HTTP**: متصفّح الأسرة يتفاوض مع المزوّد مباشرةً، فلا شيء يُرحَّل. القرار
مسجَّل بأسبابه وبموافقة المالك.
**والحدّ المقابل:** `meeting.Mint` تأخذ `Grant` فقط، **ولا طريق مُصدَّر لقول «أعطني
توكنًا للغرفة X»** — ذلك سيكون بابًا ثانيًا بجوار الباب الذي عليه كل الفحوص.
وكل قرارات «من يدخل» و«متى يُفتح الباب» في `authorize_meeting_entry` بـPL/pgSQL،
وحزمة `meeting` **لا تعرف ما هو الطفل**.

**النصف الناقص:** لا شاشة كونسول للأخصائي يدخل منها الغرفة · ولا مسار لإنشاء
`consultation_requests` (الجدول غير موجود بعد) · و`ONLINE_CONSULTATION` كمصدر
تسجيل **قيمة معرَّفة بلا كاتب** (`0129`).
الوثيقة المرجعية: [`../architect/03-online-consultation.md`](../architect/03-online-consultation.md)
و [`../business-analysis/09-FEAT-online-consultation.md`](../business-analysis/09-FEAT-online-consultation.md).
الباكلوج يصنّفها **«ميزة مكلَّفة وغير مجدولة»** (2026-09-12).

---

# التواصل

## F-37 · الإشعارات

| الحقل | القيمة |
|---|---|
| **Module** | Comms |
| **Entry Point** | بوّابة `/notifications` · كونسول `/inbox` |
| **Screens** | `portal/features/notifications/notifications.ts` · `ops/features/inbox/inbox.ts` |
| **APIs** | `GET /api/v1/notifications` · `POST /api/v1/notifications/{id}/read` |
| **DB** | `notifications` |
| **Functions** | `notify_guardians` (٢) · `notify_staff` · `notify_role` · `mark_notification_read` · وثمانية مشغّلات `trg_notify_*` |
| **Kinds** | ١٦ نوعًا — **١١ مُرسَل و٥ ميّت**. راجع 10 |
| **Permissions** | السياسة: صاحب الصفّ · و`PORTAL.VIEW` للكونسول |
| **Status** | 🟡 PARTIAL |

`notifications.sms_pending_flg` هو العلم الذي يرفعه `trg_sms_from_notification`
لصندوق الصادر: **صفّ البوّابة يُكتب دائمًا، والرسالة النصّية اختيارية**.

---

## F-38 · رسائل الأسرة

| الحقل | القيمة |
|---|---|
| **Module** | Comms · **Actors** RECEPTION/CENTER_ADMIN ↔ GUARDIAN |
| **Entry Point** | `/communications` في **كلا** التطبيقين |
| **Screens** | `web/shared/src/ui/family-messages.ts` — **مكوّن واحد مشترك** |
| **APIs** | `GET /api/v1/family-messages/{guardian_id}` · `POST /api/v1/family-messages/{guardian_id}` · `POST .../read` · `GET /api/v1/family-contacts` |
| **DB** | `family_messages` · `family_message_reads` |
| **Permissions** | `REQUEST.MANAGE` للمركز · ووليّ الأمر على خيطه هو |
| **Status** | 🟢 LIVE |

**مثال جيّد على إعادة الاستعمال:** شاشة واحدة في `web/shared` تخدم السطحين، والفرق
كلّه في الصلاحية على المسار.

> ⚠️ **وأسوأ مثال على اتّساق الاصطلاح:** الهجرتان `0079` و`0080` كُتبتا بأسلوب
> مختلف تمامًا عن السكيما (بلا رأس · بلا قواعد مرقّمة · `PRIMARY KEY` مضمَّنًا لا
> `CONSTRAINT pk_*` · `uuid` حيث لا يستعمله أحد)، وبلا أعمدة تدقيق ولا حذف ناعم —
> **خرقٌ للقاعدة ٣**. وكانتا **مطبَّقتين على القاعدة ولا تسجّلان رقمهما في الدفتر**،
> ولا `IF NOT EXISTS` فيهما، فالتشغيلة التالية كانت ستُسقط `migrate` كلّه. رُقِّعت
> بـ`0081`–`0084`. الباكلوج `HBH-033`.

---

## F-39 · صندوق صادر SMS / WhatsApp

| الحقل | القيمة |
|---|---|
| **Module** | Comms · **Actors** النظام |
| **APIs** | لا مسار عامّ — العملية داخلية |
| **DB** | `sms_outbox` · `country_dial_codes` · العروض `v_sms_delivery` · `v_sms_health` |
| **Functions** | `enqueue_sms` (٢) · `claim_sms` (٣) · `record_sms_sent` · `record_sms_failed` · `reap_stuck_sms` · `assert_sms_worker` · `trg_sms_from_notification` (٢) · `trg_sms_assessment_booked` · `trg_canonical_destination` · `queue_appointment_reminders` |
| **Statuses** | `PENDING → SENDING → SENT` · أو `FAILED → DEAD` — راجع 05 |
| **Templates** | `OTP_LOGIN` · `APPOINTMENT_BOOKED` · `APPOINTMENT_REMINDER` · `ENROLMENT_SUBMITTED` · `ENROLMENT_PENDING` · `ENROLMENT_ASSESSMENT` · `ASSESSMENT_PUBLISHED` |
| **Integrations** | `SMS_PROVIDER` ∈ {twilio · http · dev} — راجع 11 |
| **Background** | `sms.Worker` في Go (فترة `SMS_WORKER_SECONDS` · دفعة `SMS_WORKER_BATCH`) + `reap_stuck_sms` في الصيانة |
| **Status** | 🟢 LIVE |

**قواعد:**
- **نصّ رمز الدخول لا يُكتب في أي مكان** — لا في الصندوق (`body_ar` يكون `NULL`
  لـOTP بقيد `ck_sms_body`) ولا في لوج ولا في الردّ خارج التطوير.
- الرقم يُخزَّن بصيغة المجال، والتحويل لصيغة المزوّد **عند حدود المزوّد في Go**
  ولا يُكتب رجوعًا: **تمثيلٌ ثانٍ لرقم هاتف في القاعدة شيءٌ ثانٍ يجب إبقاؤه متّسقًا.**
- `error_class`: `TRANSIENT` يعيد · `PERMANENT` لا · `CONFIG` يعني أن هذا النشر لا
  يستطيع الإرسال أصلًا وإعادة المحاولة ستفشل بنفس الشكل.
- `SMS_SENDING_ENABLED` مفتاح إطفاء (`0115`).
- `TWILIO_ALLOW_FREEFORM` أداة تطوير: رسالة واتساب يبدأها المركز تُرفض كنصّ حرّ
  بالخطأ `63016` خارج نافذة ٢٤ ساعة، **وكل رسالة يبدأها هذا المركز خارج واحدة** —
  فالخدمة **ترفض الإقلاع** إن كانت مضبوطة في الإنتاج.

---

## F-40 · طلبات وليّ الأمر

| الحقل | القيمة |
|---|---|
| **Module** | Requests · **Actors** GUARDIAN (يُرسل) · RECEPTION/CENTER_ADMIN (يبتّ) |
| **Entry Point** | بوّابة `/requests` · كونسول `/requests` |
| **Screens** | `portal/features/requests/requests.ts` · `REQUESTS_SPEC` |
| **APIs** | `POST /api/v1/children/{id}/requests` · `GET /api/v1/children/{id}/requests` · `GET /api/v1/requests` · `PATCH /api/v1/requests/{id}` |
| **DB** | `parent_requests` · `number_series` (`REQUEST`) |
| **Functions** | `submit_request` · `decide_request` (٢) · `trg_request_status` · `legal_request_transition` · `trg_notify_request` |
| **Kinds** | `RESCHEDULE` · `CANCEL` · `CALLBACK` |
| **Statuses** | `NEW → ACCEPTED` أو `→ REJECTED` |
| **Permissions** | `REQUEST.SUBMIT` · `REQUEST.MANAGE` |
| **Notifications** | `REQUEST_DECIDED` · `STAFF_REQUEST_NEW` **معرَّف وغير مُرسَل** |
| **Status** | 🟢 LIVE |

**«الطلب ليس فعلًا»:** إرسال «أرجو نقل الثلاثاء» **لا يحرّك موعدًا**. يُنشئ صفًّا
يبتّ فيه الاستقبال. والبوّابة تقول ذلك، **والسكيما تجعله صحيحًا**:
`parent_requests` بلا مفتاح أجنبي يستطيع نقل حجز.
> وهذا يجعل `parent_requests` **البديل المصمَّم** لـ«الأب يحجز بنفسه» (`BL-03`) —
> فإن قُرِّر أن يحجز الأب بنفسه، **سقط نصف هذه الميزة**.

> 🔴 **درس صلاحيات:** `decide_request` كانت من الدوالّ الثماني التي تأخذ معرّفًا
> خامًّا بلا فحص مركز، **وأرسلت إشعارًا بنصّ المهاجم إلى أسرة مركز آخر** — مُثبتًا
> بالاختبار لا مستنتَجًا.

---

## F-41 · استبيان الرضا (NPS)

| الحقل | القيمة |
|---|---|
| **Module** | Satisfaction |
| **Entry Point** | بطاقة في بوّابة `/home` · كونسول `/satisfaction` |
| **Screens** | `portal/features/nps/nps-card.ts` · `ops/features/satisfaction/satisfaction.ts` · `NPS_SURVEYS_SPEC` |
| **APIs** | `GET /api/v1/nps/due` · `POST /api/v1/nps/{survey_id}/response` · `POST /api/v1/nps/{survey_id}/skip` · `GET /api/v1/nps/summary` |
| **DB** | `nps_surveys` · `nps_responses` · العرض `v_nps_summary` |
| **Functions** | `nps_due` · `submit_nps` · `skip_nps` |
| **Permissions** | `NPS.MANAGE` للإدارة والتقارير |
| **Status** | 🟢 LIVE |

**قرارات (رأس `0019`):** **متى نسأل تهيئةٌ لا كود** (`trigger_kind` ∈ PERIOD/ACTION
+ `period_days` · `action_code` · `cooldown_days` + نصّا السؤالين — كلها أعمدة).
**وألّا نسأل مهمٌّ كأن نسأل** — التخطّي **يُسجَّل** لا يُنسى، وإلّا عاد السؤال في
كل تحديث للشاشة، **واستبيانٌ يُلحّ استبيانٌ لا يجيبه أحد بصدق**.
المبذور: `PARENT_SESSION` · بعد `SESSION_COMPLETED` · تهدئة ٣٠ يومًا.

> ⚠️ حارس مسار `/satisfaction` هو `CATALOG.MANAGE`، والقاعدة تطلب `NPS.MANAGE`.
> راجع 18 · C-13.

---

# التشغيل

## F-42 · محتوى الموقع التعريفي ونشره

| الحقل | القيمة |
|---|---|
| **Module** | Site · **Actors** CENTER_ADMIN |
| **Entry Point** | `/site` · `/site/team` |
| **Screens** | `ops/features/resource/resource-screen.ts` (٧ specs) · `ops/features/team/team-screen.ts` · `portrait-crop.ts` |
| **APIs** | CRUD على `site-sections` · `site-texts` · `site-faq` · `site-services` · `site-programs` · `site-reviews` · `site-contact` · `site-team` · `site-team-media` · `site-team-specialties` · `site-team-certificates` · `site-team-facts` · و`POST /api/v1/site-media` · `GET /api/v1/site-media/{name}` |
| **DB** | ١٢ جدول `site_*` |
| **Functions** | `guard_site_text_locked` · `trg_site_publish_guard` · `trg_site_publish_stamp` · `trg_site_consent_stamp` (٢) · `trg_site_redaction_stamp` · `trg_site_section_guard` · `trg_site_text_review_stamp` (٢) |
| **Permissions** | **`SITE.EDIT` و`SITE.PUBLISH` — رمزان لا رمز** |
| **Status** | 🟢 LIVE |

**الفصل مقصود لا مرتَّب:** كتابة شهادة عميل ووضعها على الإنترنت المفتوح **فعلان
مختلفان بعاقبتين مختلفتين**، والترتيب الطبيعي أن يصوغ موظّف ويَنشر مدير. رمزٌ واحد
يخدم الاثنين يقرّر بصمت أيّ القرارين لا يُسأل عنه أحد. **والاثنان اليوم لـ
`CENTER_ADMIN`** — والفصل يكلّف صفرًا الآن، وهو الفرق بين تغيير سياسة وهجرة لاحقًا.

**نشر الموقع** عبر `scripts/site-export.sh` و`deploy/server/site-export-watch.sh`.
> وأمان هذا السطح كلّه قائم على أمرٍ واحد: **أنّه لا يمرّر شيئًا إلى الخدمة.**
> و`site.native.mjs` يحمل **قائمة سماح** لأنواع الملفّات (لا قائمة منع)، و**تُشتقّ
> من السكيما لا من الصفحة** — `.mp4` لم تكن فيها وفي `site_team_media` صفّ `VIDEO`
> حقيقي ينتظر النشر، فأوّل نشر من الشاشة كان سيردّ `404` على الشيء الوحيد المعروض.

---

## F-43 · إعدادات المركز وبارامتراته

| الحقل | القيمة |
|---|---|
| **Module** | Settings · **Actors** CENTER_ADMIN (كتابة) · RECEPTION (قراءة) |
| **Entry Point** | `/settings` |
| **Screens** | `ops/features/settings/settings.ts` |
| **APIs** | `GET /api/v1/settings/params` · `PATCH /api/v1/settings/params/{code}` · `DELETE /api/v1/settings/params/{code}` · `PATCH /api/v1/settings/center` · `GET /api/v1/settings/time-zones` |
| **DB** | `sys_params` · `centers` · `lookup_types` · `lookup_values` |
| **Functions** | `param` · `set_center_param` (٢) · `clear_center_param` · `guard_center_settings` (٣) · `assert_center_argument` |
| **Permissions** | `SETTINGS.MANAGE` للكتابة |
| **Status** | 🟢 LIVE |

**الصلاحية تغطّي الصفّ ولا تقرّر أي الأعمدة تتحرّك** — ذلك منحةٌ على مستوى العمود
في `0051`، و`code` مستثنًى منها **تمامًا** فلا صلاحية تبلغه.
`0059` يحرس المنطقة الزمنية، و`0060` يفرّق «امسح القيمة» من «اكتب فراغًا».
`UNIQUE NULLS NOT DISTINCT` على `sys_params.center_id` لأن NULL هنا **قيمة** تعني
«عامّ» — صفّان عامّان بنفس الكود تكرارٌ حقيقي. (مقابل `children.national_id`:
NULL **غياب**، ففهرس جزئي — والخلط بينهما هو العيب الذي وصل الإنتاج في أوراكل:
**رفض ثاني طفل بلا رقم قومي، في مركز لأطفال صغار في مصر كثير منهم بلا رقم قومي**.)

> ⚠️ حارس مسار `/settings` هو `CATALOG.MANAGE` والقاعدة تطلب `SETTINGS.MANAGE`.
> راجع 18 · C-13.

---

## F-44 · سجلّ التشغيل والتدقيق والنسخ الاحتياطي

| الحقل | القيمة |
|---|---|
| **Module** | Ops · **Actors** CENTER_ADMIN |
| **Entry Point** | `/ops-log` · `/dashboard` |
| **Screens** | `ops/features/ops-log/ops-log.ts` · `dashboard.ts` · `dashboard-tiles.ts` · `day-summary.ts` |
| **APIs** | `GET /api/v1/ops/activity` · `GET /api/v1/ops/errors` · `GET /api/v1/ops/health` · `GET /api/v1/dashboard/metrics` |
| **DB** | `request_log` · `audit_log` · `audit_log_archive` · `backup_runs` · `maintenance_runs` · `convention_exemptions` |
| **Views** | `v_api_health` · `v_recent_errors` · `v_user_activity` (تُقرَأ) · **`v_audit_trail` · `v_backup_health` · `v_maintenance_health` · `v_sms_health` · `v_case_timeline` · `v_guardian_portal_status` · `v_attachment_index` (لا تُقرَأ)** |
| **Functions** | `log_request` · `trg_audit` · `audit_attempt` · `archive_audit` · `record_backup` · `backup_health` · `run_maintenance` (٤) · `trg_append_only` |
| **Permissions** | `OPS.VIEW` — **للمدير وحده**: السجلّ يسمّي كل مستخدم وكل مسار لمسه |
| **Status** | 🟡 PARTIAL |

**قواعد التدقيق:**
- **الأرشفة نقل، والحذف حذف.** أي «سياسة احتفاظ» على `audit_log` مرفوضة — الصفوف
  **تنتقل** إلى `audit_log_archive` وتبقى مسؤولةً عبر `v_audit_trail`. ودالّة تعطّل
  مشغّل حماية لتفعل ذلك **تتحقّق من إعادته قبل أن تعود**، وإلّا تركت سجلّ التدقيق
  قابلًا للكتابة وسكتت.
- **الـtelemetry يُحذف** (`request_log` بعد `REQUEST_LOG_RETENTION_DAYS`)، **والسجلّ
  السريري يُنقَل**. المحوران مختلفان.
- `WHEN OTHERS` **لا يلفّ جسم الدالّة كله** — `audit_attempt` كانت ترفع `HB012` عند
  استعمال خاطئ، ثمّ يبتلعها معالجها ويحوّلها تحذيرًا، فيمرّر المنادي فعلًا غير مسموح
  **ويرجع له «نجاح»**.
- **كل قراءة حسّاسة تُسجَّل صراحةً** — المشغّلات لا تلتقط القراءات.

**الناقص:** لا قارئ لـ`v_backup_health` ولا `v_maintenance_health` ولا `v_sms_health`
→ **التوقّف الصامت لا ينبّه أحدًا** (`HBH-008`). ولا استعادة فعلية مجدولة
(`HBH-009`). راجع 20.

> **درس نشر مسجَّل:** كانت النسخ الاحتياطية تنزل في `backups/` داخل المشروع،
> والمشروع تحت «سطح المكتب» المُعاد توجيهه إلى OneDrive — **فكل dump فيه السجلّ
> السريري الكامل لكل طفل كان يُرفَع إلى حساب سحابي شخصي تلقائيًّا**، بلا خطأ ولا
> سؤال ولا سطر في أي لوج. الوجهة الآن `~/hbh-backups`، و`backup.sh` **يقف** عند أي
> مجلّد مزامنة بدل أن يحذّر.

---

## OPEN QUESTIONS من هذه الوثيقة

| # | السؤال | الأثر |
|---|---|---|
| **OQ-02** | متى يجب أن يُخصم رصيد الباقة — عند `CHECKED_IN`؟ عند `COMPLETED`؟ عند إغلاق الجلسة؟ وهل `ABORTED` يُخصم؟ | F-25 · F-35 · الفاتورة · ثقة الأسرة في الدفتر |
| **OQ-03** | وليّ أمر أُنشئ **من داخل المركز** — هل يُمنح حساب بوّابة، ومن يقرّر ذلك، ومن أي شاشة؟ | F-07 · F-12 · الدخول · الإشعارات |
| **OQ-04** | من يُدخل إجازات المركز والحجوزات المغلقة، ومن أي شاشة؟ | F-24 · F-19 · F-20 |
| **OQ-05** | هل `origin_source` / `registration_source` مطلوبة لسجلّات جديدة؟ إن نعم، من يختمها ومتى؟ | F-09 · F-12 · 15 · 16 |
| **OQ-06** | هل الخمس أنواع من الإشعارات غير المُرسَلة مطلوبة (`SESSION_STARTED` · `STAFF_*`)، أم تُحذف من القيد؟ | F-37 · 10 |
| **OQ-07** | `plan_kind` — أنواع تحمل سلوكًا أم تسميات للعرض؟ (`HBH-020` · محجوب على المالك) | F-28 |
