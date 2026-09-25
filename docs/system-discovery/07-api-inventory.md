# 07 — API INVENTORY

**الخدمة:** `api/cmd/hbhd` · Go · `net/http.ServeMux` (Go 1.22+ patterns).
**البادئة:** `/api/v1` عدا `/healthz` و`/readyz`.

| البند | العدد |
|---|---|
| مسارات مسجَّلة صراحةً | **١١٨** (method × path) |
| مسارات CRUD مولَّدة | **~١٧٨** (٣٠ موردًا) |
| الإجمالي | **~٢٩٦** |

---

## ١ · بنية الموجّه — ولماذا هي كذلك

```go
rt.route(method, pattern, handler)   // يسجّل + يلفّ الـhandler باسم القالب
rt.finish()                          // يضيف fallback لكل PATH مرّة واحدة
```

**قرارات مسجَّلة في `server.go`:**
- `router` يجمع المسارات ليُسجَّل fallback **لكل مسار** لا لكل route — لأن
  `ServeMux` القياسي **يهلع على نمط مكرَّر**، فأوّل مسار كسب طريقة ثانية
  (`GET` و`POST` على `.../requests`) **أسقط العملية كلّها عند الإقلاع**.
- ويسمح لـ`Allow` أن يسمّي **كل** الطرق التي يقبلها المسار فعلًا، بدل آخر واحدة
  سُجِّلت.
- `405` تُجاب **بـJSON** لا نصًّا عاديًّا — عميلٌ يفسّر كل ردّ كـJSON كان يحصل على
  خطأ تحليل بدل سبب الرفض.
- كل handler ملفوف بـ`noteRoute(pattern)` فسجلّ الطلبات يسجّل **القالب** الذي
  طابق، لا المسار الذي اختاره غريب — **و`404` تسجّل قيمة حرّاسة**.

**سلسلة الوسائط — من الخارج إلى الداخل:**
```
withRecover  →  withRequestID  →  withLogging  →  s.withRequestLog
             →  withSecurityHeaders  →  withCORS  →  router
```
- الاستعادة **خارج** التسجيل فالهلع يُنتج سطر طلب.
- التسجيل **خارج كل شيء** فرفضُ CORS أو حدّ المعدّل يُسجَّل.
- سجلّ القاعدة **داخل** `withRequestID` (يحتاج المعرّف) و**خارج** الباقي (يجب أن
  يرى حالة الطلب الذي رفضه CORS أو حدّ المعدّل — **وهي بالضبط الطلبات التي يبحث
  عنها المشغّل**).

---

## ٢ · الجرد — مجموعًا بالوحدة

### الصحّة والهوية

| Method | Route | Handler | الوصول | الكيانات |
|---|---|---|---|---|
| GET | `/healthz` | `handleHealth` | عامّ | — |
| GET | `/readyz` | `handleReady` | عامّ | `migration_applied` |
| POST | `/api/v1/auth/otp/request` | `handleRequestOTP` | **عامّ · محدود المعدّل** | `users` · `otp_codes` · `sms_outbox` |
| POST | `/api/v1/auth/otp/verify` | `handleVerifyOTP` | **عامّ · محدود المعدّل** | `otp_codes` · `auth_sessions` |
| POST | `/api/v1/auth/staff/login` | `handleStaffLogin` | **عامّ · محدود المعدّل** | `users` · `auth_sessions` |
| POST | `/api/v1/auth/logout` | `handleLogout` | مصادَق | `auth_sessions` |
| POST | `/api/v1/auth/password` | `handleChangeOwnPassword` | مصادَق | `users` |
| POST | `/api/v1/auth/password-setup` | `handleRedeemPasswordSetup` | **عامّ — الرمز هو الاعتماد** | `password_setups` · `users` |
| GET | `/api/v1/me` | `handleMe` | مصادَق | `users` · `user_roles` · `permissions` |
| GET | `/api/v1/me/contact` | `handleGuardianContact` | GUARDIAN | `guardians` |
| PATCH | `/api/v1/me/contact` | `handleSetGuardianContact` | GUARDIAN (سجلّه هو) | `guardians` |
| GET | `/api/v1/permissions` | `handlePermissions` | مصادَق | `permissions` |
| GET | `/api/v1/roles` | `handleRoles` | `USER.MANAGE` | `roles` · `role_permissions` |
| PUT | `/api/v1/roles/{code}/permissions` | `handleSetRolePermissions` | `USER.MANAGE` | `role_permissions` |

**أربعة مسارات غير مصادَقة تكتب أو تُصدر اعتمادًا** — وكل واحد له سببه المكتوب:
`otp/request` · `otp/verify` · `staff/login` · `auth/password-setup`. وخامسٌ يكتب
بلا أي هوية: `POST /enrolments`.

### المستخدمون وملفّاتهم

| Method | Route | الوصول |
|---|---|---|
| GET | `/api/v1/users` | `USER.MANAGE` |
| POST | `/api/v1/users` | `USER.MANAGE` |
| PATCH | `/api/v1/users/{user_id}` | `USER.MANAGE` |
| DELETE | `/api/v1/users/{user_id}` | `USER.MANAGE` — **أرشفة لا حذف** |
| PUT | `/api/v1/users/{user_id}/roles` | `USER.MANAGE` + `guard_last_admin` |
| POST | `/api/v1/users/{user_id}/password-setup` | `USER.MANAGE` |
| POST | `/api/v1/users/{user_id}/documents` | `STAFF.PII` |
| GET | `/api/v1/staff-documents/{document_id}/file` | `STAFF.PII` — **يُعنوَن بالصفّ، لا بالملفّ** |
| POST · GET | `/api/v1/users/{user_id}/photo` | `STAFF.PII` / المالك |

**قرار مسجَّل:** تحميل مستند موظّف **يكتب الملفّ والصفّ معًا**، والتنزيل
**يُعنوَن بالصفّ لا باسم الملفّ** — فـRLS هي التي تقرّر، **ولا مسار يستطيع عميل
أن يبنيه**. وكلّه خلف `requireAuth`: **لا شيء هنا عامّ أبدًا.**

### الالتحاق

| Method | Route | الوصول |
|---|---|---|
| POST | `/api/v1/enrolments` | **عامّ · حدّ لكل جوال/يوم ولكل IP/ساعة** |
| GET | `/api/v1/enrolments` | `ENROLMENT.MANAGE` |
| GET | `/api/v1/enrolments/{application_id}` | `ENROLMENT.MANAGE` |
| PATCH | `/api/v1/enrolments/{application_id}` | `ENROLMENT.MANAGE` |
| POST | `/api/v1/enrolments/{application_id}/convert` | `ENROLMENT.MANAGE` |

### الطفل والأسرة

| Method | Route | الوصول |
|---|---|---|
| GET | `/api/v1/children` | `CHILD.VIEW_ALL` أو `can_access_child` (البوّابة) |
| GET | `/api/v1/children/{child_id}` | `can_access_child` |
| GET | `/api/v1/children/{child_id}/profile` | `can_access_child` |
| GET | `/api/v1/children/{child_id}/guardians` | `GUARDIAN.MANAGE` |
| POST · GET | `/api/v1/children/{child_id}/photo` | `CHILD.EDIT` + موافقة `PHOTO_USE` |
| GET | `/api/v1/children/{child_id}/appointments` | `can_access_child` |
| GET | `/api/v1/children/{child_id}/sessions` | `can_access_child` |
| GET | `/api/v1/children/{child_id}/notes` | `can_access_child` + **سلّم الرؤية** |
| GET | `/api/v1/children/{child_id}/plans` | `can_access_child` |
| GET | `/api/v1/children/{child_id}/reports` | `REPORT.VIEW` + `can_access_child` |
| GET | `/api/v1/children/{child_id}/activities` | `can_access_child` |
| GET | `/api/v1/children/{child_id}/activity-log` | `can_access_child` |
| POST | `/api/v1/children/{child_id}/activities/{child_activity_id}/log` | وليّ الأمر على طفله |
| GET | `/api/v1/children/{child_id}/invoices` | `BILLING.VIEW` أو الأسرة |
| GET | `/api/v1/children/{child_id}/balance` | كذلك |
| GET · POST | `/api/v1/children/{child_id}/packages` | `BILLING.MANAGE` للبيع |
| GET · POST | `/api/v1/children/{child_id}/requests` | `REQUEST.SUBMIT` / `REQUEST.MANAGE` |
| POST · DELETE | `/api/v1/guardians/{guardian_id}/consent` | `GUARDIAN.MANAGE` |
| GET | `/api/v1/family-contacts` | `REQUEST.MANAGE` |
| GET · POST | `/api/v1/family-messages/{guardian_id}` | `REQUEST.MANAGE` أو صاحب الخيط |
| POST | `/api/v1/family-messages/{guardian_id}/read` | كذلك |

### الجدولة والجلسة

| Method | Route | الوصول |
|---|---|---|
| GET | `/api/v1/appointments` | `CHILD.VIEW_ALL` |
| GET | `/api/v1/appointments/slots` | `APPOINTMENT.BOOK` |
| POST | `/api/v1/appointments/validate` | `APPOINTMENT.BOOK` |
| POST | `/api/v1/appointments` | `APPOINTMENT.BOOK` |
| PATCH | `/api/v1/appointments/{appointment_id}/status` | `APPOINTMENT.BOOK` / `APPOINTMENT.CANCEL` |
| POST | `/api/v1/appointments/{appointment_id}/session` | `SESSION.START` + `caseload` |
| POST | `/api/v1/appointments/{appointment_id}/consultation` | `authorize_meeting_entry` |
| GET | `/api/v1/sessions` | `SESSION.START` |
| PUT | `/api/v1/sessions/{session_id}/note` | `SESSION.NOTES.EDIT` + صاحب الجلسة |
| PATCH | `/api/v1/sessions/{session_id}/close` | `SESSION.COMPLETE` + `can_close_session` |
| POST | `/api/v1/notes/{note_id}/publish` | `NOTE.PUBLISH` |
| POST | `/api/v1/sessions/{session_id}/stream` | `LIVE.VIEW` + موافقة `LIVE_VIEW` |
| POST | `/api/v1/stream/close` | صاحب التوكن |

### الأخصائيون

| Method | Route | الوصول |
|---|---|---|
| GET · POST · DELETE | `/api/v1/therapists/{id}/services[/{service_id}]` | `STAFF.MANAGE` |
| GET · PUT · DELETE | `/api/v1/therapists/{id}/languages[/{lang_code}]` | `STAFF.MANAGE` |
| GET · POST | `/api/v1/therapists/{id}/certificates` | `STAFF.MANAGE` |
| PATCH | `/api/v1/certificates/{certificate_id}/image` | `STAFF.MANAGE` |
| PATCH | `/api/v1/therapists/{id}/profile` | `can_edit_therapist` |
| POST · DELETE | `/api/v1/therapists/{id}/consent` | موافقة الأخصائي |
| POST | `/api/v1/therapists/{id}/publish` | `SITE.PUBLISH` |
| GET | `/api/v1/service-therapists` | `APPOINTMENT.BOOK` |
| GET | `/api/v1/services/{service_id}/therapists` | `APPOINTMENT.BOOK` |

### المال

| Method | Route | الوصول |
|---|---|---|
| GET · POST | `/api/v1/invoices` | `BILLING.VIEW` / `BILLING.MANAGE` |
| GET | `/api/v1/invoices/{invoice_id}` | `BILLING.VIEW` |
| POST · DELETE | `/api/v1/invoices/{invoice_id}/lines[/{line_id}]` | `BILLING.MANAGE` |
| POST | `/api/v1/invoices/{invoice_id}/issue` | `BILLING.MANAGE` |
| POST | `/api/v1/invoices/{invoice_id}/payments` | `BILLING.MANAGE` |
| GET | `/api/v1/billing/summary` | `BILLING.VIEW` |
| GET | `/api/v1/billing/ledger` | `BILLING.VIEW` |

### التقارير · الطلبات · الإشعارات · الاستبيان

| Method | Route | الوصول |
|---|---|---|
| GET · POST | `/api/v1/reports` | `REPORT.VIEW` / `REPORT.WRITE` |
| GET · PATCH | `/api/v1/reports/{report_id}` | `REPORT.VIEW` / `REPORT.WRITE` |
| POST | `/api/v1/reports/{report_id}/publish` | `REPORT.PUBLISH` |
| GET · PATCH | `/api/v1/requests[/{request_id}]` | `REQUEST.MANAGE` |
| GET | `/api/v1/notifications` | صاحب الصفّ |
| POST | `/api/v1/notifications/{notification_id}/read` | صاحب الصفّ |
| GET | `/api/v1/nps/due` | GUARDIAN |
| POST | `/api/v1/nps/{survey_id}/response` | GUARDIAN |
| POST | `/api/v1/nps/{survey_id}/skip` | GUARDIAN |
| GET | `/api/v1/nps/summary` | `NPS.MANAGE` |

### الإعدادات · التشغيل · الموقع

| Method | Route | الوصول |
|---|---|---|
| GET | `/api/v1/settings/params` | مصادَق (قراءة) |
| PATCH · DELETE | `/api/v1/settings/params/{code}` | `SETTINGS.MANAGE` |
| PATCH | `/api/v1/settings/center` | `SETTINGS.MANAGE` |
| GET | `/api/v1/settings/time-zones` | مصادَق |
| GET | `/api/v1/dashboard/metrics` | `PORTAL.VIEW` |
| GET | `/api/v1/ops/activity` · `/ops/errors` · `/ops/health` | `OPS.VIEW` |
| POST | `/api/v1/site-media` | `SITE.EDIT` — **المسار الوحيد الذي يكتب ملفًّا لا صفًّا، والوحيد الذي يفحص صلاحيةً بنفسه** |
| GET | `/api/v1/site-media/{name}` | **غير مصادَق — بقرار مسجَّل** |

> **لماذا `GET /site-media/{name}` عامّ:** الخدمة تصادق بتوكن في رأس، و`<img src>`
> أو `<video src>` **لا يرسل رؤوسًا** — فمسارٌ مصادَق هنا يرسم صورة مكسورة لمن
> رفعها للتوّ بلا طريقة يعرف بها إن نجحت. والبديل — الجلب عبر المعترِض ورسم blob —
> يعني سحب فيلم بمئة ميجابايت إلى ذاكرة المتصفّح لأجل معاينة.
> **وما يجعله مقبولًا:** هذه أصول تسويقية لصفحة لا تسجيل دخول عليها، واسم الملفّ
> المرفوع هو **SHA-256 لمحتواه**، فلا يُخمَّن ولا يُعدَّد، ومعرفته تعني امتلاك الملفّ.
> **وقيل صراحةً:** صورة مرفوعة ولم تُنشَر بعد **يبلغها من يملك بصمتها** — وهذا هو
> الثمن، وهو صغير لهذا المحتوى **وغير مقبول لأي شيء إكلينيكي، ولهذا لا شيء
> إكلينيكي يُخدَم من هنا.**

---

## ٣ · مسارات CRUD المولَّدة

`registerCRUD` يسجّل **٦ مسارات لكل مورد**:

```
GET    /api/v1/{resource}              قائمة  (?q= · ?archived=true)
GET    /api/v1/{resource}/{param}      واحد
POST   /api/v1/{resource}              إنشاء
PATCH  /api/v1/{resource}/{param}      تعديل
DELETE /api/v1/{resource}/{param}      أرشفة  ← ليست حذفًا
POST   /api/v1/{resource}/{param}/restore   استعادة
```

**استثناء:** `children` تُستثنى من الـ`GET`ين — للبوّابة جوابها الخاصّ وهو الصحيح
لوليّ أمر. فتحصل على ٤ مسارات لا ٦.

### الموارد الثلاثون

| Resource | Param | Table | بحث حرّ `?q=` |
|---|---|---|---|
| `services` | `service_id` | `hbh.services` | `code` · `name_ar` · `name_en` |
| `rooms` | `room_id` | `hbh.rooms` | `code` · `name_ar` · `name_en` |
| `cameras` | `camera_id` | `hbh.cameras` | — |
| `activity-library` | `activity_id` | `hbh.activity_library` | `code` · `title_ar` |
| `service-packages` | `package_id` | `hbh.service_packages` | — |
| `therapists` | `therapist_id` | `hbh.therapists` | `full_name_ar` · `title_ar` |
| `working-hours` | `working_hour_id` | `hbh.therapist_working_hours` | — |
| `caseload` | `caseload_id` | `hbh.caseload` | — |
| `children` | `child_id` | `hbh.children` | `full_name_ar` · `child_no` |
| `guardians` | `guardian_id` | `hbh.guardians` | `full_name_ar` · `mobile` · `email` |
| `plans` | `plan_id` | `hbh.treatment_plans` | — |
| `goals` | `goal_id` | `hbh.plan_goals` | — |
| `child-activities` | `child_activity_id` | `hbh.child_activities` | — |
| `measurements` | `measurement_id` | `hbh.goal_measurements` | — |
| `therapist-qualifications` | `qualification_id` | `hbh.therapist_qualifications` | — |
| `nps-surveys` | `survey_id` | `hbh.nps_surveys` | `code` · `name_ar` |
| `site-contact` | `contact_id` | `hbh.site_contact` | — |
| `site-texts` | `text_id` | `hbh.site_texts` | `text_key` · `text_ar` |
| `site-faq` | `faq_id` | `hbh.site_faq` | — |
| `site-team` | `member_id` | `hbh.site_team` | — |
| `staff-profiles` | — | `hbh.staff_profiles` | — |
| `staff-documents` | — | `hbh.staff_documents` | — |
| `site-team-media` | `media_id` | `hbh.site_team_media` | — |
| `site-team-specialties` | — | `hbh.site_team_specialties` | — |
| `site-reviews` | `review_id` | `hbh.site_reviews` | — |
| `site-team-certificates` | — | `hbh.site_team_certificates` | — |
| `site-team-facts` | `fact_id` | `hbh.site_team_facts` | — |
| `site-services` | `site_service_id` | `hbh.site_services` | — |
| `site-programs` | `program_id` | `hbh.site_programs` | — |
| `site-sections` | `section_id` | `hbh.site_sections` | — |

**قواعد مثبتة بالثمن في `crud_handlers.go`:**
- **سلسلة الاستعلام تُحلَّل والخطأ يُقرأ** — `req.URL.Query()` يرميه. فمنذ Go 1.17
  الفاصلة المنقوطة خطأُ تحليل، و`Query()` يجيب بما قرأ **بلا إشارة إلى ما أسقط**:
  مصطلحٌ فيه `;` كان يصل **بلا مصطلح أصلًا**، والردّ **الجدول كلّه** — وهو بالضبط
  الفشل الذي وُجدت هذه الدفعة لإزالته، **يلبس `200`**.
  وُجد بالبحث عن `'); DROP TABLE hbh.guardians; --`: **لا شيء حُقِن** (المصطلح
  بارامتر مربوط ولا يبلغ المحلّل) — **وعادوا كلّهم الستّة**. وبحثٌ يجيب «كل شيء»
  عن نصّ عدائي عيبٌ أيًّا كان سببه.
- **مصطلحٌ على مورد لا يستطيع مطابقته = رفض** (`400`)، لا إسقاطًا صامتًا.
  **تجاهلُ بارامتر لم تُنفّذه هو كيف نجا ذلك.**
- **`?archived=true` قرار عرضٍ لا قاعدة وصول** — السياسة تقرّر هل يرى الصفّ المؤرشف
  أصلًا، وهذا يقرّر هل نطلبه.
- **`DELETE` أرشفة** — `store.SoftDelete`. **لا منحة `DELETE` على أي جدول في هذه
  السكيما**، فالفعل يصف ما تعنيه الشاشة لا ما تفعله القاعدة.
- `likeEscape` يضاعف الشرطة المائلة ثم يهرّب `%` و`_`، وكل نمط ينتهي بـ`ESCAPE '\'`.
  **والتهريب يسبق الطيّ العربي** (`likeEscape` في Go ثم `normalize_arabic` فوق
  نتيجته) — لأن الدالّة لا تمسّ الشرطة المائلة.

---

## ٤ · ترجمة الرفض — `SQLSTATE` → HTTP

| المصدر | الردّ |
|---|---|
| `HBxxx` معروف بالاسم | الرمز المخصَّص له (`403` · `409` · `413` · `415` · `422` …) |
| `HBxxx` **غير** معروف | **`409 REFUSED`** — لا `500` |
| `42501` منحة ناقصة | `403` |
| صفر صفوف من سياسة | `404` — **لا `403`**، لأن `403` تخبر بوجود ما لا يجوز معرفته |
| غير ذلك | `500` + سطر في `v_recent_errors` |

> 🔴 **والاحتياطي كلّف مرّتين في يوم واحد.** `businessRefusal` كان ينتهي بـ
> `HasPrefix(code, "HB0")` — صحيحًا يوم كُتب. ثم نمت السكيما إلى `HB1xx` **فسقطت
> ثمانية رفضات حيّة في `500`** ووصلت الشاشة كـ«حدث خطأ غير متوقَّع». وُسِّع إلى
> `"HB"` — **فأخفى النصف الثاني**: واحد وعشرون رمزًا حيًّا صارت تُجاب `409 REFUSED`،
> فيها **نقصُ صلاحية يُبلَّغ تعارضًا**، وأخطاؤنا نحن تُنسب إلى المتّصل، وبوّابةُ
> موافقة المشاهدة الحيّة تجيب بكلمة **لا تستطيع الشاشة التصرّف بها**.
>
> **والاختبار المكتوب للأولى لا يرى الثانية**: «هل الرمز معروف؟» جوابه نعم، لأن
> الاحتياطي يجيب فعلًا. السؤال الذي لم يُطرح: **«معروفٌ بالاسم؟»**
> الحارس `bash scripts/api.sh code-drift` يقرأ `pg_proc` ويقارنه بالجدول، وهو في
> سلسلة `lint`.
>
> **والاحتياطي الحالي خاصّيةٌ لا قائمة:** `business_refusal_test.go` يمشي
> `HB000`→`HB999` ويثبت أن **أي** رمز يُجاب بغير `500`. ولهذا تحمل رؤوس `0117` و
> `0118` و`0120` سطر «**ORDER OF DEPLOYMENT: EITHER WAY ROUND**» — وقد فُحص لا
> افتُرض: **وملاحظة نشر خاطئة أسوأ من غياب ملاحظة نشر.**

---

## ٥ · تكرار محتمل في المسارات

**الفحص المطلوب في §9: هل مساران يؤدّيان نفس الوظيفة؟**

| المجموعة | الحكم |
|---|---|
| `GET /children` (بوّابة) · `GET /children` (CRUD) | ✅ **لا تكرار** — `children` مستثناة من `GET`ي CRUD بقصد، والبوّابة هي الجواب الوحيد |
| `GET /children/{id}` · `GET /children/{id}/profile` | ⚠️ **تداخل** — الأول ملخّص والثاني تفصيل. الحدّ بينهما غير موثَّق ولا اختبار يثبته. راجع 19 · D-07 |
| `GET /invoices` · `GET /children/{id}/invoices` | ✅ فهرسة مختلفة (بالمركز مقابل بالطفل) |
| `GET /appointments` · `GET /children/{id}/appointments` | ✅ كذلك |
| `GET /reports` · `GET /children/{id}/reports` | ✅ كذلك |
| `GET /requests` · `GET /children/{id}/requests` | ✅ كذلك |
| `GET /sessions` · `GET /children/{id}/sessions` | ✅ كذلك |
| `GET /therapists/{id}/services` · `GET /services/{id}/therapists` · `GET /service-therapists` | ⚠️ **ثلاثة مسارات على نفس الجدول** بثلاث فهرسات. الثالث يخدم شاشة الحجز. مقبول ويستحقّ تعليقًا يقول أيّها لأيّ شاشة. راجع 19 · D-08 |
| `PUT /therapists/{id}/languages` مقابل `DELETE .../languages/{lang_code}` | ✅ `PUT` upsert و`DELETE` مفرد |
| `POST /users/{id}/photo` · `POST /site-media` · `POST /children/{id}/photo` | ⚠️ **ثلاثة مسارات ترفع ملفًّا بثلاث سياسات مختلفة** (صفّ مصادَق · ملفّ عامّ · صفّ بموافقة). الفرق حقيقي، **والتوثيق الجامع غائب** |
| `POST /auth/password` · `POST /auth/password-setup` | ✅ تغيير ذاتي مقابل استهلاك رابط |

**لم يُعثَر على أي مسار مكرَّر فعليًّا** (لا `POST /parents` و`POST /parent/create`
و`POST /api/parent` معًا) — **والاصطلاح متّسق تمامًا**: جمعٌ للمورد، `{entity_id}`
للمعرّف، فعلٌ بعده للأمر (`/issue` · `/publish` · `/convert` · `/close`).

---

## ٦ · مسارات بلا مستهلك واجهة

| Route | من يستعمله |
|---|---|
| `GET /api/v1/therapist-qualifications` + CRUD | ❌ لا شاشة (ولا Spec) |
| `POST /api/v1/site-team-specialties` + CRUD | عبر `team-screen.ts` ✅ |
| `GET /api/v1/site-sections` + CRUD | `/site` ✅ |
| `POST /api/v1/services/{id}/…` | ✅ |

**وقدرات القاعدة بلا مسار — الأهمّ:** التقييمات · قائمة الانتظار · الحجز المتكرّر ·
`schedule_blocks` · المرفقات العامّة · `grant_portal_access` · `v_case_timeline` ·
صحّة النسخ/الصيانة/الـSMS. راجع 20.

---

## ٧ · حدّ المعدّل · CORS · الرؤوس

| البند | القيمة |
|---|---|
| حدّ معدّل المصادقة | `AUTH_RATE_PER_MINUTE` على IP · يُسجَّل `ActionDeny` |
| حدّ الالتحاق | `ENROLMENT_MAX_PER_IP_HOUR` · `ENROLMENT_MAX_PER_MOBILE_DAY` — **في القاعدة لا في الطبقة** |
| CORS | `CORS_ORIGINS` — قائمة سماح صريحة |
| رؤوس الأمن | `withSecurityHeaders` |
| IP العميل | `TRUST_PROXY` + `TRUSTED_PROXIES` (بادئات CIDR) — `HBH-005` يطلب `TRUST_PROXY=true` في النشر |
| سجلّ الطلبات | `REQUEST_LOG` (افتراضي `true`) → `request_log` · يُحذف بعد `REQUEST_LOG_RETENTION_DAYS` |
| حجم المرفق | `MAX_ATTACHMENT_MB` (٥) → `HB121` = `413` |

---

## ٨ · العقد المكتوب

[`../02-api-contract.md`](../02-api-contract.md) (٨٦ كيلوبايت) هو عقد الـAPI
الرسمي. **آخر تحديثه 2026-09-12، ووثيقة `INDEX.md` تصنّفه ⬜ «لم يُقابَل بـ١٠٧
مسارًا»** — والعدد اليوم **١١٨ صريحًا**. أي أن العقد **يحتاج مقابلةً بالموجّه
كاملة** قبل أن يُعتمد عليه. راجع 21 · T-08.

**أداة المقابلة موجودة:** `tests/e2e/e1_contract_verify.sh`.

---

## OPEN QUESTIONS

| # | السؤال | الأثر |
|---|---|---|
| **OQ-21** | `GET /children/{id}` مقابل `/children/{id}/profile` — ما الحدّ بينهما، وهل يُدمجان؟ | 07 · 19 · D-07 |
| **OQ-22** | `therapist-qualifications` له CRUD كامل ولا شاشة — يُربط بشاشة الملفّ أم يُسحب؟ | 07 · 06 |
