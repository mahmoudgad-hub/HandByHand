# عقد الدفعة ١١ — للـ API

<!-- doc-owner -->
> **المالك:** Database Developer — **هو وحده من يكتب في هذه الوثيقة.**
> لاحظت خطأً؟ **راسله ولا تصلحه بنفسك** — راجع [OWNERS.md](OWNERS.md).
<!-- doc-owner -->


الهجرات **0022 · 0023 · 0024 · 0025 · 0029** مطبَّقة على القاعدة المشتركة، ومجموعة القبول
`tests/db/p11_verify.sql` تطبع **`PHASE 11 ACCEPTED`** بـ **١٠٠ فحص · ٠ فشل**.

القواعد كما هي: كل معاملة تبدأ بـ `SET LOCAL hbh.user_id = $1`، والاتصال بـ `hbh_app`،
والصلاحيات تُفحص في الداتابيز لا في Go.

---

## ١. الحجز المتكرّر

```sql
SELECT * FROM hbh.book_recurring(
  p_center_id, p_branch_id, p_child_id, p_therapist_id, p_room_id, p_service_id,
  p_first_start timestamptz, p_first_end timestamptz, p_occurrences smallint,
  p_interval_days integer DEFAULT 7);
```

**ترجع صفًّا لكل أسبوع** — لا قيمة واحدة:

| العمود | |
|---|---|
| `occurrence` | ترتيب الأسبوع (١، ٢، ٣ …) |
| `starts_at` | موعد ذلك الأسبوع |
| `ok` | حُجز أم لا |
| `reason` | `OK` · `CENTER_CLOSED` · `THERAPIST_OFF` · `ROOM_BUSY` · `CHILD_BUSY` · `THERAPIST_BUSY` · `OUTSIDE_HOURS` |
| `appointment_id` | المعرّف عند النجاح، وإلا `NULL` |

**والـ API يعرض كل الصفوف.** أربعة أسابيع فيها عطلة تُنتج ثلاثة حجوزات ورفضًا واحدًا.
اختزال ذلك إلى «نجح/فشل» يكذب في الاتجاهين — تعيد HTTP 207 أو 200 مع المصفوفة كاملة،
والشاشة تقول للاستقبال أي أسبوع لم يُحجز ولماذا.

```sql
SELECT hbh.cancel_recurrence(p_group_id bigint, p_from timestamptz, p_reason text);
```
ترجع عدد ما أُلغي. `p_from` تحمي الماضي: ما وقع لا يُلغى. **الرفض `HB101`** عند غياب
السبب أو الصلاحية.

---

## ٢. قائمة الانتظار

```sql
SELECT hbh.add_to_waiting_list(
  p_child_id, p_service_id, p_therapist_id DEFAULT NULL, p_priority smallint DEFAULT 5,
  p_from date DEFAULT current_date, p_to date DEFAULT NULL,
  p_weekdays smallint[] DEFAULT NULL,       -- ١=الاثنين … ٧=الأحد
  p_time_from time DEFAULT NULL, p_time_to time DEFAULT NULL);
```

`p_weekdays` والمدى الزمني هما **نافذة الأسرة**. أسرة صباحية ليست مرشَّحة لموعد بعد
الظهر مهما طال انتظارها — وهذا مُختبَر.

```sql
SELECT * FROM hbh.waiting_candidates(p_center_id, p_service_id,
                                     p_starts_at, p_ends_at, p_therapist_id, p_limit);
```
مرتَّبة بـ `priority` ثم `created_at`. تُستدعى عند إلغاء موعد لعرض من يُنادى.

```sql
SELECT hbh.offer_slot(p_wait_id, p_appointment_id);   -- ترجع وقت انتهاء المهلة
SELECT hbh.accept_offer(p_wait_id);                   -- boolean
SELECT hbh.release_expired_offers();                  -- ترجع العدد
```
المهلة من `WAITLIST_OFFER_HOURS` (٤٨ افتراضًا). **`HB102`** عند قبول عرض منتهٍ أو مقبول
سلفًا، و**`HB100`** عند انتقال حالة غير مشروع. `release_expired_offers` تناديها
`run_maintenance` تلقائيًا — لا تكرّرها في Go.

الحالات: `WAITING → OFFERED → BOOKED` · `OFFERED → WAITING` (انتهت المهلة) ·
`WAITING|OFFERED → CANCELLED`.

---

## ٣. التقييمات

```sql
SELECT hbh.record_assessment(p_child_id, p_instrument_id, p_therapist_id,
                             p_assessed_on date, p_session_id, p_summary_ar);
SELECT hbh.publish_assessment(p_assessment_id);
```

سلّم الرؤية نفسه: `DRAFT → COMPLETED → PUBLISHED`، وولي الأمر لا يرى إلا `PUBLISHED`
**ولا يرى درجات البنود إطلاقًا** — تلك تفصيل عمل الأخصائي.

- `ASSESSMENT.RECORD` و`ASSESSMENT.PUBLISH` صلاحيتان منفصلتان — **`HB111`**.
- نشر مسوّدة مرفوض — **`HB110`**.
- المنشور **مجمَّد**: أي تعديل على الرأس أو على درجات البنود مرفوض — **`HB112`**.
- درجة بند تتجاوز حدّ الأداة مرفوضة — **`HB113`**.
- `raw_score` **مشتقّة** من البنود عند وجودها. لا ترسلها.
- النشر يولّد إشعارًا `ASSESSMENT_PUBLISHED` تلقائيًا.

---

## ٤. المرفقات

```sql
SELECT hbh.attach_file(p_owner_kind, p_owner_id, p_child_id,
                       p_file_name, p_mime_type, p_content bytea, p_caption_ar);
SELECT hbh.publish_attachment(p_attachment_id);
```

`owner_kind` ∈ `CHILD` · `SESSION` · `REPORT` · `ASSESSMENT` · `INVOICE` · `ENROLMENT` · `PLAN`.

**أربع قواعد تُبنى عليها الشاشة:**

1. **الفيديو مرفوض — قيدًا لا سياسة.** `HB122` من الدالة، و`23514` من القيد مباشرة.
   النظام يبثّ حيًّا ولا يسجّل. لا تعرض زرّ رفع فيديو أصلًا.
2. **الحدّ من `MAX_ATTACHMENT_MB`** — `HB121`. اقرأه من `sys_params` واعرضه قبل الرفع
   لا بعده.
3. **الملف يولد `INTERNAL`.** النشر لولي الأمر فعل منفصل بصلاحية `ATTACHMENT.PUBLISH`.
4. **البايتات تُكتب مرّة.** أي محاولة استبدال محتوى مرفق قائم مرفوضة — `HB120`. الاستبدال
   يعني رفع مرفق جديد.

**وللقوائم استعمل `hbh.v_attachment_index` — لا الجدول.** فيه البيانات الوصفية بلا
`content`. `SELECT * FROM hbh.attachments` في شاشة قائمة يبثّ كل ملف تعرضه.

التنزيل يقرأ `content` لصفّ **واحد** بمعرّفه، ويسجّل القراءة كما تُسجَّل قراءة تقرير.

---

## ٥. النسخ الاحتياطي والأرشفة — للتشغيل لا للـ API

`hbh.backup_runs` و`hbh.audit_log_archive` **بلا `GRANT` لـ `hbh_app`** عمدًا. لا تلمسهما
من Go.
الشيء الوحيد الذي يصل للتطبيق: **`hbh.backup_health()`** — دالة `SECURITY DEFINER` محكومة
بـ `OPS.VIEW`. التفاصيل في الملحق آخر هذه الوثيقة. والجدولان يبقيان بلا `GRANT`.
`scripts/backup.sh` **يستعيد كل نسخة يأخذها** إلى قاعدة مؤقتة ويعدّ جداولها قبل أن
يسمّيها نسخة احتياطية.

---

## ملخّص رموز الخطأ الجديدة

| الرمز | المعنى |
|---|---|
| `HB100` | انتقال حالة غير مشروع في قائمة الانتظار |
| `HB101` | لا صلاحية / سبب ناقص في الحجز المتكرّر |
| `HB102` | عرض منتهٍ أو مقبول سلفًا |
| `HB110` | نشر تقييم ليس `COMPLETED` |
| `HB111` | لا صلاحية تسجيل أو نشر تقييم |
| `HB112` | تعديل تقييم منشور |
| `HB113` | درجة بند تتجاوز حدّ الأداة |
| `HB120` | لا صلاحية على المرفق / محاولة استبدال محتواه |
| `HB121` | الملف أكبر من الحدّ |
| `HB122` | نوع وسائط مرفوض (الفيديو) |
| `HB130` | خلل في الأرشفة (تشغيلي، لا يصل للـ API) |

---

## ملحق — `hbh.backup_health()` (هجرة **0029**، مطبَّقة)

```sql
SELECT * FROM hbh.backup_health();
```

| العمود | |
|---|---|
| `last_verified_at` | آخر نسخة **تحقّق منها الاستعادة** |
| `last_attempt_at` | آخر محاولة، نجحت أو لا |
| `hours_since_verified` | بالساعات، منزلة عشرية واحدة |
| `failures_this_week` | فشل آخر سبعة أيام |
| `is_stale` | تجاوزت `BACKUP_MAX_AGE_HOURS` (٣٦ افتراضًا) |
| `never_verified` | **صحيحة على قاعدة لم تنجح فيها نسخة قط** — وهي الحالة التي يجب أن تصرخ |

**البوّابة:** `OPS.VIEW`، و**تفشل مقفولة**: بلا هوية = `HB130`، لا «الجواب العام».
والاستقبال والأخصائي مرفوضان — مُختبَران في مجموعة `ops`.

**وما لا تُرجعه عمدًا:** `file_name` و`sha256_hex` و`detail`. اسم الـ dump ومساره يصفان
نظام ملفات الخادم، و`detail` يحمل نصّ خطأ `pg_restore` وقد يقتبس قيمة صفّ. الشاشة التي
تقول «آخر نسخة موثّقة من ٤ ساعات» لا تحتاج أيًّا منها. إضافتها لاحقًا تعني تعديل هذه
الدالة — وهي بالضبط المراجعة التي يجب أن تحدث.

**و`hbh.backup_runs` نفسه يبقى بلا `GRANT`** — حتى للمالك. الفحص موجود في المجموعة.
