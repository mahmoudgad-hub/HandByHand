# 04 — ROLE & PERMISSION MATRIX

**مقروء من `db/seed/0002_rbac.sql` + الهجرة `0091`، ومقابَل بـ`has_permission()` في
السكيما وبحرّاس المسار في `web/ops`.**

---

## ١ · الأدوار الموجودة فعلًا — أربعة، بهذه الأسماء

| Code | الاسم العربي | `user_type` | ملاحظة |
|---|---|---|---|
| `CENTER_ADMIN` | مدير المركز | `STAFF` | ٢٩ صلاحية |
| `RECEPTION` | استقبال | `STAFF` | ١١ صلاحية |
| `THERAPIST` | أخصائي | `STAFF` | ١٦ صلاحية |
| `GUARDIAN` | وليّ أمر | `PORTAL` | ٣ صلاحيات |

> ⚠️ **تصحيح تسمية مهمّ:** لا يوجد `ADMIN` ولا `MANAGER` ولا `RECEPTIONIST` ولا
> `SPECIALIST` ولا `PARENT` في هذه السكيما. أي كود أو وثيقة تستعمل تلك الأسماء
> **لن تطابق شيئًا** — وهذا بالضبط شكل العيب الذي يُقرأ كصلاحية ناقصة.
>
> الأدوار **لكل مركز** (`roles.center_id`) و`is_system_flg = true` للأربعة.
> `UNIQUE (center_id, code)`.

## ٢ · الصلاحيات — ٣٥ رمزًا

| Code | المعنى | مصدرها |
|---|---|---|
| `PORTAL.VIEW` | فتح التطبيق | seed |
| `CHILD.VIEW_ALL` | رؤية كل أطفال المركز | seed |
| `CHILD.CREATE` · `CHILD.EDIT` | إنشاء/تعديل طفل | seed |
| `GUARDIAN.MANAGE` | إدارة أولياء الأمور | seed |
| `APPOINTMENT.BOOK` · `APPOINTMENT.CANCEL` | الحجز والإلغاء | seed |
| `SESSION.START` · `SESSION.COMPLETE` · `SESSION.NOTES.EDIT` | الجلسة وملاحظتها | seed |
| `NOTE.PUBLISH` | نشر ملاحظة للأسرة | seed |
| `PLAN.MANAGE` · `GOAL.MEASURE` | الخطط والقياسات | seed |
| `REPORT.VIEW` · `REPORT.WRITE` · `REPORT.PUBLISH` | التقارير | seed + **`0091`** |
| `ASSESSMENT.RECORD` · `ASSESSMENT.PUBLISH` | التقييمات | seed |
| `ATTACHMENT.UPLOAD` · `ATTACHMENT.PUBLISH` | المرفقات | seed |
| `LIVE.VIEW` | البثّ | seed |
| `BILLING.VIEW` · `BILLING.MANAGE` | الفواتير | seed |
| `REQUEST.SUBMIT` · `REQUEST.MANAGE` | الطلبات | seed |
| `ENROLMENT.MANAGE` | طلبات الالتحاق | seed |
| `NPS.MANAGE` | الاستبيان | seed |
| `OPS.VIEW` | سجلّ التشغيل | seed |
| `CATALOG.MANAGE` | الخدمات والغرف والأنشطة والباقات | seed |
| `STAFF.MANAGE` | الأخصائيون وساعاتهم | seed |
| `USER.MANAGE` | الحسابات وكلمات المرور | seed |
| `SETTINGS.MANAGE` | بارامترات المركز | seed |
| `STAFF.PII` | بيانات الموظّفين الشخصية | seed |
| `SITE.EDIT` · `SITE.PUBLISH` | محتوى الموقع ونشره | seed |

**الصلاحيات عالمية لا مركزية** (`permissions.code` فريد بلا `center_id`) —
و`role_permissions` هو الذي يحملها لكل مركز.

## ٣ · المصفوفة — دور × صلاحية

| الصلاحية | CENTER_ADMIN | RECEPTION | THERAPIST | GUARDIAN |
|---|:--:|:--:|:--:|:--:|
| `PORTAL.VIEW` | ✅ | ✅ | ✅ | ✅ |
| `CHILD.VIEW_ALL` | ✅ | ✅ | ✅ | — |
| `CHILD.CREATE` | ✅ | ✅ | — | — |
| `CHILD.EDIT` | ✅ | ✅ | — | — |
| `GUARDIAN.MANAGE` | ✅ | ✅ | — | — |
| `APPOINTMENT.BOOK` | ✅ | ✅ | — | — |
| `APPOINTMENT.CANCEL` | ✅ | ✅ | — | — |
| `SESSION.START` | ✅ | — | ✅ | — |
| `SESSION.COMPLETE` | ✅ | — | ✅ | — |
| `SESSION.NOTES.EDIT` | **❌ بقصد** | — | ✅ | — |
| `NOTE.PUBLISH` | **❌ بقصد** | — | ✅ | — |
| `PLAN.MANAGE` | ✅ | — | ✅ | — |
| `GOAL.MEASURE` | — | — | ✅ | — |
| `REPORT.VIEW` | ✅ | — | ✅ | ✅ |
| `REPORT.WRITE` | ✅ | — | ✅ | — |
| `REPORT.PUBLISH` | ✅ | — | ✅ | — |
| `ASSESSMENT.RECORD` | ✅ | — | ✅ | — |
| `ASSESSMENT.PUBLISH` | **❌ بقصد** | — | ✅ | — |
| `ATTACHMENT.UPLOAD` | ✅ | ✅ | ✅ | — |
| `ATTACHMENT.PUBLISH` | ✅ | — | ✅ | — |
| `LIVE.VIEW` | ✅ | — | ✅ | — |
| `BILLING.VIEW` | ✅ | ✅ | — | — |
| `BILLING.MANAGE` | ✅ | — | — | — |
| `REQUEST.SUBMIT` | — | — | — | ✅ |
| `REQUEST.MANAGE` | ✅ | ✅ | — | — |
| `ENROLMENT.MANAGE` | ✅ | ✅ | — | — |
| `NPS.MANAGE` | ✅ | — | — | — |
| `OPS.VIEW` | ✅ | — | — | — |
| `CATALOG.MANAGE` | ✅ | — | — | — |
| `STAFF.MANAGE` | ✅ | — | — | — |
| `USER.MANAGE` | ✅ | — | — | — |
| `SETTINGS.MANAGE` | ✅ | — | — | — |
| `STAFF.PII` | ✅ | — | — | — |
| `SITE.EDIT` | ✅ | — | — | — |
| `SITE.PUBLISH` | ✅ | — | — | — |

### الحجوبات المقصودة — وكلّها مسجَّلة بسببها

| الحجب | السبب المكتوب في السكيما |
|---|---|
| `CENTER_ADMIN` بلا `SESSION.NOTES.EDIT` | **الملاحظة السريرية يكتبها من كان في الغرفة.** ولا يكتبها إداري بالنيابة |
| `CENTER_ADMIN` بلا `NOTE.PUBLISH` | من كتب الملاحظة هو من يقرّر أن الأسرة ترى؛ الإداري ينشر **تقارير رسمية** لا ملاحظات غيره |
| `CENTER_ADMIN` بلا `ASSESSMENT.PUBLISH` | الإكلينيكي الذي أدار الأداة هو من يقرّر — نفس طريق الملاحظة |
| `RECEPTION` بلا `OPS.VIEW` | السجلّ يسمّي كل مستخدم وكل مسار لمسه؛ الاستقبال لا دور تشغيلي له |
| `RECEPTION` بلا `STAFF.PII` | **الاستقبال يدير المواعيد لا الملفّات الشخصية** |
| `RECEPTION` بلا `SETTINGS.MANAGE` | العطلة تقرّر أي الأيام تُحجز في **كل** شاشة، والعملة تُلبس كل مبلغ خُزِّن؛ الاستقبال يقرأ ولا يكتب |
| `GUARDIAN` بلا `LIVE.VIEW` | **ملاحظة:** البثّ لوليّ الأمر يمرّ بـ`can_view_live` + موافقة `LIVE_VIEW`، لا برمز صلاحية. فالحجب هنا **ليس تعارضًا** — الرمز لطبقة أخرى من السؤال |

### الفصولات المقصودة — رمزان لا رمز

| الزوج | لماذا فُصلا |
|---|---|
| `SESSION.COMPLETE` \| `SESSION.NOTES.EDIT` | **حقّان لهما رمزان يحتاجان بوّابتين.** بوّابة واحدة تخدم الاثنين تعيد تعريف أيّ المنحتين تتجاهلها بصمت — عيبٌ حقيقي وقع في النظام القديم |
| `SITE.EDIT` \| `SITE.PUBLISH` | كتابة شهادة ووضعها على الإنترنت المفتوح فعلان بعاقبتين. **الاثنان لـ`CENTER_ADMIN` اليوم، والفصل يكلّف صفرًا وهو الفرق بين تغيير سياسة وهجرة لاحقًا** |
| `REPORT.WRITE` \| `REPORT.PUBLISH` | إعادة استعمال `PUBLISH` للصياغة تطوي خطوتين في واحدة |
| `CATALOG.MANAGE` \| `STAFF.MANAGE` | قائمة الأسعار والغرف شيء، ومن يعمل هنا ومتى شيء آخر |
| `USER.MANAGE` \| `STAFF.PII` | من يمنح الأدوار ليس بالضرورة من يقرأ رقم قومي زميله وعنوان بيته. **لو طُويا، لصار كل من يمنح دورًا يقرأ أوراق كل موظّف — ولم يكن أحد ليختار ذلك، بل ليَرِثه** |
| `CATALOG.MANAGE` + `LIVE.VIEW` **معًا** للكاميرات | فمحرّر الكتالوج لا يستطيع توجيه كاميرا إلى غرفة أخرى |

---

## ٤ · مصفوفة الفعل — الميزة × الدور × الفعل

**مقروءة من `has_permission()` في السكيما، لا من الشاشات.**

### الموعد (F-20 · F-21)

| الفعل | CENTER_ADMIN | RECEPTION | THERAPIST | GUARDIAN |
|---|:--:|:--:|:--:|:--:|
| VIEW | ✅ | ✅ | ✅ (أطفاله + كلّهم) | ✅ (طفله) |
| CREATE (حجز) | ✅ | ✅ | — | — |
| CONFIRM / CHECK_IN | ✅ | ✅ | — | — |
| CANCEL | ✅ | ✅ | — | **طلب فقط** (F-40) |
| RESCHEDULE | ✅ | ✅ | — | **طلب فقط** |
| NO_SHOW | ✅ | ✅ | — | — |

> وليّ الأمر **لا يحجز ولا يلغي**. `parent_requests` بأنواعها الثلاثة هي البديل
> المصمَّم — **وإن قُرِّر أن يحجز بنفسه سقط نصفها** (`BL-03`).

### الجلسة (F-25 · F-26)

| الفعل | CENTER_ADMIN | RECEPTION | THERAPIST | GUARDIAN |
|---|:--:|:--:|:--:|:--:|
| START | ✅ | — | ✅ | — |
| VIEW | ✅ | — | ✅ | ✅ (طفله) |
| WRITE NOTE | — | — | ✅ (جلسته) | — |
| PUBLISH NOTE | — | — | ✅ | — |
| COMPLETE / ABORT | ✅ (أي جلسة · `user_type=STAFF`) | — | ✅ (**جلسته هو**) | — |
| WATCH LIVE | ✅ | — | ✅ | ✅ (بموافقة) |

> **الخط:** الإكلينيكي يُغلق عمله هو، والإداري يُغلق عمل أي أحد — تبريران مختلفان
> ففرعان مختلفان. وقبل `0087` كان **أي أخصائي يغلق جلسة أي أخصائي آخر**، لأن
> التجاوز كان مبنيًّا على الصلاحيات وحدها ودور `THERAPIST` يملك الاثنتين.

### الفاتورة (F-34)

| الفعل | CENTER_ADMIN | RECEPTION | THERAPIST | GUARDIAN |
|---|:--:|:--:|:--:|:--:|
| VIEW | ✅ | ✅ | — | ✅ (طفله) |
| CREATE / EDIT LINES | ✅ | — | — | — |
| ISSUE | ✅ | — | — | — |
| ADD PAYMENT | ✅ | — | — | — |
| CANCEL | ✅ | — | — | — |
| SELL PACKAGE | ✅ | — | — | — |
| EXPORT | — | — | — | — (`HBH-032` تصدير ملفّ الطفل غير مبنيّ) |

### طلب الالتحاق (F-08 · F-09)

| الفعل | CENTER_ADMIN | RECEPTION | THERAPIST | GUARDIAN | مجهول |
|---|:--:|:--:|:--:|:--:|:--:|
| SUBMIT | — | — | — | — | ✅ |
| VIEW | ✅ | ✅ | — | **❌ ولا طلبه هو** | — |
| CHANGE STATUS | ✅ | ✅ | — | — | — |
| CONVERT | ✅ | ✅ | — | — | — |

> وليّ الأمر لا يرى طلبه، **لأن «طلبه» غير قابل للإثبات قبل وجود الحساب**.

### التقرير (F-32) · التقييم (F-31)

| الفعل | CENTER_ADMIN | RECEPTION | THERAPIST | GUARDIAN |
|---|:--:|:--:|:--:|:--:|
| WRITE DRAFT | ✅ | — | ✅ | — |
| EDIT DRAFT | ✅ | — | ✅ | — |
| PUBLISH REPORT | ✅ | — | ✅ | — |
| VIEW PUBLISHED | ✅ | — | ✅ | ✅ (طفله) |
| RECORD ASSESSMENT | ✅ | — | ✅ | — (**لا مسار**) |
| PUBLISH ASSESSMENT | — | — | ✅ | — (**لا مسار**) |

### الإدارة (F-05 · F-42 · F-43 · F-44)

| الفعل | CENTER_ADMIN | RECEPTION | THERAPIST |
|---|:--:|:--:|:--:|
| إدارة المستخدمين والأدوار | ✅ | — | — |
| قراءة بيانات الموظّفين الشخصية | ✅ | — | **سجلّه هو فقط** (السياسة تُدخل المالك) |
| كتابة بارامترات المركز | ✅ | — | — |
| قراءتها | ✅ | ✅ | ✅ |
| تحرير الموقع | ✅ | — | — |
| نشر الموقع | ✅ | — | — |
| سجلّ التشغيل والأخطاء | ✅ | — | — |
| إدارة الكتالوج | ✅ | — | — |
| إدارة الأخصائيين وساعاتهم | ✅ | — | — |
| تحرير **ملفّه العامّ** | ✅ | — | ✅ (`can_edit_therapist`) |

---

## ٥ · حرّاس المسار في الكونسول — مقابَلة بالقاعدة

**١٥ حارسًا في `web/ops/src/app/app.routes.ts`، وثلاثة منها لا يطابق القاعدة.**

| المسار | حارس الشاشة | الصلاحية التي تطلبها القاعدة | الحكم |
|---|---|---|---|
| `/inbox` · `/dashboard` · `/access` | `PORTAL.VIEW` | `USER.MANAGE` لأفعال `/access` | ⚠️ **حارس أوسع من الأفعال** — الشاشة تُفتح والأفعال تُرفَض (الشاشة تحسبها بـ`canManage`) |
| `/children` · `/children/:id` · `/children/:id/card` | `CHILD.VIEW_ALL` | نفسها | ✅ |
| `/children/:id/reports/new` · `/:reportId` | `REPORT.WRITE` | `REPORT.WRITE` | ✅ (ومنحتها هشّة — راجع C-02) |
| `/therapists` · `/therapist-services` | `STAFF.MANAGE` | نفسها | ✅ |
| `/therapists/:id/profile` | **لا حارس — بقصد** | `can_edit_therapist` | ✅ مسجَّل بسببه |
| `/rooms` · `/catalog` | `CATALOG.MANAGE` | نفسها | ✅ |
| `/site` · `/site/team` | `SITE.EDIT` | `SITE.EDIT` / `SITE.PUBLISH` | ✅ |
| `/appointments` | `APPOINTMENT.BOOK` | نفسها | ✅ |
| `/my-day` · `/sessions` | `SESSION.START` | نفسها | ✅ |
| `/plans` | `PLAN.MANAGE` | نفسها | ✅ |
| `/reports` | `REPORT.VIEW` | نفسها | ✅ |
| `/billing` | `BILLING.VIEW` | `BILLING.MANAGE` للكتابة | ✅ (القراءة تفتح والكتابة تُفحص في الفعل) |
| `/requests` · `/communications` | `REQUEST.MANAGE` | نفسها | ✅ |
| `/enrolments` | `ENROLMENT.MANAGE` | نفسها | ✅ |
| `/sessions/:id/live` | `LIVE.VIEW` | نفسها | ✅ |
| `/ops-log` | `OPS.VIEW` | نفسها | ✅ |
| **`/settings`** | **`CATALOG.MANAGE`** | **`SETTINGS.MANAGE`** | ⚠️ **مختلفان** — C-13 |
| **`/satisfaction`** | **`CATALOG.MANAGE`** | **`NPS.MANAGE`** | ⚠️ **مختلفان** — C-13 |

> **إخفاء زرّ ليس ضابطًا.** هذه الحرّاس **تحسين تجربة** — التخويل يُفرض في القاعدة
> داخل السياسة. لكن حارسًا يذكر رمزًا **غير** الذي تطلبه القاعدة هو جوابٌ ثانٍ عن
> نفس السؤال، والأضعف هي التي تقرّر يوم يتغيّر أحدهما.

## ٦ · القاعدة المعمارية التي لا تُنقض

> **الصلاحية تقول «ماذا»، ولا تقول «أيّ صفّ» أبدًا.**
> RLS هي التي تجيب النصف الثاني — و`SECURITY DEFINER` هي بالضبط المكان الذي **لا**
> تُطبَّق فيه.

**ثماني دوالّ كانت تأخذ معرّفًا خامًّا وتسأل `has_permission` وحدها، وأُثبت سبعٌ
منها بالاختبار:**

| الدالّة | ما كانت تسمح به عبر المراكز |
|---|---|
| `issue_invoice` | إصدار فاتورة في مركز آخر |
| `decide_request` | **إرسال إشعار بنصّ المهاجم إلى أسرة مركز آخر** |
| `sell_package` | بيع باقة في مركز آخر |
| `publish_session_note` | نشر ملاحظة سريرية لمركز آخر |
| `grant_consent` | **تقرير من يشاهد طفلًا أثناء جلسته** |
| `withdraw_consent` | سحب موافقة في مركز آخر |
| `set_password` | **استيلاء على حساب موظّف في مركز آخر** |

**الترتيب الملزم داخل كل دالّة:**
`اقرأ الصفّ ← هل هو موجود ← هل هو لي ← هل يحقّ لي ← هل الحالة تسمح ← ثم اكتب`

والفحص الآلي في `tests/db/p00_verify.sql` **يمنع عودة الصنف كلّه**، و
`assert_same_center` و`assert_center_argument` (`0099` · `0101` · `0102`) هما
الأداتان.

---

## ٧ · تعديل الصلاحيات في التشغيل

`PUT /api/v1/roles/{code}/permissions` → `set_role_permissions(code, codes[])` —
تُطفئ ما لم يبقَ، وتعيد ما أُلغي، وتمنح ما لم يكن. و`guard_last_admin` +
حسبةٌ في الشاشة تمنعان إسقاط `USER.MANAGE` عن **آخر** دور يملكها.
**فالمصفوفة أعلاه هي القيم المبذورة، لا القيم الحالية على قاعدة مشتغَّلة.**
> المرجع الحيّ: `GET /api/v1/roles` و`GET /api/v1/permissions` وشاشة `/access`.

---

## OPEN QUESTIONS

| # | السؤال | الأثر |
|---|---|---|
| **OQ-12** | هل يُنشأ دور خامس (مثل `SUPERVISOR` أو `ACCOUNTANT`)؟ الأدوار `is_system_flg` والشاشة لا تصنع أدوارًا جديدة — إنشاء دور اليوم **هجرة** | 04 · F-05 · F-06 |
| **OQ-13** | `RECEPTION` بلا `BILLING.MANAGE` — من يستقبل الدفعة النقدية عند الباب فعلًا؟ | F-34 · FL-10 |
| **OQ-14** | هل `THERAPIST` يجب أن يرى **كل** أطفال المركز (`CHILD.VIEW_ALL`) أم أطفال `caseload` وحدهم؟ الرمز اليوم يعني الأولى، والتبرير المكتوب «ليغطّي زميلًا» | F-10 · F-18 · سلّم الرؤية |
