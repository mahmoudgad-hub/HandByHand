# 06 — FRONTEND SCREEN INVENTORY

**ثلاثة أسطح مستقلّة**، لا يتشارك أيّها كود مع الآخر إلّا عبر `web/shared`.

| السطح | التقنية | الشاشات | المسار |
|---|---|---|---|
| بوّابة الأسرة | Angular 20 · standalone · lazy | **٢٠** | `web/portal` |
| تطبيق المركز | Angular 20 · standalone · lazy | **٢٨** | `web/ops` |
| مكوّنات مشتركة | Angular · مكتبة | **١١** | `web/shared` |
| الموقع التعريفي | HTML/CSS/JS خام · بلا بناء | **٢** صفحتان | `site` |

---

## ١ · بوّابة الأسرة — `web/portal`

| Screen | Route | Guard | الغرض | APIs |
|---|---|---|---|---|
| Login | `/login` | `guestOnlyGuard` | إدخال الجوال | `POST /auth/otp/request` |
| OTP | `/login/otp` · `/otp` | `guestOnlyGuard` | إدخال الرمز | `POST /auth/otp/verify` |
| Apply | `/apply` | **لا حارس — عامّ** | نموذج طلب الالتحاق | `POST /enrolments` · `GET /site-contact` |
| Welcome | `/welcome` | `authGuard` | اختيار الطفل + مدخل | `GET /me` · `GET /children` |
| Home | `/home` | `authGuard` + `childSelectedGuard` | ملخّص الطفل + بطاقة NPS | `GET /children/{id}` · `GET /nps/due` · `GET /notifications` |
| Schedule | `/schedule` | + `childSelectedGuard` | مواعيد الطفل | `GET /children/{id}/appointments` |
| Progress | `/progress` | + `childSelectedGuard` | الأهداف والقياسات | `GET /children/{id}/plans` · `v_goal_progress` |
| Activities | `/activities` | + `childSelectedGuard` | البرنامج المنزلي وتسجيله | `GET /children/{id}/activities` · `POST .../log` |
| Live | `/live` | + `childSelectedGuard` | مشاهدة الجلسة | `POST /sessions/{id}/stream` · `POST /stream/close` |
| Consultation | `/consultation/:appointmentId` | `authGuard` | غرفة الاستشارة الأونلاين | `POST /appointments/{id}/consultation` |
| Reports (list) | `/reports` | + `childSelectedGuard` | التقارير المنشورة | `GET /children/{id}/reports` |
| Report (one) | `/reports/:reportId` | + `childSelectedGuard` | تقرير واحد | `GET /reports/{id}` |
| Billing | `/billing` | `authGuard` | الفواتير والرصيد | `GET /children/{id}/invoices` · `.../balance` |
| Requests | `/requests` | `authGuard` | إرسال ومتابعة الطلبات | `GET/POST /children/{id}/requests` |
| Communications | `/communications` | `authGuard` | رسائل الأسرة ↔ المركز | `GET/POST /family-messages/{guardian_id}` |
| Therapist | `/therapists/:therapistId` | `authGuard` | ملفّ الأخصائي العامّ | `GET /therapists/{id}` · `.../languages` |
| Notifications | `/notifications` | `authGuard` | التغذية | `GET /notifications` · `POST .../read` |
| Profile | `/profile` | `authGuard` | بيانات وليّ الأمر | `GET/PATCH /me/contact` |
| NPS card | (مكوّن في `/home`) | — | السؤال والتخطّي | `POST /nps/{id}/response` · `/skip` |
| Shell | `/` (layout) | `authGuard` | التنقّل + سياق الطفل | — |

**الحرّاس:** `authGuard` · `guestOnlyGuard` · `childSelectedGuard`.
`ChildContextService` يحفظ الطفل الحالي — **وهو سياق عرضٍ لا ضابط وصول**: RLS
هي التي تمنع وليَّ أمر من بيانات طفل آخر، لا الحارس.

**مكوّنات البوّابة الخاصّة:** `shared/ui/appointment-row.ts` · `shared/ui/status-badge.ts`.
**طبقة الـAPI:** `core/api/portal-api.ts` (واجهة) + `http-portal-api.ts` (تنفيذ)
+ **`fixture-portal-api.ts`** (بيانات ثابتة للتطوير) — راجع 21 · T-05.

---

## ٢ · تطبيق المركز — `web/ops`

### شاشات مخصَّصة

| Screen | Route | Permission | الغرض |
|---|---|---|---|
| Login | `/login` | `opsGuestGuard` | دخول الموظّف |
| Dashboard | `/dashboard` | `PORTAL.VIEW` | أرقام اليوم + بلاطات |
| Inbox | `/inbox` | `PORTAL.VIEW` | إشعارات الموظّف |
| Access | `/access` | `PORTAL.VIEW` ⚠️ | **المستخدمون · الأدوار · الصلاحيات · مستندات وصور الموظّفين** |
| Child profile | `/children/:childId` | `CHILD.VIEW_ALL` | ملفّ الطفل |
| Child card | `/children/:childId/card` | `CHILD.VIEW_ALL` | كارت الطفل + الصورة + الموافقات |
| Report editor (new) | `/children/:childId/reports/new` | `REPORT.WRITE` | صياغة تقرير |
| Report editor (edit) | `/children/:childId/reports/:reportId` | `REPORT.WRITE` | تعديل مسودّة |
| Therapist profile | `/therapists/:therapistId/profile` | **لا حارس — بقصد** | تحرير الملفّ العامّ + موافقته + نشره |
| Therapist services | `/therapist-services` | `STAFF.MANAGE` | ربط أخصائي بخدمة |
| Team screen | `/site/team` | `SITE.EDIT` | الفريق · الوسائط · الشهادات · التخصّصات · الحقائق |
| Live view | `/sessions/:sessionId/live` | `LIVE.VIEW` | مشاهدة جلسة جارية |
| Satisfaction | `/satisfaction` | `CATALOG.MANAGE` ⚠️ | إجابات NPS + `v_nps_summary` |
| Settings | `/settings` | `CATALOG.MANAGE` ⚠️ | بارامترات المركز + المنطقة الزمنية |
| Ops log | `/ops-log` | `OPS.VIEW` | `v_api_health` · `v_recent_errors` · `v_user_activity` |
| Communications | `/communications` | `REQUEST.MANAGE` | **نفس مكوّن البوّابة** |
| Denied | `/denied` | — | رسالة «لا صلاحية» |
| Shell / Nav | `/` | `opsAuthGuard` | التنقّل — الروابط تُفلتر بالصلاحية |

### شاشات «اليوم» (`features/day`)

| Screen | Route | Permission | Spec |
|---|---|---|---|
| Appointments (الحجز) | `/appointments` | `APPOINTMENT.BOOK` | `APPOINTMENTS_SPEC` |
| My Day | `/my-day` | `SESSION.START` | `APPOINTMENTS_SPEC` |
| Sessions | `/sessions` | `SESSION.START` | `SESSIONS_SPEC` |
| Reports list | `/reports` | `REPORT.VIEW` | `REPORTS_SPEC` |
| Billing overview | `/billing` | `BILLING.VIEW` | `INVOICES_SPEC` |
| Billing ledger | (داخل `/billing`) | `BILLING.VIEW` | — |
| Requests | `/requests` | `REQUEST.MANAGE` | `REQUESTS_SPEC` |
| Enrolments | `/enrolments` | `ENROLMENT.MANAGE` | `ENROLMENTS_SPEC` |

> **`/appointments` و`/my-day` يستعملان نفس الـ`APPOINTMENTS_SPEC` وهما ليسا
> تكرارًا.** المكتوب في الكود: «**لا شيء منسوخ. ما يختلف هو الصلاحية على المسار**» —
> الأولى `APPOINTMENT.BOOK` (الاستقبال) والثانية `SESSION.START` (الأخصائي)،
> **وكل فعل داخل الشاشة تحرسه صلاحيته هو** (`day-screen.ts`). وقبل ذلك كان
> الأخصائي يرى شاشةً تعرض الحجز ولا يستطيعه: **الصلاحية كانت حقيقية وغير قابلة
> للوصول.**

### شاشة المورد العامّة (`features/resource/resource-screen.ts`)

**مكوّن واحد يخدم ٢٠ موردًا عبر `resource-spec.ts`** — وهذا أفضل مثال على إعادة
الاستعمال في المشروع:

| Route | Permission | Specs |
|---|---|---|
| `/children` | `CHILD.VIEW_ALL` | `GUARDIANS_SPEC` · `CHILDREN_SPEC` |
| `/therapists` | `STAFF.MANAGE` | `THERAPISTS_SPEC` · `WORKING_HOURS_SPEC` · `CASELOAD_SPEC` |
| `/rooms` | `CATALOG.MANAGE` | `ROOMS_SPEC` · `CAMERAS_SPEC` |
| `/plans` | `PLAN.MANAGE` | `PLANS_SPEC` · `GOALS_SPEC` · `MEASUREMENTS_SPEC` · `CHILD_ACTIVITIES_SPEC` |
| `/catalog` | `CATALOG.MANAGE` | `SERVICES_SPEC` · `PACKAGES_SPEC` · `ACTIVITY_LIBRARY_SPEC` · `NPS_SURVEYS_SPEC` |
| `/site` | `SITE.EDIT` | `SITE_CONTACT_SPEC` · `SITE_SERVICES_SPEC` · `SITE_PROGRAMS_SPEC` · `SITE_FAQ_SPEC` · `SITE_REVIEWS_SPEC` · `SITE_TEXTS_SPEC` · `SITE_SECTIONS_SPEC` |

**معنى ذلك عمليًّا:** مورد جديد = **صفّ `Spec` واحد**، لا شاشة جديدة.
> وهذا هو أوّل ما يجب فحصه في أي `PRE-DEVELOPMENT ANALYSIS` قبل اقتراح شاشة:
> **هل يكفي `Spec`؟**

**طبقة الـAPI في الكونسول:** `core/api/ops-api.ts` · `child-api.ts` ·
`inbox-api.ts` · `live-api.ts` · `therapist-profile-api.ts` · `core/ops/day-api.ts`
· `core/resource/*`.

---

## ٣ · المكوّنات المشتركة — `web/shared`

| المكوّن | الاستعمال |
|---|---|
| `ui/family-messages.ts` | **شاشة كاملة تُحمَّل في كلا التطبيقين** على `/communications` |
| `ui/empty-state.ts` · `ui/error-note.ts` · `ui/skeleton.ts` · `ui/spinner.ts` | حالات الفراغ والخطأ والتحميل |
| `ui/date-parts.ts` | إدخال التاريخ — **وكل تاريخ يحمل سنته** بعد عيبٍ كان يخفيها في كل شاشة |
| `format/format.service.ts` · `format.pipes.ts` | العملة والتاريخ والأرقام من بارامترات المركز |
| `i18n/i18n.service.ts` · `translate.pipe.ts` | **كل نصّ واجهة عربيّ عبر ملفّات ترجمة، لا داخل قالب** |
| `icon/icon.ts` · `sprite/icon-sprite.ts` | الأيقونات |
| `toast/toast.ts` · `toast.service.ts` | الإشعارات الطائرة |
| `a11y/route-announcer.ts` · `modal-dialog.ts` · `connectivity.ts` | إتاحة الوصول والاتّصال |
| `config/app-config.ts` | عنوان الـAPI وقت التشغيل |

---

## ٤ · الموقع التعريفي — `site/`

| الملفّ | ماذا فيه |
|---|---|
| `index.html` | الصفحة الرئيسية بكل أقسامها — مشتقّة من ١٢ جدول `site_*` عبر `site-export.sh` |
| `privacy.html` | سياسة الخصوصية |
| `app.js` · `content.js` · `team-gallery.js` · `team-media.js` | روابط البوّابة · التواصل · تبديل اللغة · قائمة الجوال |
| `config.js` | **إعداد النشر** — يُستبدل في كل بيئة، **ولا يحمل سرًّا أبدًا** |
| `styles.css` · `reference.css` · `loader.css` | التنسيق (و`reference.css` مستوحًى من `website/`) |

**بلا إطار وبلا CDN وبلا خطوة بناء.** الطلب الخارجي الوحيد خطّ Cairo من Google Fonts.

> 🔴 **ودرسان أمنيّان على هذا السطح بعينه:**
> 1. الخادم الثابت كان يمرّر `/api/` لكل أصل يخدمه — **بما فيه الموقع، وهو الوحيد
>    على دومين حقيقي** — فصار `POST /api/v1/auth/otp/request` يردّ `200` ومعه
>    `dev_code`: رمز دخول أي وليّ أمر لأي غريب يعرف رقم موبايله، **على الإنترنت
>    المفتوح، إحدى عشرة دقيقة.** والقاعدة كانت مكتوبة في ملفّ nginx **الذي لا
>    يعمل**، لا في الخادم الذي يعمل.
> 2. والمرّة التالية لم يكن المكشوف المسار بل **التعليمات**: `/README.md` و
>    `/CONTENT-AUDIT.md` بـ`200`، و`config.js` — الذي **يُخدَم بالضرورة** — كان في
>    تعليقاته ستّ إشارات إلى `OTP_ECHO` وشرحٌ صريح للثغرة. **الشرح ليس سرًّا بذاته؛
>    هو خريطة** — يوفّر على قارئه السؤال الوحيد الذي يفصل بين من يعرف ومن لا يعرف.
>
> العلاج: **قائمة سماح لأنواع الملفّات في `site.native.mjs`**، **مشتقّة من السكيما
> لا من الصفحة** (لأن `.mp4` لم تكن فيها، وفي `site_team_media` صفّ `VIDEO` حقيقي
> ينتظر النشر). والسبب انتقل إلى `deploy/server/PORTAL-LINK.md` — **حيث لا يُقرأ من
> الخارج**.

---

## ٥ · التصميم والهوية

- `web/*/src/styles/` + `assets/brand/` · RTL أوّلًا · خطّ Cairo.
- `docs/04-frontend-guide.md` هو دليل الهوية البصرية.
- `figma/` يحمل جرد **٤٤ شاشة** في التصميم — و`html/` يحمل نموذجًا بصريًّا
  بـ**١٢ شاشة قابلة للنقر** من النظام القديم. راجع 19 · D-04 و21.
- **ولا رمز تعبيري في كود يُشحن** — سبق أن جعل حزمةً غير قابلة للترجمة برسالة خطأ
  تشير إلى مكان آخر تمامًا.

### CSP — درسٌ يلزم كل من يلمس `angular.json`

أول `Content-Security-Policy` على تطبيق Angular **يكسر أنماطه ويبدو سليمًا**:
البناء الإنتاجي يؤجّل ملفّ الأنماط بـ
`<link rel="stylesheet" media="print" onload="this.media='all'">`، و`script-src`
بلا `'unsafe-inline'` تمنع **معالِج الحدث المضمَّن** — فيبقى الملفّ على
`media="print"` ولا يُطبَّق أبدًا. **٧٦١ قاعدة معطّلة**، والصفحة تبدو صحيحة لأن
Angular يضمّن ٤٥ قاعدة «حرجة» في `<head>`.

العلاج: `"inlineCritical": false` في `web/angular.json` **للتطبيقين** — **لا**
`'unsafe-inline'` في `script-src`. و`style-src` تحتاجها فعلًا ولا مفرّ.
**والسياسة تُقاس في متصفّح لا تُقرأ**، و**البلاغ في الكونسول هو الحكم** — لأن
`onerror` وحده لا يفرّق بين رفض السياسة وفشل الشبكة، و`iframe` مرفوض يطلق `load`
على `about:blank` فيُقرأ نجاحًا.

---

## ٦ · شاشات متشابهة — ولماذا ليست تكرارًا

| المجموعة | الحكم |
|---|---|
| `/appointments` · `/my-day` | ✅ **مقصود** — نفس Spec، صلاحيتان مختلفتان، وكل فعل بحارسه |
| `/reports` (كونسول) · `/children/:id/reports/new` | ✅ قائمة مقابل محرّر |
| `/reports` (بوّابة) · `/reports/:id` (بوّابة) | ✅ قائمة مقابل مفرد |
| `/communications` في التطبيقين | ✅ **مكوّن واحد** في `web/shared` |
| `/billing` في التطبيقين | ✅ منظوران مختلفان لنفس البيانات |
| `/access` · `/settings` · `/catalog` | ⚠️ الحدود بينها ليست واضحة: `/access` يحمل مستندات الموظّفين، و`/settings` يحمل البارامترات، و`/catalog` يحمل `NPS_SURVEYS_SPEC` — **والإجابات عليها في `/satisfaction`**. راجع 19 · D-05 |
| `site/` · `website/` · `html/` | 🔴 **ثلاثة أسطح موقع** — راجع 19 · D-04 |

---

## ٧ · شاشات غائبة مقابل قدرات موجودة

| القدرة الموجودة في القاعدة | شاشة؟ |
|---|---|
| التقييمات (٤ جداول · ٦ دوالّ) | ❌ |
| قائمة الانتظار والعرض (٧ دوالّ) | ❌ |
| الحجز المتكرّر (كورس) | ❌ |
| إجازات المركز `schedule_blocks` | ❌ |
| المرفقات (رفع/نشر عامّ) | ❌ (عدا صورة الطفل) |
| منح حساب بوّابة لأسرة موجودة | ❌ |
| الموافقات — عرض ما وافقت عليه الأسرة | ❌ |
| الخطّ الزمني للحالة `v_case_timeline` | ❌ |
| صحّة النسخ الاحتياطي والصيانة والـSMS | ❌ |
| الأرشيف الورقي | ❌ (`HBH-022`) |
| تصدير ملفّ الطفل للأسرة | ❌ (`HBH-032`) |
| دخول الأخصائي إلى غرفة الاستشارة | ❌ |

راجع [20-missing-incomplete-flow-report](20-missing-incomplete-flow-report.md).

---

## ٨ · الاختبار في هذه الطبقة — حالته

| البند | الحالة |
|---|---|
| `web/portal` اختبارات وحدة | **٣٤** — وتُشغَّل من داخل `hbh-web-portal` وحدها (`node_modules` على القرص مبنيّ لويندوز، فـ`esbuild` يموت في أي حاوية لينكس أخرى) |
| `web/ops` اختبارات وحدة | 🔴 **صفر** (`HBH-047`) |
| `tests/web` | ملفّات فحص واجهة |
| `tests/e2e` | `e1_contract_verify.sh` · `e2_mirror_verify.sh` |

> 🔴 **و`ng test` ردّ صفرًا ثلاث مرات والمتصفّح لم يقم أصلًا**
> (`Cannot start ChromeHeadless — running as root without --no-sandbox`). صفر
> اختبار نُفِّذ، والأمر يقول «نجح». **اقرأ عدد ما نُفِّذ، لا كود الخروج.**
> (`HBH-046`)

---

## OPEN QUESTIONS

| # | السؤال | الأثر |
|---|---|---|
| **OQ-19** | `/access` يجمع إدارة المستخدمين ومستندات الموظّفين الشخصية على شاشة واحدة بحارس `PORTAL.VIEW`. هل يُفصل السطران، ويُرفع الحارس إلى `USER.MANAGE`؟ | 04 · 06 · 18 · C-19 |
| **OQ-20** | هل تُنشر بوّابة الأسرة على دومين عامّ؟ اليوم غير منشورة، وقائمة السماح في الخادم الثابت **مبنيّة على أن الموقع وحده عامّ** | 06 · 11 · 21 |
