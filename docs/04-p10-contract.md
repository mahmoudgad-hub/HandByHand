# 04 — عقد المرحلة العاشرة للـ API

<!-- doc-owner -->
> **المالك:** Database Developer — **هو وحده من يكتب في هذه الوثيقة.**
> لاحظت خطأً؟ **راسله ولا تصلحه بنفسك** — راجع [OWNERS.md](OWNERS.md).
<!-- doc-owner -->


ثلاث ميزات جاهزة في قاعدة البيانات ومقبولة بـ **٩١ فحصًا · ٠ فشل**
(`bash scripts/db.sh verify 10`). المهاجرات **0018 · 0019 · 0020**.

> الرقم المتاح التالي لأي مهاجرة جديدة: **0022**.

---

## ١. طلب الالتحاق — أول مسار **بلا مصادقة**

نموذج على شاشة دخول وليّ الأمر، لأسرة لا حساب لها بعد.

### الإرسال (عام، بلا توكن)

```sql
SELECT * FROM hbh.submit_enrolment(
  p_center_code       => 'HBH',
  p_parent_name_ar    => $1,
  p_parent_mobile     => $2,
  p_child_name_ar     => $3,
  p_child_birth_date  => $4,
  p_child_gender      => $5,      -- 'M' أو 'F'
  p_parent_email      => $6,
  p_relationship_code => $7,      -- FATHER · MOTHER · GUARDIAN
  p_main_concern_ar   => $8,
  p_preferred_service_id   => $9,
  p_address_ar             => $10,
  p_preferred_contact_time => $11,
  p_previous_therapy_ar    => $12,
  p_source_code       => 'WEB',
  p_client_ip         => $13);
```

ترجع `(ok, reason, application_no)`.

| `reason` | المعنى | الرد المقترح |
|---|---|---|
| `OK` | نجح | ٢٠١ + رقم الطلب |
| `TOO_MANY_FOR_MOBILE` | تجاوز الحدّ اليومي لهذا الجوّال | ٤٢٩ |
| `TOO_MANY_FOR_IP` | تجاوز الحدّ الساعي لهذا العنوان | ٤٢٩ |
| `REJECTED` | كود مركز غير معروف | ٤٠٠ برسالة عامة |

**لا تُمرِّر `reason` كما هو للشاشة.** `REJECTED` غامضة عمدًا حتى لا يعرف مجهولٌ أي أكواد
مراكز موجودة، وتمييز `TOO_MANY_FOR_MOBILE` عن `TOO_MANY_FOR_IP` في الواجهة يكشف أن الرقم
معروف. الرسالة للمستخدم واحدة؛ التفريق للسجلّ.

**المسار عام تمامًا:** `hbh.current_user_id()` تساوي NULL، ومجهول الهوية **لا يقرأ ولا صفًّا**
من `enrolment_applications` ولا يستطيع الإدراج مباشرة (`42501`). لا تفتح أي نقطة قراءة عامة.

**حدّان قابلان للضبط** من `hbh.sys_params`: `ENROLMENT_MAX_PER_MOBILE_DAY` (٣) و
`ENROLMENT_MAX_PER_IP_HOUR` (١٠). مرّر `p_client_ip` وإلا عُطِّل الحدّ الثاني.

### الطابور والتحويل (يحتاج `ENROLMENT.MANAGE` — لدى `CENTER_ADMIN` و`RECEPTION`)

قراءة: `SELECT ... FROM hbh.enrolment_applications` — السياسة تتكفّل بالتصفية.
تغيير الحالة: `UPDATE` عادي؛ الآلة تفرض الشرعية وترفع **`HB090`**.

```
NEW → CONTACTED → ASSESSMENT_BOOKED → ENROLLED
 └────────────→ REJECTED · DUPLICATE
```

```sql
SELECT * FROM hbh.convert_enrolment($1, $2);  -- (guardian_id, child_id, child_no)
```

- تحتاج `ENROLMENT.MANAGE` وإلا **`HB092`**.
- ترفض إن كانت الحالة `NEW` أو `ENROLLED` بـ **`HB091`** — لا بدّ من التواصل أولًا.
- **تُعيد استعمال وليّ الأمر** إن كان الجوّال معروفًا؛ لا تُنشئ نسخة ثانية.
- **لا ترفع `can_view_live_flg`** — مشاهدة طفل تحتاج موافقة مسجَّلة (D-24).

---

## ٢. استبيان الرضا — الإعداد بيانات

### في البوابة

```sql
SELECT * FROM hbh.nps_due();
```

عند كل تحميل للصفحة. ترجع **صفر أو صفًّا واحدًا**:
`(survey_id, code, question_ar, followup_question_ar, context_kind, context_id)`.
بلا هوية ترجع صفرًا. النصوص من قاعدة البيانات — **لا تكتب السؤال في الواجهة**.

```sql
SELECT hbh.submit_nps($survey_id, $score::smallint, $comment, $context_kind, $context_id, $ip);
SELECT hbh.skip_nps($survey_id, $context_kind, $context_id);
```

- `score` من ٠ إلى ١٠ وإلا **`HB093`**.
- **`skip_nps` إلزامية عند الإغلاق.** بدونها يعود السؤال مع كل تحديث للشاشة.
- الخانة الحرّة تحت الرقم اختيارية.

### في الإدارة (يحتاج `NPS.MANAGE` — لدى `CENTER_ADMIN` وحده)

`hbh.nps_surveys` قابل للـ `INSERT`/`UPDATE` مباشرة. الأعمدة القابلة للتغيير في أي وقت:
`question_ar` · `followup_question_ar` · `audience` · `trigger_kind` · `period_days` ·
`action_code` · `cooldown_days` · `starts_on` · `ends_on` · `active_flg`.

- `trigger_kind = 'PERIOD'` ← يلزم `period_days` و`action_code` فارغ.
- `trigger_kind = 'ACTION'` ← يلزم `action_code` و`period_days` فارغ.
- خلاف ذلك **`23514`** — استبيان بلا شرط إطلاق لا يُطلَق أبدًا بصمت.
- `action_code` ∈ `SESSION_COMPLETED` · `REPORT_PUBLISHED` · `INVOICE_PAID` · `FIRST_LOGIN`.

**لوحة النتائج:** `SELECT * FROM hbh.v_nps_summary` — فيها
`answered_cnt · skipped_cnt · promoters · passives · detractors · nps · mean_score`.

⚠️ **اعرض `nps` لا `mean_score`.** هما رقمان مختلفان: في اختبار القبول `nps = 25` بينما
`mean_score = 7.25`. المتوسّط ليس NPS.

---

## ٣. سجلّ التشغيل — يُكتب من الوسيط

نداء واحد في نهاية كل طلب، **بعد** تحديد الرد:

```sql
SELECT hbh.log_request(
  p_method => $1, p_route => $2, p_status_code => $3::smallint, p_duration_ms => $4,
  p_path => $5, p_request_id => $6, p_client_ip => $7, p_user_agent => $8,
  p_error_code => $9, p_error_message => $10, p_detail => $11::jsonb);
```

**خمس نقاط غير قابلة للتفاوض:**

1. **`route` قالب، `path` فعليّ.** `/api/children/{id}` مقابل `/api/children/42`.
   التجميع على `path` يعطي صفًّا لكل طفل ولا يقول أي مدخل بطيء.
2. **كل رد ≥ ٤٠٠ يلزمه `error_code`** وإلا **`23514`**. استعمل رمز `HB0xx` إن جاء من
   قاعدة البيانات، أو رمزك الداخلي.
3. **لا بيانات شخصية في `error_message`.** اسم طفل في أثر خطأ يضع بيانات سريرية في جدول
   تعرضه شاشة التشغيل. رمز ورسالة تقنية قصيرة، والتفاصيل المهيكلة في `p_detail`.
4. **الدالة لا ترفع أبدًا.** فشل التسجيل تحذير في لوج الخادم، فلا يتحوّل طلب **نجح** إلى
   طلب فشل. نادِها كما هي ولا تلفّها في `try` يبتلع النتيجة.
5. **الهوية تُقرأ من الطلب** — لا تمرّرها. مجهول الهوية يُسجَّل بـ `user_id = NULL`، وهذا
   مقصود ومُختبَر.

### شاشة التشغيل (تحتاج `OPS.VIEW` — لدى `CENTER_ADMIN` وحده)

| العرض | ما فيه |
|---|---|
| `hbh.v_api_health` | لكل `route` + `method`: `calls · p50_ms · p95_ms · max_ms · error_pct · last_error_at` |
| `hbh.v_recent_errors` | آخر الأخطاء كاملة بالرمز والرسالة و`detail` |
| `hbh.v_user_activity` | من دخل، كم طلبًا، كم يومًا نشطًا، وآخر ظهور وآخر عنوان |

الاحتفاظ: `REQUEST_LOG_RETENTION_DAYS` (٣٠) وينظّفه `hbh.run_maintenance`.
**`hbh.audit_log` لا يُحذف** — قرار امتثال يخصّ المالك.

---

## ملاحظتان تخصّان الشغل المشترك

- **`db.sh reset` ممنوع** على هذه القاعدة: جلستان تعملان عليها، والهدم سحب السكيما من تحت
  عملية كانت تطبّق مهاجراتها. `migrate` فقط.
- **الرفض بعد فتح الكتابة صار «صفر صفوف» لا `42501`.** المنحة موجودة والسياسة هي التي
  تقرّر، فالتحديث الممنوع يُبلغ عن النجاح ويُغيّر لا شيء. تحقّق من عدد الصفوف المتأثّرة قبل
  أن ترد ٢٠٠ على تعديل لم يحدث.
