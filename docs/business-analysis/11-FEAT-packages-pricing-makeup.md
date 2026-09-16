# FEAT — الباقات · الأسعار · التعويض · الدفع بالحصة

**المالك:** `Business analysis` · **التاريخ:** 2026-09-12 · **الحالة:** 🟢 تحليل مكتمل · البناء بعد المرحلة ١' في [`10` §9](10-FEAT-unified-customer-journey.md)

**المرجع:** تكليف المالك §7–§21 و§24 · استمارته المملوءة (أ.١ الأسعار · أ.٣ الباقات · أ.٤ سعر الجلسة) · [`06-owner-answers.md`](06-owner-answers.md) §ثانيًا · قرارات `OD-12`…`OD-17` و`OD-21` في [`10` §3](10-FEAT-unified-customer-journey.md). · وقرارات المساء `OD-25`…`OD-34` (§14–§16).

> **ما ليس هنا:** **الكورسات** خارج النطاق بقرار مكتوب · و`BL-37 ج` (القسط المتأخّر — السلوك القائم يستمرّ: إشعار لا حجب). الجلسات الخارجية في §16 والتقسيط في §15 بعد قرارات الليل (`OD-32`…`OD-34`).

---

# ٠ — ما هو مبنيّ · **ولا مهمّة له**

| المكوّن | الدليل | يُعاد استعماله كـ |
|---|---|---|
| `service_packages` (كود · اسم · عدد · سعر · صلاحية · تدقيق كامل) | `0008:50` | **القالب** — بعد إخراج `service_id` منه |
| `child_packages` (نسخة الشراء: `purchased_on · expires_on · sessions_total · price_amt · status`) | `0008:77` | **الاشتراك** — والنسخة هي طبقة التجاوز الخاصّ بالحالة |
| `package_ledger` مضاف-فقط (`delta · balance_after · reason · session_id`) | `0008:116` | دفتر الرصيد — يُضاف إليه `service_id` |
| `sell_package` (`BILLING.MANAGE` · نفس المركز `0101`) | | يُوسَّع ليقرأ النسخة ويكتب أسطر الخدمات |
| `consume_package_session` (`FOR UPDATE` · `HB051` · ترجع المتبقّي · **بلا منادٍ** — C-01) | `0008:473` | يُنادى من مشغّل الموعد · ويأخذ `service_id` |
| `expire_packages` في `run_maintenance` (تعلّم `EXPIRED` وتكتب `EXPIRY` في الدفتر) | `0008:537` · `0094` | كما هي + إشعار قرب الانتهاء |
| `book_recurring` · `cancel_recurrence` · `recurrence_group_id` (`HB101`/`HB102`) — بلا مسار | `0022` | **التثبيت** |
| `rescheduled_from` (`0088`) · `parent_requests` `RESCHEDULE·CANCEL` · `decide_request` | | الاعتذار وإعادة الجدولة |
| `invoice_lines.unit_amt · service_id · child_package_id · session_id` | `0008:194` | تجميد السعر |
| `sys_params` مُنمَّط · لكل مركز · `SETTINGS.MANAGE` · مُدقَّق | `0058` | كل بارامتر أدناه صفّ |
| البوّابة `billing`: باقات · انتهاء · متبقّ · فواتير · مستحق | `web/portal/features/billing` | اللوحة تُوسَّع |
| الكونسول `resource-screen` بـ`PACKAGES_SPEC` | discovery 02 | شاشة القالب |

**والفجوة المبنيّة قبل التكليف:** **C-01** — `close_session` لا تخصم. الرصيد لا يُخصم أبدًا اليوم. **تُصلَح هنا** (`PK-06`).

---

# ١ — نموذج التسعير كما وصفه المالك · **المرجع الدائم**

من الاستمارة أ.١ (2026-09-07)، مقروءة في `06` §ثانيًا:

| الخدمة | داخل الباقة | فرديًّا | المدّة |
|---|---|---|---|
| تخاطب · تكامل حسّي · وظيفي · أكاديمي · سيكوموتور · Oral motor/OPT · رسم | **٤٠٠** | **٥٠٠** «دون ميزة تثبيت المواعيد» | ٤٥–٥٠ |
| موسيقى | **٦٠٠** | **٨٠٠** | ٣٠–٣٥ |
| قرآن | **٢٥٠** | **٣٠٠** | ٤٥–٥٠ |
| الاستشارة الأولى | — | **٦٠٠** (موسيقى ٨٠٠) | ٤٥–٦٠ |
| تقييم واختبارات | — | **١٠٠٠** · تقرير خلال ٣ أيام عمل | ٦٠–٩٠ |
| الاستشارات النفسية والأسرية · الإرشاد المهني · CBT بأنواعه | — | **٦٠٠** | ٥٠–٦٠ |

**والباقة:** شهرية **٣٠ يومًا** · العدد = التكرار الأسبوعي × الأسابيع (٣ أسبوعيًّا → ١٢) · **تشتري تثبيت المواعيد وضمانها** · التعويض **حتى ٢٠٪ للأقلّ** بإخطار **٢٤ ساعة** داخل الشهر · وخصم الظروف «٣٠٠ و٣٥٠ على نطاق المساعدة».

**فالفرق بين السعرين ليس خصمًا بل ميزة** — والباقة تشتري خانة محجوزة (`06` §ثانيًا). وهذا ما يجعل `FIXED_APPOINTMENT_FLG` جوهر الباقة لا خيارًا.

---

# ٢ — البنية · **ثلاث طبقات، اثنتان منها قائمتان**

```
service_packages  ─── القالب (التعريف · الاسم · الحالة DRAFT/ACTIVE/INACTIVE/ARCHIVED)
      │ 1:N
package_versions  ─── النسخة (السعر · الصلاحية · التجميد · التجديد · التثبيت · سياسة التعويض · سريان)   [جديد]
      │ 1:N
package_version_services ─── الخدمة داخل النسخة (عدد · مدّة · في الأسبوع · تعويض مسموح · نوع الأخصائي)  [جديد]
      
child_packages    ─── الاشتراك (قائم) + package_version_id + آلة حالة + تاريخ
      │ 1:N
child_package_services ─── رصيد كل خدمة (purchased · used · returned)                                    [جديد]
      │
package_ledger    ─── الدفتر (قائم) + service_id
appointments.makeup_for_appointment_id ─── الرابط الوحيد المكتوب للتعويض؛ الحدّ والمستعمَل مشتقّان (§17.2)          [عمود]
limit_overrides (جدول واحد · قوس حصري من مفاتيح حقيقية · ثلاثة حدود) ─── التجاوزات المسبَّبة بمدّة سريان — المعماري ١.٧ المُراجَع (§17.4) [جديد]
```

**لماذا نسخة والاشتراك ينسخ أصلًا؟** لأن النسخة **تُشار إليها** (FK) والتدقيق لا يُشار إليه؛ ولأن قائمة الخدمات داخل الباقة لا تُنسخ إلى صفّ واحد. **ولماذا يبقى النسخ على الاشتراك؟** لأنه طبقة **التجاوز الخاصّ بالحالة** الذي طلبه التكليف §8 — الاشتراك يبدأ نسخةً من النسخة ويُعدَّل بصلاحية وسبب.

**`service_packages.service_id` يخرج على خطوتين** (القارئ أولًا): `PACKAGES_SPEC` والـCRUD وبذور الاختبار تتوقّف عن قراءته، ثم يُسقَط.

---

# ٣ — آلة حالة الاشتراك · **`child_packages.status`**

```
PENDING_PAYMENT ──► ACTIVE ⇄ FROZEN
       │              │
       │              ├──► EXHAUSTED   (آخر رصيد استُهلك — الاسم القائم، = COMPLETED في التكليف)
       │              ├──► EXPIRED     (الصيانة، expires_on مضى)
       │              └──► CANCELLED
       └──► CANCELLED
```

| القاعدة | التنفيذ |
|---|---|
| `legal_package_transition(from, to)` + `package_status_history` | مشغّل — **قاعدة ٥**: لا تحديث حرّ، ولا من مدير المركز |
| `PENDING_PAYMENT → ACTIVE` **بالسداد الكامل** لفاتورة الاشتراك | مشغّل على `payments` — **`INSERT OR UPDATE`** (درس `0090`: صفّ يُدرَج بالحالة النهائية) · بجملة مستقلّة |
| `ACTIVE → FROZEN` يتطلّب `allow_freeze_flg` على النسخة، ومجموع أيام التجميد ≤ `freeze_days` | دالّة `freeze_package(id, from, to, reason)` |
| `FROZEN → ACTIVE` يمدّد `expires_on` بأيام التجميد الفعلية (**افتراض `10` §4** — يُنقَض إن شاء المالك) | نفس الدالّة عند الفكّ |
| `NEAR_EXPIRY` **ليست حالة** | إشعار من الصيانة حين `expires_on - today <= PACKAGE_NEAR_EXPIRY_DAYS` |
| `EXHAUSTED` تضعها `consume_package_session` حين يصير مجموع المتبقّي صفرًا | قائمة — تصير مُنادَاة (C-01) |
| **الاستهلاك لا يسأل عن الدفع** — كان كذلك ومختبَرًا (`BL-37 ج`) | يبقى: `PENDING_PAYMENT` **لا** تُستهلك لأن الحجز لا يُنشأ قبل `ACTIVE`… **إلّا** إذا قرّر المالك السماح بالتثبيت قبل الدفع → `BL-53` |

---

# ٤ — الدفع بالحصة · **نموذج الفوترة على الخدمة**

| على `services` | القيم | الافتراضي |
|---|---|---|
| `billing_model` | `PACKAGE_ONLY · SINGLE_SESSION_ONLY · PACKAGE_AND_SINGLE_SESSION` | `PACKAGE_AND_SINGLE_SESSION` |
| `allow_parent_self_booking_flg` | | `false` — و`true` لخدمة الاستشارة (`OD-06`) |
| `allow_parent_reschedule_flg` · `allow_parent_cancel_flg` | تغيير **مباشر**؛ الطلب عبر `parent_requests` متاح دائمًا | `false` |

**`service_prices`** (جديد): `price_id · center_id · service_id · price_kind ∈ {PACKAGE, SINGLE} · amount · currency_code · effective_from · effective_to · created_by …` + قيد استبعاد **لا يسمح بسعرين من نفس النوع لنفس الخدمة يتداخلان زمنيًّا** (`EXCLUDE USING gist` — نفس أداة المواعيد) + تدقيق.

**`current_price(service_id, kind, at)`** دالّة واحدة يقرؤها الجميع. **و`add_invoice_line` تتغيّر:** `p_unit_amt` **لا يُقبل من المنادي** حين يُعطى `service_id` — يُقرأ من `current_price(SINGLE)`؛ ويُقبل **فقط** مع `BILLING.PRICE_OVERRIDE` + `p_override_reason` إلزامي، ويُسجَّل `list_amt` (سعر الكتالوج) بجوار `unit_amt` فيظهر الخصم رقمًا لا تخمينًا. **وسطر بلا `service_id`** (بند حرّ) يبقى كما اليوم بـ`BILLING.MANAGE`.

**الجلسة المفردة:** لا رصيد · لا انتهاء · السعر مجمَّد على السطر وقت الحجز (قائم) · سياسة الإلغاء **`SINGLE_CANCELLATION_NOTICE_HOURS`** مستقلّة عن الباقة.

---

# ٥ — التعويض · **`OD-13` · `OD-14` · `OD-15`**

## ٥.١ · السياسة على النسخة

| حقل `package_versions` | القيم | السياسة الحالية |
|---|---|---|
| `makeup_policy_type` | `NONE · FIXED · PERCENTAGE` | `PERCENTAGE` |
| `makeup_value` | عدد أو نسبة | `20` |
| `makeup_rounding` | `FLOOR · CEIL · ROUND` | `FLOOR` |
| `makeup_notice_hours` | ساعات قبل `starts_at` | `24` |
| `makeup_expiry_rule` | `PACKAGE_END_DATE · FIXED_DAYS` | `PACKAGE_END_DATE` |

**الحدّ المحسوب** = `FLOOR(12 × 20%)` = **٢**. يُحسب عند تفعيل الاشتراك ويُخزَّن في `makeup_credits.granted` — **لا يُعاد حسابه** إذا تغيّرت النسخة (النسخة لا تتغيّر أصلًا).

## ٥.٢ · التعويض ليس رصيدًا

`8 Purchased + 2 Makeup ≠ 10`. الـ٨ في `child_package_services.purchased`، والـ٢ في `makeup_credits.granted` — **جدولان**، ولا يدخل التعويض `package_ledger` كـ`delta` موجب. الموعد التعويضي يحمل `makeup_credit_id` ويستهلك من رصيد **الخدمة نفسها** التي اعتُذر عنها.

## ٥.٣ · ماذا يحدث عند كل انتقال — **الجدول الذي يُنفَّذ في المشغّل**

| الحدث على موعد مربوط باشتراك | `cancel_kind` (مشتقّ) | الرصيد | التعويض |
|---|---|---|---|
| `COMPLETED` | — | **يُستهلك** `-1` للخدمة | — |
| `NO_SHOW` | — | **يُستهلك** | لا |
| وليّ الأمر ألغى **قبل** `makeup_notice_hours` | `PARENT_ON_TIME` | لا يُستهلك · يُرجَع للرصيد المتاح للحجز | **يُمنح ائتمان** إن `used < granted`، وإلّا **يُستهلك** (الحدّ نفد) |
| وليّ الأمر ألغى **بعد** المهلة | `PARENT_LATE` | **يُستهلك** | لا |
| **المركز** ألغى | `CENTER` | لا يُستهلك · يُرجَع | **لا يمسّ الحدّ** |
| موعد تعويضي `COMPLETED` | — | يُستهلك (من الرصيد المُرجَع) · `makeup_credits.used +1` | — |
| موعد تعويضي `NO_SHOW` / متأخّر | | يُستهلك · **الائتمان استُهلك** ولا يُعاد | |
| انتهاء الاشتراك | | `EXPIRY` في الدفتر (قائم) | الائتمانات غير المستعملة **تسقط** |

**`cancel_kind` يشتقّه المشغّل** من: هل المُلغي وليّ أمر (`current_user_is_staff()` = false، أو طلب `parent_requests` مقبول) × `now() < starts_at - notice`. **لا يختاره موظّف** — وإلّا صار التعويض قابلًا للتلاعب بكلمة. الاستقبال يُلغي **نيابةً** عن الأسرة عبر قبول طلب `CANCEL` — فيُقرأ وقت **الطلب** لا وقت القبول.

**و`is_billable_flg` القائم** (K-18): يصير **نتيجة** المشغّل (`true` حين يُستهلك) لا مدخلًا — أو يُهمَل بمهاجرة تقول ذلك. **`Database Developer` يقرّر الشكل، والقاعدة واحدة: علمان لشيء واحد ممنوعان.**

## ٥.٤ · التجاوز — `policy_overrides`

جدول واحد لكل أنواع التجاوز (`OD-03` · `OD-14` · `OD-05` تمديد المهلة): `override_id · center_id · kind ∈ {MAKEUP_LIMIT, RESCHEDULE_LIMIT, PAYMENT_HOLD, CANCEL_NOTICE} · entity_table · entity_id · old_value · new_value · reason_ar (إلزامي) · effective_from · effective_to · approved_by · approved_at` + مضاف-فقط. **من انتهت مدّته لا يُقرأ** — `current_limit(kind, entity)` تأخذ التجاوز الساري وإلّا الافتراضي. الصلاحيات: `PACKAGE.MAKEUP_OVERRIDE` · `BILLING.HOLD_EXTEND` · `SETTINGS.MANAGE` للباقي.

---

# ٦ — Data Impact

| # | التغيير | الجدول | النوع |
|---|---|---|---|
| `PK-D1` | `package_versions` (`version_id · package_id · version_no · price_amt · validity_days · allow_freeze_flg · freeze_days · allow_renewal_flg · fixed_appointment_flg · makeup_* ×5 · status ∈ {DRAFT, ACTIVE, RETIRED} · effective_from/to`) + تدقيق · **نسخة `ACTIVE` واحدة لكل قالب في أي لحظة** (استبعاد زمني) | جديد | جدول |
| `PK-D2` | `package_version_services` (`version_id · service_id · session_count · session_duration_min · sessions_per_week · makeup_allowed_flg · specialist_type`) · `UNIQUE(version_id, service_id)` | جديد | جدول |
| `PK-D3` | `service_packages`: `status ∈ {DRAFT, ACTIVE, INACTIVE, ARCHIVED}` + آلة · **`service_id` يُسقَط على خطوتين** · `description_ar` | تعديل | أعمدة |
| `PK-D4` | `child_packages`: `package_version_id` FK · `invoice_id` FK (فاتورة الاشتراك) · `frozen_days_used` · قيد الحالة الجديد · `package_status_history` + `legal_package_transition` · **التعبئة الرجعيّة:** الاشتراكات القائمة تأخذ نسخة `1` مولَّدة من قالبها **كما هو** (لا تخمين) | تعديل | أعمدة + جدول تاريخ |
| `PK-D5` | `child_package_services` (`child_package_id · service_id · purchased · used · returned`) · `CHECK (used + returned <= purchased)` · **رجعيًّا:** صفّ واحد من `service_packages.service_id` القديم | جديد | جدول |
| `PK-D6` | `package_ledger.service_id` · `reason` يُضاف `RETURN` (إلغاء المركز/في الوقت) | تعديل | عمود + قيد |
| `PK-D7` | ~~`makeup_credits`~~ **يُحذف (§17.2)** → `appointments.makeup_for_appointment_id` FK + فهرس فريد جزئي · الحدّ والمستعمَل مشتقّان | تعديل | عمود |
| `PK-D8` | `appointments.child_package_id` · `cancel_kind ∈ {PARENT_ON_TIME, PARENT_LATE, CENTER}` · `CHECK ((status='CANCELLED') = (cancel_kind IS NOT NULL))` — يعيش بجوار `ck_appointments_cancel` **ويُختبر برمزه** (٥ قيود تتقاسم `23514`) | تعديل | أعمدة |
| `PK-D9` | ~~`policy_overrides`~~ → **`limit_overrides` واحد بقوس حصري من مفاتيح حقيقية** للحدود الثلاثة — شكل المعماري ١.٧ المُراجَع (`01-proposals.md:361`)، **بعد قبول المالك** (§17.4) · و`OD-33` في `invoice_installments` | جديد | جدول |
| `PR-D1` | `service_prices` + استبعاد زمني + تدقيق | جديد | جدول |
| `PR-D2` | `services.billing_model` · ٣ أعلام وليّ الأمر | تعديل | أعمدة |
| `PR-D3` | `invoice_lines.list_amt` · `override_reason_ar` | تعديل | أعمدة |
| `CF-D1` | بارامترات: `PACKAGE_NEAR_EXPIRY_DAYS` · `PACKAGE_SESSIONS_LOW_THRESHOLD` · `SINGLE_CANCELLATION_NOTICE_HOURS` · `CANCELLATION_NOTICE_HOURS` · `ALLOW_RESCHEDULE` · `MAX_RESCHEDULE_COUNT` · `RECEIPT_REVIEW_SLA_HOURS` (`BL-52`) — صفوف في `sys_params` بنوعها · **الافتراضيات من السياسة الحالية** حيث قالها المالك، و`NULL` حيث لم يقل | بذور | صفوف |
| `RB-D1` | ٦ رموز صلاحية (K-12) وربطها بـ`CENTER_ADMIN` | بذور | صفوف |

---

# ٧ — Backend Impact

| # | الدالّة / المسار | القاعدة | الرفض |
|---|---|---|---|
| `PR-01` | `current_price(service_id, kind, at)` · `set_service_price(...)` بـ`BILLING.PRICE_EDIT` | سعر واحد ساري لكل نوع | `HB` جديد: لا سعر ساري |
| `PR-02` | `add_invoice_line` **v2** (§4) | `BILLING.MANAGE` + `PRICE_OVERRIDE` للتجاوز | `HB` جديد: تجاوز بلا صلاحية/سبب |
| `PR-03` | `services.billing_model` يُفحص في `sell_package` و`book_appointment` المفرد | | `HB`: نموذج لا يسمح |
| `PK-01` | `create_package_version` · `activate_package_version` (`CATALOG.PUBLISH`) · `retire_package_version` | نسخة `ACTIVE` واحدة | |
| `PK-02` | `sell_package` **v2**(child, version, first_start?, overrides?) → اشتراك `PENDING_PAYMENT` + أسطر خدمات + فاتورة `ISSUED` بسطر من `current_price(PACKAGE)`… **لا**: سعر النسخة `price_amt` هو سعر الباقة الكليّ — يُجمَّد على السطر | معاملة واحدة · **اقرأ ← لي ← يحقّ ← الحالة ← اكتب** | |
| `PK-03` | مشغّل `payments` **`INSERT OR UPDATE`**: فاتورة الاشتراك `PAID` → `ACTIVE` بجملة مستقلّة → يحسب `makeup_credits.granted` → **إن `fixed_appointment_flg`: `book_recurring`** للخدمات (والرفض المسمّى للعطلة **يُعاد** للاستقبال لا يُبتلع) | | `HB101/102` القائمان |
| `PK-04` | `freeze_package` · `unfreeze_package` | `allow_freeze_flg` · `freeze_days` | `HB` جديد |
| `PK-05` | `renew_package(child_package_id)` → اشتراك جديد من **النسخة السارية اليوم** (لا القديمة) | `allow_renewal_flg` | |
| `PK-06` | **مشغّل انتقال الموعد** (`trg_appointment_status` يُوسَّع): جدول §5.3 — يشتقّ `cancel_kind`، ينادي `consume_package_session(cp, service, session)` **بجملة مستقلّة**، يكتب `RETURN`، يمنح/يستهلك الائتمان — **يغلق C-01** | جملة لكل تحديث · `27000` محسوب | `HB051` القائم |
| `PK-07` | `book_makeup_appointment(...)` → موعد بـ`makeup_credit_id` من نفس الخدمة · تجاوز الخدمة بـ`PACKAGE.MAKEUP_OVERRIDE` + سبب | `used < granted` · داخل `expires_on` | `HB` جديد |
| `PK-08` | `apply_policy_override(kind, entity, new, reason, from, to)` + `current_limit(kind, entity)` | صلاحية حسب `kind` | |
| `PK-09` | `run_maintenance` يُوسَّع: `PACKAGE_NEAR_EXPIRY` · `PACKAGE_SESSIONS_LOW` · `MAKEUP_EXPIRING` · `RENEWAL_REQUIRED` (إشعارات) — **الحالة لا تتغيّر بالإشعار** | | |
| `PK-10` | `decide_request` يُوسَّع: قبول `RESCHEDULE` يفحص `ALLOW_RESCHEDULE` و`MAX_RESCHEDULE_COUNT` (عدّ سلسلة `rescheduled_from`) — والتجاوز عبر `PK-08` | | `HB` جديد: تجاوز الحدّ |
| `PK-11` | مسارات: `GET/POST /api/v1/package-templates` (CRUD قائم يُوسَّع) · `…/{id}/versions` · `POST …/versions/{id}/activate` · `POST /children/{id}/packages` (v2) · `POST /packages/{id}/freeze|unfreeze|renew` · `GET /children/{id}/package-balances` · `POST /appointments/makeup` · `GET/POST /service-prices` · `GET/POST /policy-overrides` · `GET /me/packages` (البوّابة: رصيد كل خدمة + تعويض + انتهاء) | Go ينقل | بالاسم |
| `PK-12` | `v_case_timeline` مصادر: `PACKAGE_ACTIVATED · PACKAGE_FROZEN · PACKAGE_UNFROZEN · PACKAGE_EXPIRED · MAKEUP_GRANTED · MAKEUP_USED · PRICE_OVERRIDDEN` | | |

**Race:** الاستهلاك `FOR UPDATE` (قائم) · التثبيت يصطدم بـ`23P01` **ويُعاد للاستقبال باسم الموعد** · تجاوزان لنفس الكيان في لحظة ← الاستبعاد الزمني على `policy_overrides`.

**Transaction boundaries:** البيع = اشتراك + أسطر + فاتورة + سطر + إصدار **في واحدة** · التفعيل = مشغّل بجملة مستقلّة · التثبيت = **نداء مستقلّ بعد التفعيل** (فشله لا يُلغي الاشتراك — الاستقبال يُبلَّغ).

---

# ٨ — Notifications · `NT-xx` (**راجع القائم أولًا** — ١٦ نوعًا · ٥ ميّتة C-14)

| # | النوع | يُطلق من | القائم؟ |
|---|---|---|---|
| — | `APPOINTMENT_BOOKED · CANCELLED · RESCHEDULED · REMINDER` · `INVOICE_ISSUED` | | ✅ قائم |
| `NT-01`…`NT-06` | `CONSULTATION_REQUESTED · THERAPIST_ASSIGNED · CHOOSE_SLOT · PAYMENT_PENDING · RECEIPT_RECEIVED · RECEIPT_APPROVED · RECEIPT_REJECTED` | `09` `BE-09` | ❌ |
| `NT-07` | `APPOINTMENT_CONFIRMED` | تأكيد بالسداد | ❌ |
| `NT-08` | `PACKAGE_ACTIVATED` | `PK-03` | ❌ |
| `NT-09` | `PACKAGE_NEAR_EXPIRY` | صيانة | ❌ |
| `NT-10` | `PACKAGE_SESSIONS_LOW` | صيانة | ❌ |
| `NT-11` | `MAKEUP_GRANTED` | `PK-06` | ❌ |
| `NT-12` | `MAKEUP_EXPIRING` | صيانة | ❌ |
| `NT-13` | `RENEWAL_REQUIRED` | صيانة (`EXHAUSTED`/قرب الانتهاء + `allow_renewal`) | ❌ |
| `NT-14` | `STAFF_RECEIPT_PENDING` · `STAFF_FIXED_BOOKING_FAILED` | للموظّف | ❌ |

**القناة:** `NOTIFY_CHANNEL` القائم (In-App دائمًا + SMS إن مفعَّل وبموافقة). **لا WhatsApp ولا Email** (`OD-22`).

---

# ٩ — Frontend Impact · **وليّ الأمر** (`FE-P`)

| # | الشاشة | الغرض | الحقول | الأفعال | الحالات | الأخطاء | فارغ | موبايل |
|---|---|---|---|---|---|---|---|---|
| `FE-P1` | **اللوحة** (تُوسَّع `home`/`billing`) | الباقة الفعّالة · الانتهاء · **المتبقّي لكل خدمة** · **التعويض ن من م** · الموعد التالي · حالة الدفع · المستحق · الاستحقاق التالي · **يلزم تجديد** · **تحذير الاكتمال** | من `me/packages` · `me/balance` | «التفاصيل» · «طلب إعادة جدولة» (= `parent_requests`) · «تجديد» (إن `allow_renewal`) | `PENDING_PAYMENT` (شارة انتظار الدفع) · `ACTIVE` · `FROZEN` · `EXHAUSTED` · `EXPIRED` | — | «لا باقة — اطلب من المركز» | بطاقة واحدة أولًا |
| `FE-P2` | **تفاصيل الباقة** | كل خدمة: مشترى/مستعمل/مُرجَع/متبقّ · التعويض: ممنوح/مستعمل/ينتهي | | «احجز تعويضًا» **فقط إن `used < granted` وخدمة بائتمان** | | | | |
| `FE-P3` | **الاعتذار** (`requests` قائم) | `CANCEL`/`RESCHEDULE` على موعد | سبب | إرسال | **يعرض قبل الإرسال:** «قبل المهلة → يُحسب تعويضًا / بعدها → لا» **بقراءة من الخادم لا حساب** | | | |
| `FE-P4` | **حجز التعويض** | فتحات الخدمة نفسها (إن `allow_parent_self_booking`) وإلّا طلب | | | | `HB`: لا ائتمان | | |

# ١٠ — Frontend Impact · **الكونسول** (`FE-C`)

| # | الشاشة | الصلاحية |
|---|---|---|
| `FE-C1` | **قوالب الباقات** (`PACKAGES_SPEC` يُوسَّع): حالة · وصف · **زرّ «نسخة جديدة»** | `CATALOG.MANAGE` |
| `FE-C2` | **نسخة الباقة**: الحقول ١٤ + جدول الخدمات (N صفوف) · «تفعيل» (`CATALOG.PUBLISH`) · **النسخة `ACTIVE` للقراءة فقط** | `CATALOG.MANAGE` · `CATALOG.PUBLISH` |
| `FE-C3` | **اشتراكات المستفيد** (`child-profile` يُوسَّع): بيع (اختيار نسخة سارية) · أرصدة الخدمات · تجميد/فكّ · تجديد · **نتيجة التثبيت** (١١ نجحت + ١ مرفوض بالاسم) | `BILLING.MANAGE` |
| `FE-C4` | **تجاوزات السياسة**: قائمة · إنشاء بسبب ومدّة · تاريخ | حسب `kind` |
| `FE-C5` | **أسعار الخدمات**: لكل خدمة سعران بتاريخ سريان · تاريخ التغييرات (من `audit_log`) | `BILLING.PRICE_EDIT` |
| `FE-C6` | **الفاتورة** (قائم): السعر **يُملأ ولا يُكتب** · تجاوز بسبب لمن يملكه · `list_amt` ظاهر | `BILLING.MANAGE` · `PRICE_OVERRIDE` |
| `FE-C7` | **مراجعة الإيصالات** — في `09` `FE-13` | `BILLING.RECEIPT_REVIEW` |
| `FE-C8` | **إعدادات السياسات** (`settings` قائم): البارامترات الجديدة تظهر تلقائيًّا | `SETTINGS.MANAGE` |
| `FE-C9` | **سجلّ التدقيق** (`ops-log` قائم): يكفي — لا شاشة جديدة | `OPS.VIEW` |

---

# ١١ — Acceptance Criteria · `PK-AC`

| # | المعيار |
|---|---|
| PK-AC-01 | تفعيل نسخة ثانية لقالب يجعل الأولى `RETIRED` — **ولا يغيّر رقمًا في أي اشتراك قائم** |
| PK-AC-02 | باقة بثلاث خدمات (٨+٤+٢) تُباع ← ثلاثة أسطر أرصدة، والمجموع ١٤ على الاشتراك |
| PK-AC-03 | البيع ينتج `PENDING_PAYMENT` + فاتورة `ISSUED`؛ والسداد الكامل ← `ACTIVE` **بلا نقرة**؛ الجزئي **لا** |
| PK-AC-04 | التفعيل مع `fixed_appointment_flg` يحجز السلسلة؛ الاصطدام بعطلة يُبلَّغ **بالموعد المرفوض بالاسم** والباقي محجوز |
| PK-AC-05 | جلسة `COMPLETED` تُنقص **خدمتها** واحدًا في `child_package_services` **و**تكتب `SESSION` في الدفتر — **C-01 مغلق** |
| PK-AC-06 | `NO_SHOW` تُنقص · إلغاء وليّ الأمر قبل ٢٤ ساعة لا يُنقص ويمنح ائتمانًا · بعدها يُنقص بلا ائتمان · إلغاء المركز لا يُنقص ولا يمسّ الائتمان |
| PK-AC-07 | `cancel_kind` **لا يُقبل من المنادي** — `UPDATE` مباشر بقيمة يُرفض بالرمز |
| PK-AC-08 | الائتمان الثالث على حدّ ٢ ← الجلسة **تُستهلك** (لا خطأ، وسطر دفتر يقول لماذا) |
| PK-AC-09 | موعد تعويضي لخدمة أخرى يُرفض؛ ومع `PACKAGE.MAKEUP_OVERRIDE` + سبب يُقبل ويُدقَّق |
| PK-AC-10 | تجاوز حدّ التعويض ٢→٤ بمدّة: داخل المدّة `current_limit = 4`، بعدها `2` — **بلا تدخّل** |
| PK-AC-11 | تجميد ٧ أيام على `freeze_days = 10` يمدّد `expires_on` ٧ · والثامن+الرابع يُرفض |
| PK-AC-12 | الانتهاء: `EXPIRED` · `EXPIRY` في الدفتر بالمتبقّي · الائتمانات تسقط · `RENEWAL_REQUIRED` يصل |
| PK-AC-13 | التجديد يأخذ **النسخة السارية اليوم** لا نسخة الاشتراك المنتهي |
| PK-AC-14 | سطر فاتورة بخدمة **بلا سعر مرسَل** يأخذ `current_price(SINGLE)`؛ وبسعر مرسَل **بلا `PRICE_OVERRIDE`** يُرفض؛ ومعها بلا سبب يُرفض |
| PK-AC-15 | رفع السعر اليوم لا يغيّر `unit_amt` على فاتورة أمس |
| PK-AC-16 | خدمة `PACKAGE_ONLY` تُرفض في حجز مفرد بالرمز؛ `SINGLE_SESSION_ONLY` تُرفض في البيع |
| PK-AC-17 | وليّ الأمر يرى في اللوحة: ٣ من ٨ · ١ من ٢ تعويض · ينتهي · الموعد التالي — **من الخادم، لا حساب في الشاشة** |
| PK-AC-18 | كل تغيير سعر/سياسة/تجاوز له صفّ `audit_log` بـ`old_data`/`new_data`/`changed_by` |
| PK-AC-19 | **كل رفض يُؤكَّد برمزه هو** — والقيود الخمسة على `appointments` التي تتقاسم `23514` تُختبر **بالاسم** |

---

# ١٢ — Test Scenarios · `TS-P-xx`

| # | السيناريو | النوع | التأكيد |
|---|---|---|---|
| TS-P-01 | إنشاء قالب → نسخة بثلاث خدمات → تفعيل | Happy | `ACTIVE` واحدة |
| TS-P-02 | نسخة ثانية وتفعيلها | Happy | الأولى `RETIRED` · اشتراك قائم لم يتغيّر |
| TS-P-03 | بيع لطفل → فاتورة → سداد كامل | Happy | `ACTIVE` · ائتمان `granted = 2` · ١٢ موعدًا (إن تثبيت) |
| TS-P-04 | سداد جزئي | Negative | `PENDING_PAYMENT` باقٍ |
| TS-P-05 | تثبيت فوق عطلة المركز | Edge | ١١ + رفض مسمّى · الاشتراك `ACTIVE` |
| TS-P-06 | جلسة تخاطب `COMPLETED` | Happy | تخاطب ٧/٨ · مهارات ٤/٤ · دفتر `SESSION` بـ`service_id` |
| TS-P-07 | إلغاء وليّ الأمر قبل ٤٨ ساعة | Happy | لا خصم · `RETURN` · ائتمان `used 0/2` باقٍ · `MAKEUP_GRANTED` |
| TS-P-08 | إلغاء قبل ٦ ساعات | Negative | خصم · `PARENT_LATE` · لا ائتمان |
| TS-P-09 | `NO_SHOW` | Negative | خصم |
| TS-P-10 | المركز يُلغي | Happy | لا خصم · `CENTER` · الائتمان لا يُمَسّ |
| TS-P-11 | ثالث إلغاء في الوقت على حدّ ٢ | Edge | خصم · سطر دفتر مسبَّب |
| TS-P-12 | حجز تعويض لنفس الخدمة | Happy | `makeup_credit_id` · `used 1/2` |
| TS-P-13 | تعويض لخدمة أخرى بلا صلاحية / بها بلا سبب / بها وبسبب | Negative×2 + Happy | الرموز الثلاثة بالاسم |
| TS-P-14 | تجاوز الحدّ ٢→٤ من ١٠/١ إلى ٣٠/١ ثم اليوم ٣١/١ | Edge | `4` ثم `2` |
| TS-P-15 | تجميد ٧ ثم محاولة ٤ على حدّ ١٠ | Edge | الأولى تمرّ · الثانية `HB` · `expires_on +7` |
| TS-P-16 | `expire_packages` على اشتراك بمتبقٍّ | Happy | `EXPIRED` · `EXPIRY -3` · ائتمان ساقط |
| TS-P-17 | تجديد بعد رفع سعر النسخة | Edge | الاشتراك الجديد بالسعر الجديد |
| TS-P-18 | `add_invoice_line` بخدمة بلا سعر | Happy | `unit_amt = current_price` · `list_amt` مساوٍ |
| TS-P-19 | نفسها بسعر ٣٥٠ من استقبال | Negative | `HB` بلا صلاحية |
| TS-P-20 | نفسها بسعر ٣٥٠ من مدير بسبب «ظروف» | Happy | `unit 350` · `list 500` · تدقيق |
| TS-P-21 | تغيير السعر بعد فاتورة | Regression | فاتورة الأمس ثابتة |
| TS-P-22 | سعران متداخلان لنفس الخدمة والنوع | Negative | `23P01` |
| TS-P-23 | `PACKAGE_ONLY` في حجز مفرد | Negative | بالرمز |
| TS-P-24 | `UPDATE appointments SET cancel_kind='CENTER'` مباشر (`SET ROLE hbh_app`) | Negative | مرفوض بالرمز |
| TS-P-25 | `UPDATE child_packages SET status='ACTIVE'` مباشر | Negative | آلة الحالة ترفض |
| TS-P-26 | لوحة وليّ الأمر | Happy | الأرقام من `me/packages` تطابق القاعدة |
| TS-P-27 | وليّ أمر (أ) يقرأ `me/packages` بمعرّف طفل (ب) | Security | صفر |
| TS-P-28 | صيانة عند `expires_on - 3` | Happy | `PACKAGE_NEAR_EXPIRY` مرّة واحدة — **لا كل تشغيلة** |
| TS-P-29 | **قبل كل رفض:** فحص قبول | Meta | البوّابة تفتح |
| TS-P-30 | `p6` يُوسَّع: **المنادي** يُختبر لا الدالّة | Meta | إغلاق جلسة يحرّك الرصيد |

---

# ١٣ — مفتوح في هذه الوثيقة وحدها

| # | السؤال | الافتراض حتى الجواب |
|---|---|---|
| `BL-53` 🟡 | هل تُثبَّت المواعيد **قبل** السداد (الأسرة تحجز خانتها ثم تدفع)؟ | **لا** — التثبيت عند `ACTIVE`. إن نعم: `PENDING_PAYMENT` يحجز ويُحرَّر بمهلة كالاستشارة |
| `BL-37` | التقسيط | لا يُبنى |
| ب.٢ | الجلسة الخارجية: خدمة أم مكان؟ | لا يُبنى |
| — | التجميد يمدّد الانتهاء؟ | نعم (`10` §4) |

---


---

# ١٤ — قرارات المالك المسائية · **`OD-28` و`OD-29` تغيّران ثلاثة مواضع أعلاه**

**`BL-53` أُغلق (`OD-28`):** لا تثبيت نهائي قبل تأكيد **مبلغ التفعيل**؛ حجز مؤقّت جائز أثناء الدفع؛ والمبلغ المطلوب — كامل أو مقدَّم — **سياسة قابلة للإعداد**. **`BL-39` أُغلق (`OD-29`):** التجميد يمدّد الانتهاء بأيامه؛ لا استهلاك أثناءه؛ حدّ أيام **ومرّات**؛ صلاحية وسبب ومدّة وتدقيق.

| الموضع | كان | صار |
|---|---|---|
| §3 آلة الاشتراك | `PENDING_PAYMENT → ACTIVE` **بالسداد الكامل** | **ببلوغ مبلغ التفعيل**: `PACKAGE_ACTIVATION_KIND ∈ {FULL, DEPOSIT}` · `PACKAGE_DEPOSIT_PCT` (أو `_AMT`) — بارامتران عامّ/لكل مركز. `FULL` = السلوك السابق. السداد الجزئي **دون** المقدَّم لا يفعّل |
| §3 التثبيت قبل الدفع | لا | **حجز مؤقّت**: `sell_package` يحجز السلسلة بـ`book_recurring` **مع `PENDING_PAYMENT`** وتُسجَّل `hold_until = now() + PACKAGE_PAYMENT_HOLD_MIN`؛ الصيانة تُلغي السلسلة (`cancel_recurrence` القائمة، سبب `PAYMENT_TIMEOUT`، `cancel_kind = CENTER` فلا يمسّ شيئًا) وتُبقي الاشتراك `PENDING_PAYMENT` أو تُلغيه — **سياسة**: `PACKAGE_HOLD_EXPIRY_ACTION ∈ {RELEASE_SLOTS, CANCEL_SUBSCRIPTION}`، الافتراضي `RELEASE_SLOTS`. **الضمان** (عدم إعطاء الخانة لغيره) يبدأ عند `ACTIVE` — وقبله الخانة محجوزة فعلًا بقيد الاستبعاد لكنها **قابلة للتحرير بالمهلة** |
| §3 التجميد | يمدّد `expires_on` (افتراض) | **قرار**: يمدّد بعدد الأيام المعتمدة · **لا استهلاك أثناءه**: المواعيد المثبَّتة داخل نافذة التجميد تُلغى بـ`cancel_kind = CENTER` وسبب `FREEZE` (لا تُستهلك ولا تمسّ التعويض — `OD-15`)، وتُعاد جدولة الذيل بعد الفكّ بـ`book_recurring` من `expires_on` القديم إلى الجديد · `freeze_max_count` يُضاف إلى النسخة بجوار `freeze_days` · الصلاحية `BILLING.MANAGE` (دورة حياة الاشتراك) · السبب والمدّة **إلزاميان** · وسطر في `package_ledger`؟ **لا** — التجميد ليس حركة رصيد؛ `package_status_history` + `audit_log` يكفيان |
| §6 `CF-D1` | ٧ بارامترات | + `PACKAGE_ACTIVATION_KIND` (`FULL`) · `PACKAGE_DEPOSIT_PCT` (**`50` — `OD-31`**) · `PACKAGE_PAYMENT_HOLD_MIN` (**نفس قيمة الاستشارة `120` افتراضًا** — يُفصَل لأن باقةً وحجزَ ساعةٍ ليسا شيئًا واحدًا) · `PACKAGE_HOLD_EXPIRY_ACTION` (`RELEASE_SLOTS`) · `RECEIPT_REVIEW_SLA_HOURS = 2` (`OD-27`) |
| §7 `PK-03` | مشغّل التفعيل على `PAID` | على **`paid_amt >= activation_amount(version, kind)`** — `INSERT OR UPDATE` · والتثبيت **لا يُعاد** إن كانت السلسلة محجوزة مؤقّتًا من البيع؛ يكتفي بتغيير الاشتراك `ACTIVE` |
| §7 `PK-04` | `freeze_package(id, from, to, reason)` | + فحص `freeze_max_count` · إلغاء مواعيد النافذة · وعند الفكّ إعادة الجدولة للذيل · **ونتيجة إعادة الجدولة تُعاد بالاسم** (١١ نجحت + ١ رفض) كما في التثبيت |
| §11 `PK-AC-03` | «الجزئي **لا**» | «الجزئي يفعّل **إذا بلغ مبلغ التفعيل** (`DEPOSIT`)، ولا يفعّل دونه» |
| §11 `PK-AC-04` | التفعيل يحجز السلسلة | البيع يحجز **مؤقّتًا** بمهلة · انقضاؤها يحرّر السلسلة ويُبقي `PENDING_PAYMENT` · التفعيل يثبّت |
| §11 `PK-AC-11` | تجميد ٧ يمدّد ٧ | + الثالثة على `freeze_max_count = 2` تُرفض · مواعيد النافذة تُلغى `CENTER` بلا استهلاك · الذيل يُعاد جدولته |
| §12 | ٣٠ سيناريو | + `TS-P-31` بيع بـ`DEPOSIT 50%` وسداد ٤٠٪ ثم ٦٠٪ (الثانية تفعّل) · `TS-P-32` حجز مؤقّت ينقضي: السلسلة محرَّرة والاشتراك باقٍ · `TS-P-33` تجميد فوق موعد مثبَّت: يُلغى `CENTER` والرصيد ثابت والتعويض ثابت · `TS-P-34` فكّ التجميد: الذيل محجوز حتى `expires_on` الجديد · `TS-P-35` ثالث تجميد يُرفض بالرمز · `TS-P-36` إيصال تجاوز `SLA`: يبقى `REVIEW_PENDING` و`STAFF_RECEIPT_OVERDUE` **مرّة واحدة** |
| §13 | `BL-53` · التجميد افتراض | كلاهما **مغلق** — يبقى `BL-37 أ·ب` (أشكال التقسيط الأخرى ومَن يوافق) وب.٢ |

**ما تغيّر في الواجهة:** `FE-P1` يعرض «محجوز مؤقّتًا حتى …» في `PENDING_PAYMENT` مع المبلغ المطلوب للتفعيل **مقروءًا من الخادم** · `FE-C3` زرّ التجميد يطلب السبب والمدّة ويعرض «تبقّى ن مرّات» · **ولا حساب في الشاشة**.


---

# ١٥ — خطط الدفع · **`OD-33` — `BL-37 أ·ب` أُغلق**

**القرار:** التقسيط **نموذج خطّة دفع** قابل للإعداد: `FULL` و`DEPOSIT_PERCENT` (المقدَّم الافتراضي ٥٠٪)؛ الباقي أقساطًا بمبلغ/نسبة **وتاريخ استحقاق أو استحقاق بعد عدد جلسات**؛ الإدارة المخوَّلة تُعدّ الجدول أو تتجاوزه بتاريخ تدقيق. **و`BL-37 ج` (القسط المتأخّر) يبقى** — السلوك القائم: الاستهلاك لا يسأل عن الدفع، والتأخّر **إشعار لا حجب**.

**ويحلّ محلّ بارامترَي `OD-28`/`OD-31`** — وقد أُنشئا فعلًا في `0137` قبل أن تصل هذه الرسالة (`PACKAGE_ACTIVATION_KIND = FULL` · `PACKAGE_DEPOSIT_PCT = 50`، **بلا قارئ**): **يُتقاعدان في `0138`** لا يُتركان. مبلغ التفعيل = **مقدَّم خطّة الفاتورة** — مصدر حقيقة واحد، وصفّان بلا قارئ يصيران قارئًا يومًا ما.


**الترتيب — طبقتان (حُسم مع `Database Developer`):** **أ** الآن قبل الباقات: القوالب · الأقساط · `invoice_installments` وآلتها · `issue_invoice` v2 · مشغّل المجموع · سداد بالترتيب · `BILLING.SCHEDULE_OVERRIDE` · **و`policy_overrides` (§5.4) معها** بـ`override_installment_schedule`. **ب** مع الباقات: مشغّل `AFTER_SESSIONS` · التفعيل عند `seq 1`. راجع `10` §2 التصحيح على `OD-33`.

## ١٥.١ · Data

| # | التغيير | النوع |
|---|---|---|
| `PP-D1` | **`payment_plans`** (القالب): `plan_id · center_id · code · name_ar · kind ∈ {FULL, DEPOSIT_PERCENT} · deposit_pct · status ∈ {DRAFT, ACTIVE, RETIRED} · is_default_flg` + `UNIQUE (center_id) WHERE is_default_flg` + تدقيق · **بذور:** `FULL` (افتراضية — نصّ `OD-31`) · `DEPOSIT_50` (`DEPOSIT_PERCENT`, `50`) | جديد |
| `PP-D2` | **`payment_plan_installments`** (تعريف الأقساط في القالب): `plan_id · seq · amount_kind ∈ {AMOUNT, PERCENT} · amount_value · due_kind ∈ {DAYS_AFTER_ISSUE, AFTER_SESSIONS} · due_value` · `CHECK` مجموع النسب ≤ ١٠٠ − المقدَّم | جديد |
| `PP-D3` | **`invoice_installments`** (جدول الفاتورة الفعلي، مولَّد عند الإصدار): `installment_id · invoice_id · seq · amount · due_date · due_after_sessions · status ∈ {PENDING, DUE, PAID, OVERDUE}` + آلة حالة وتاريخ + مجموع الأقساط = إجمالي الفاتورة بمشغّل | جديد |
| `PP-D4` | `invoices.payment_plan_id` (نسخة القالب وقت الإصدار — لا يتغيّر بتغيير القالب) · `child_packages.payment_plan_id` | أعمدة |
| `PP-D5` | صلاحية **`BILLING.SCHEDULE_OVERRIDE`** (السابع على الاصطلاح) — تجاوز جدول فاتورة **مُصدَرة** بسبب، عبر `policy_overrides` kind `PAYMENT_SCHEDULE` | بذور |

## ١٥.٢ · Backend

| # | العمل | القاعدة |
|---|---|---|
| `PP-01` | `issue_invoice` **v2**: يولّد `invoice_installments` من خطّة الفاتورة (المقدَّم قسط `seq 1` مستحقّ فورًا) · بلا خطّة ← الافتراضية | معاملة الإصدار نفسها |
| `PP-02` | مشغّل `payments` (`INSERT OR UPDATE`): يسدّد الأقساط **بالترتيب** (`seq`) · و**تفعيل الاشتراك عند سداد `seq 1`** — يستبدل شرط `PK-03` | جملة مستقلّة |
| `PP-03` | `AFTER_SESSIONS`: مشغّل على `child_package_services.used` يعلّم القسط `DUE` حين مجموع المستعمل ≥ `due_after_sessions` · و`DAYS_AFTER_ISSUE`: الصيانة تعلّم `DUE` ثم `OVERDUE` | لا حجب — `BL-37 ج` |
| `PP-04` | `override_installment_schedule(invoice_id, new_schedule, reason)` بـ`BILLING.SCHEDULE_OVERRIDE` · المجموع ثابت · المدفوع لا يُمَسّ · صفّ في `policy_overrides` | |
| `PP-05` | إشعارات `INSTALLMENT_DUE` · `INSTALLMENT_OVERDUE` (الأسرة) · `STAFF_INSTALLMENT_OVERDUE` (الموظّف) — مرّة لكل قسط | `NT-15`…`NT-17` |
| `PP-06` | مسارات: `GET/POST /api/v1/payment-plans` (+ أقساطها) · `GET /invoices/{id}/installments` · `POST …/installments/override` · البوّابة `GET /me/installments` | Go ينقل |

## ١٥.٣ · Frontend

| الشاشة | ما يظهر |
|---|---|
| الكونسول / خطط الدفع (`settings` يُوسَّع) | القوالب وأقساطها · «افتراضية» واحدة · الصلاحية `BILLING.MANAGE` (مال، لا كتالوج) |
| الكونسول / الفاتورة (قائم) | جدول الأقساط · «تجاوز» لمن يملكه بسبب |
| الكونسول / بيع الباقة (`FE-C3`) | اختيار الخطّة (الافتراضية مسبقًا) · **المبلغ المطلوب للتفعيل مقروء من الخادم** |
| البوّابة / اللوحة (`FE-P1`) | «الاستحقاق التالي: مبلغ · تاريخ / بعد ن جلسات» · شارة «متأخّر» — **بلا حساب** |

## ١٥.٤ · AC + TS

| # | المعيار |
|---|---|
| PP-AC-01 | فاتورة اشتراك بخطّة `DEPOSIT_50` + قسطان ٢٥٪/٢٥٪ ← ٣ أقساط مجموعها = الإجمالي؛ الأول `DUE` فورًا |
| PP-AC-02 | سداد ٥٠٪ ← القسط ١ `PAID` **والاشتراك `ACTIVE`** · سداد ٤٠٪ ← لا |
| PP-AC-03 | قسط `AFTER_SESSIONS = 6` يصير `DUE` عند الجلسة السادسة **المكتملة** — لا المحجوزة |
| PP-AC-04 | تغيير القالب بعد الإصدار لا يغيّر جدول الفاتورة |
| PP-AC-05 | التجاوز بلا `BILLING.SCHEDULE_OVERRIDE` يُرفض · بها بلا سبب يُرفض · بمجموع مختلف يُرفض · الصحيح يُقبل ويُدقَّق |
| PP-AC-06 | قسط `OVERDUE` **لا يمنع** إغلاق جلسة ولا استهلاكًا (`BL-37 ج` قائم) — ويُشعر الطرفين مرّة |
| PP-AC-07 | خطّتان افتراضيتان لمركز ← `23505` بالاسم |

| # | السيناريو | التأكيد |
|---|---|---|
| TS-P-37 | بيع بخطّة `DEPOSIT_50` + قسطان بتاريخ | ٣ أقساط · `seq 1 DUE` |
| TS-P-38 | ٤٠٪ ثم ١٠٪ | الثانية تفعّل · `seq 1 PAID` |
| TS-P-39 | قسط بعد ٦ جلسات: ٥ مكتملة + ١ محجوزة | `PENDING` · السادسة تُكمل ← `DUE` |
| TS-P-40 | تجاوز الجدول: ٤ حالات | الرموز بالاسم · المدفوع ثابت |
| TS-P-41 | قسط متأخّر ثم إغلاق جلسة | الجلسة تُغلق · الرصيد يُستهلك · إشعار واحد |
| TS-P-42 | تعديل القالب بعد فاتورة | الفاتورة ثابتة |

---

# ١٦ — الجلسات الخارجية · **`OD-34` — ب.٢ أُغلق**

**القرار:** الجلسة الخارجية/المجتمعية **خدمة مستقلّة** حين تختلف مدّتها أو سعرها أو نموذج تشغيلها أو سعتها. لكلٍّ سعرها ومدّتها وقواعد مكانها وسعتها وسلوك فوترتها. **والمكان ظاهر على الموعد.**

**ما هو مبنيّ ويُعاد استعماله:** `services` (صفّ لكل خدمة خارجية: «جلسة تفاعلية — بيلي بييز» · «فيتنس — Eagles» · «سباحة — رويال») · `service_prices` (§4) · `billing_model` · `default_duration_min` · **`appointments.delivery_mode = 'EXTERNAL'` قائم منذ `0117` و`room_id` فارغ له** · `therapist_services` (مَن يقدّمها — أماني وحدها لبيلي بييز) · الباقة تضمّها إن أدرجتها النسخة (يجيب ب.٣ س٤ بلا قاعدة).

| # | التغيير | النوع |
|---|---|---|
| `EX-D1` | **`external_locations`**: `location_id · center_id · name_ar · address_ar · parallel_capacity` (**كم من جلساتنا نحن بالتوازي** — لا سعة المكان) · `contract_kind ∈ {MONTHLY, PER_VISIT, FREE}` · `active_flg` + تدقيق · **بذور:** الأربعة من الاستمارة ب.١ (بيلي بييز ٣ · Eagles · رويال · الخيل «قريبًا» = غير نشط) | جديد |
| `EX-D2` | `appointments.location_id` FK · `CHECK ((delivery_mode = 'EXTERNAL') = (location_id IS NOT NULL))` — أخت قيد `room_id` في `0117` **وتُختبر برمزها** (سادس قيد يتقاسم `23514`) | عمود + قيد |
| `EX-D3` | `services.location_id` (افتراضي للخدمة الخارجية — الموعد يرثه ويجوز تغييره) | عمود |
| `EX-01` | **فحص السعة مشغّل عدّ** لا قيد استبعاد: عدد المتداخل في المكان بحالة حيّة < `parallel_capacity` وإلّا رفض بالاسم — و`available_slots` تُعلمه (`p_location_id`) | مشغّل + توسيع |
| `EX-02` | `v_case_timeline` / `v_family_timeline`: `APPOINTMENT_*` يحمل اسم المكان في `detail` للخارجي | عرض |
| `EX-03` | البوّابة `schedule` (قائم) + الكونسول `day` (قائم): **المكان والعنوان** على الموعد الخارجي — وأيقونة تفرّق `IN_PERSON / ONLINE / EXTERNAL` | FE |

**ما لا يُبنى (ب.٣ لم يُقرَّر ولا يحجب):** مَن ينقل الطفل · هل تُصوَّر الجلسة الخارجية (اليوم: لا كاميرا خارج المركز، فـ`LIVE.VIEW` لا ينطبق) · رسم دخول المرافق (١٠٠ ج.م على الأهل — خارج الفاتورة حتى يُقال غير ذلك).

| # | المعيار |
|---|---|
| EX-AC-01 | خدمة خارجية بسعر ١٠٠٠ ومدّة ٩٠ تُحجز `EXTERNAL` بمكان · الفاتورة من `service_prices` · الموعد يظهر للأسرة بالمكان والعنوان |
| EX-AC-02 | ثلاث جلسات متزامنة في بيلي بييز (سعة ٣) تمرّ · الرابعة تُرفض بالاسم · وغرفة المركز ما زالت طفلًا واحدًا (`23P01`) |
| EX-AC-03 | `EXTERNAL` بلا مكان ← رفض القيد **برمزه** لا بـ`23514` مجهول · `IN_PERSON` بمكان ← رفض |
| EX-AC-04 | الخدمة الخارجية داخل نسخة باقة تُستهلك من رصيدها كأي خدمة · وخارجها تُفوتر مفردة |

| # | السيناريو | التأكيد |
|---|---|---|
| TS-P-43 | حجز خارجي كامل | `EXTERNAL` · `location_id` · السعر من الكتالوج · البوّابة تعرض المكان |
| TS-P-44 | ٣ + ١ في نفس الساعة، بيلي بييز | الرابع مرفوض بالاسم |
| TS-P-45 | نفس الساعة في غرفة | `23P01` — الحارسان مختلفان |
| TS-P-46 | القيد الزوجي `delivery_mode/location_id` بالاتجاهين | رمزه هو |
| TS-P-47 | خارجي داخل باقة ثم `COMPLETED` | رصيد خدمته `-1` |


---

# ١٧ — تصحيحان بنيويّان بعد حكم المعماري · 2026-09-12 ليلًا

## ١٧.١ · `policy_overrides` **لم يُبنَ** — وشكله ليس ما كتبتُه · ⚠️ **الشكل المذكور هنا (جدول لكل كيان) صيغة المعماري الأولى وقد سحبها — المعتمد §17.4 (`architect/01-proposals.md:361`)**

**واقعة:** كتبتُ لمدير المشروع «بُني في طبقة أ بقراري» وقصدتُ «يُبنى» — فنُقلت إلى المعماري واللوحة على أنه بُني. **لا هجرة ولا جدول** (`grep -rl policy_overrides db/migrations/` = ٠). خطأ صياغة منّي انتشر ثلاث وثائق، وكلفته صفر هجرة تُلغى لأن مدير المشروع قارن بالدفتر.

**حكم المعماري (اقتراح `01-proposals.md` بند ١.٧ — ينتظر قبول المالك):** لا جدول واحد ولا جدول لكل نوع، بل **جدول لكل كيان مُتجاوَز بمفتاح أجنبي حقيقي**. العيب في شكلي ليس عدد الجداول بل المفتاح متعدّد الأشكال `entity_table · entity_id`: لا `FOREIGN KEY` ممكن (تجاوز على اشتراك غير موجود صفّ شرعي) · فحص `p00` «كل مفتاح أجنبي له فهرس» لا يراه · وRLS تحتاج `CASE` على اسم الجدول لتصل `can_access_child`. والسؤال الموحَّد «مَن تجاوز ماذا ولماذا» يُجاب بعرض `UNION` بـ`security_invoker` — شكل `v_case_timeline` نفسه.

~~**فيُقرأ §5.4 و`PK-D9` و`PP-D5`/`PP-04` هكذا:** التجاوزات **أربعة جداول**~~ *(مسحوب — راجع §17.4)* — كان: بمفاتيح حقيقية — `package_makeup_overrides(child_package_id)` · `appointment_reschedule_overrides(appointment_id)` · `payment_hold_overrides(consultation_request_id)` · `installment_schedule_overrides(invoice_id)` — بنفس الأعمدة المشتركة (`old_value · new_value integer · reason_ar إلزامي · effective_from/to · approved_by/at`، مضاف-فقط)، وعرض `v_policy_overrides` يجمعها. **الأسماء اقتراح؛ الشكل للمعماري بعد قبول المالك.**

## ١٧.٢ · `makeup_credits` **يُحذف من المواصفة** — رقمٌ واحد كان له بيتان

سأل مدير المشروع: `makeup_credits.granted` (س ٦٥) و`MAKEUP_LIMIT` في التجاوزات (§5.4) **بيتان لرقم واحد**، والوثيقة نفسها تمنع علمين لشيء واحد. **الجواب: كلاهما يُشتقّ، ولا يُكتب أيّهما.**

| الرقم | كان | صار |
|---|---|---|
| **الحدّ** | `granted` يُحسب عند التفعيل ويُخزَّن | **يُشتقّ عند القراءة**: `current_makeup_limit(child_package_id)` = التجاوز الساري إن وُجد، وإلّا `FLOOR(Σ purchased × makeup_value%)` من النسخة (أو `makeup_value` إن `FIXED`). النسخة لا تتغيّر، فالاشتقاق مستقرّ — والتجاوز بمدّة **يعود إلى الافتراضي بانتهائها بلا كتابة** (`OD-14` حرفيًّا) |
| **المستعمَل** | `used` عدّاد | **يُشتقّ**: عدد مواعيد الاشتراك التي `makeup_for_appointment_id IS NOT NULL` وحالتها حيّة أو مكتملة |
| **الأهليّة** | `used < granted` | تُحسب في `book_makeup_appointment` لحظة الحجز، `FOR UPDATE` على الاشتراك |
| **الربط** | `appointments.makeup_credit_id` | **`appointments.makeup_for_appointment_id`** FK حقيقي إلى الموعد الملغى `PARENT_ON_TIME` — **وهو ما يفرض «من نفس الخدمة» اشتقاقًا** (`service_id` الموعدين)، ويمنع تعويض الموعد الواحد مرّتين بفهرس فريد جزئي |
| **الانتهاء** | `expires_on` | `expires_on` الاشتراك نفسه (`PACKAGE_END_DATE`) أو `+ FIXED_DAYS` من النسخة — مشتقّ |
| **حدث «مُنح تعويض»** | صفّ في `makeup_credits` | **هو الإلغاء `PARENT_ON_TIME` نفسه** في `appointment_status_history` — يُقرأ منه الإشعار `MAKEUP_GRANTED` والخطّ الزمني |

**فالمكتوب الوحيد رابطٌ حقيقي، والرقمان مشتقّان.** `PK-D7` يصير: عمود `makeup_for_appointment_id` + فهرس فريد جزئي. و`PK-07` تقرأ الحدّ والمستعمَل من الدالّتين. **والمعايير `PK-AC-08`…`10` والسيناريوهات `TS-P-11`…`14` تبقى كما هي** — تؤكّد السلوك لا الجدول.

**ولماذا لم أرَه:** كتبتُ «التعويض ليس رصيدًا» ثم أعطيته جدول رصيد. القاعدة التي كُتبت في `N-19`: **علمان لشيء واحد ممنوعان — وهذا ينطبق على الجداول كما على الأعمدة.**

## ١٧.٣ · وعلاج «قيود تتقاسم `23514`» — من المعماري على `HBH-044`

`ck_plans_active_approved` يعود بـ`NOT VALID`، **والرفض يُؤكَّد باسم القيد** عبر `GET STACKED DIAGNOSTICS … CONSTRAINT_NAME` — غير مستعمل في المشروع اليوم، وهو علاج «خمسة قيود على `appointments` تتقاسم `23514`» (وسادسها `EX-D2`) من أصله. **فحيث كُتب في هذه الوثيقة «يُختبر برمزه» على قيد `CHECK`، فالمقصود باسم القيد.**

# سجلّ التغيير

| التاريخ | ماذا |
|---|---|
| 2026-09-12 | إنشاء |
| 2026-09-12 مساءً | §14 — `OD-28` `OD-29`: مبلغ التفعيل · الحجز المؤقّت · التجميد بقواعده · ٦ سيناريوهات |
| 2026-09-12 ليلًا | §15 خطط الدفع (`OD-33`) · §16 الجلسات الخارجية (`OD-34`) · بارامترا `OD-28`/`OD-31` لا يُنشآن |
| 2026-09-12 ليلًا | §17 — `policy_overrides` لم يُبنَ · §17.4 حكم المعماري المُراجَع: `limit_overrides` بقوس حصري لثلاثة حدود، `OD-33` في `invoice_installments` · `makeup_credits` يُحذف: الحدّ والمستعمَل مشتقّان · تأكيد الرفض باسم القيد |

## ١٧.٤ · حكم المعماري **المُراجَع** — يحلّ محلّ §17.1 · 2026-09-12 ليلًا

بعد حجّتي غيّر حكمه الأول: **جدول واحد نعم — بمفاتيح حقيقية، وللحدود العددية الثلاثة وحدها، و`OD-33` خارجه.** (بند ١.٧ مُراجَع في `architect/01-proposals.md`؛ رقم `D-xx` ينتظر قبول المالك.)

| | |
|---|---|
| **الاسم** | **`limit_overrides`** — الاسم يحمل الحدّ؛ «تجاوز السياسات» يدعو كل تجاوز، وهو ما حدث مع الرابع |
| **المفتاح** | **قوس حصري** لا `entity_table·entity_id`: `child_package_id REFERENCES child_packages` · `appointment_id REFERENCES appointments` · `consultation_request_id REFERENCES consultation_requests` · `CHECK (num_nonnulls(…) = 1)` · و`CHECK` يربط `kind` بذراعه |
| **الأنواع** | `MAKEUP_LIMIT` (ذراع الاشتراك) · `RESCHEDULE_LIMIT` (ذراع الموعد) · `PAYMENT_HOLD` (ذراع طلب الاستشارة) — **ثلاثة لا أربعة** |
| **القيم** | `old_value · new_value integer CHECK (new_value >= 0)` — لا `jsonb` |
| **السريان** | استبعاد زمني **قيدان جزئيان، واحد لكل ذراع** (NULL لا يساوي NULL في `EXCLUDE`) |
| **الثمن المقصود** | هدف جديد = **عمود بمفتاح يظهر في الدفتر**، لا قيمة في `CHECK` |
| **ما يحفظه** | لي: جدول واحد · `current_limit` واحدة · مجموعة قبول واحدة. له: مفاتيح · فهارس (`p00` يراها) · RLS تعبر إلى `can_access_child` بلا `CASE` · أنواع |

**`OD-33` خارجه — وله بيت أصلًا:** تجاوز جدول الأقساط **مجموعة صفوف** (مبالغ/نسب بتواريخ أو بعد جلسات) لا `old→new`؛ حشره في عمودين نسخة `jsonb` ثانية بلا قيد. **فيُكتب في `invoice_installments` بآلته:** `override_installment_schedule` يُلغي الأقساط غير المسدَّدة القائمة (حالة `SUPERSEDED` في آلتها) ويكتب أقساطًا جديدة، **ويُختم على الفاتورة** بـ`schedule_override_reason_ar · overridden_by · overridden_at`. لا يحتاج `limit_overrides` ولا رقم `D-` — **فيعود إلى طبقة أ** (`PP-04`) كما كان. (وإن ثبت يومًا أنه قيمة واحدة — المقدَّم مثلًا — يدخل ذراعًا رابعة على `invoice_id`.)

**توحيد التسمية (سؤاله ٤):** §5.4 سمّى النوع الرابع `CANCEL_NOTICE` و`10` K-27 سمّاه `OD-33` — **كلاهما يُحذف من الأنواع**: `CANCEL_NOTICE` **سياسة مركز لا حالة**، وبيتها `sys_params` (`CANCELLATION_NOTICE_HOURS` · `MAKEUP_NOTICE_HOURS` على النسخة) وتجاوز المركز لها قائم منذ `0058`/`0060`. و`OD-33` خارجه كما فوق. **فحيث كُتب في §5.4 «`kind ∈ {MAKEUP_LIMIT, RESCHEDULE_LIMIT, PAYMENT_HOLD, CANCEL_NOTICE}`» يُقرأ ثلاثة، وحيث كُتب `policy_overrides` يُقرأ `limit_overrides` بالقوس الحصري.**

**وسؤاله ٥** (`makeup_credits.granted` مقابل `MAKEUP_LIMIT`) — أُجيب في §17.2: **كلاهما يُشتقّ**، والجدول حُذف.

**ترتيب الأذرع — من المعماري، 2026-09-12 ليلًا:** الذراع الثالثة `consultation_request_id` تشير إلى جدول **غير موجود بعد** (`hbh.consultation_requests` — أوّل ذكر له تعليق في `0129:127`). ومفتاح أجنبي إلى جدول غائب لا يُعلَن؛ فإمّا تفشل الهجرة أو تُكتب الذراع بلا `REFERENCES` — **وذاك يعيد `entity_id` متعدّد الأشكال من الباب الخلفي**. **فالهجرة الأولى لـ`limit_overrides` بذراعين** (`child_package_id` · `appointment_id`) ونوعين (`MAKEUP_LIMIT` · `RESCHEDULE_LIMIT`)؛ **والذراع الثالثة وقيد ربطها بـ`PAYMENT_HOLD` تنزلان في الهجرة التي تُنشئ `consultation_requests`** (`HBH-059`). وهذا هو الثمن المقصود يعمل كما صُمِّم: الهدف الجديد عمود في الدفتر **يوم يوجد هدفه**. الرقم **`D-41`** ينتظر قبول المالك (`D-39` واتساب، `D-40` لبند ١.٦).
| 2026-09-12 ليلًا | §17.4 — ترتيب أذرع `limit_overrides`: ذراعان أوّلًا، والثالثة مع `consultation_requests` (`HBH-059`) · الرقم `D-41` |

## ١٧.٥ · ستّ نقاط في §15 حسمها البناء · 2026-09-13

`0140` نزل (فصل رموز الأسعار + `HB261`)، وطبقة أ رقمها **`0142`**. ستّ نقاط لا تحسمها §15، والحكم بجوار كلٍّ:

| # | النقطة | الحكم |
|---|---|---|
| 1 | حالة **`CANCELLED`** للقسط — فاتورة تُلغى يبقى قسطها `DUE` ثم `OVERDUE` وتُشعَر الأسرة عن فاتورة ملغاة | **تُضاف** وتُطبَّق آليًّا على غير المدفوع عند إلغاء الفاتورة. **ومعها `SUPERSEDED`** (§17.4 — تجاوز الجدول يعلّم غير المدفوع ويكتب جديدًا). الآلة: `PENDING → DUE → PAID \| OVERDUE` · `PENDING/DUE/OVERDUE → CANCELLED \| SUPERSEDED` |
| 2 | بذرة `DEPOSIT_50` بلا تعريف للباقي | **تُبذر `DRAFT`**؛ التفعيل يرفض خطّة `DEPOSIT` بلا قسط واحد على الأقل؛ `FULL` `ACTIVE` وافتراضية. **ومتى يُستحقّ الباقي افتراضيًّا سؤال قيمة للمالك — `BL-56`** (لا يحجب: الإدارة تُكمل الخطّة من الشاشة) |
| 3 | الباقي والتقريب | القسط الأخير يحمل الفرق حتى يساوي الإجمالي بالقرش · أقساط `AMOUNT` تزيد على الإجمالي ← **رفض الإصدار برمز مسمّى**، لا قصّ صامت |
| 4 | `DUE` ثم `OVERDUE` لـ`DAYS_AFTER_ISSUE` | **في طبقة أ** (لا يعتمد على الباقات): عند الإصدار ما تاريخه اليوم أو قبله `DUE`؛ الصيانة تعلّم `DUE` يوم الاستحقاق و**`OVERDUE` بعد `due_date + INSTALLMENT_GRACE_DAYS`** — بارامتر `NUMBER` افتراضيه **٠** (لا مهلة حتى يقول المالك غير ذلك — `OD-18`)، وإشعار مرّة لكل قسط. `AFTER_SESSIONS` وحده يبقى لطبقة ب |
| 5 | الفواتير المُصدَرة قبل `0142` | **لا جدول لها ولا تعبئة آلية** — تُعدّ وتُذكر في رأس الهجرة؛ البوّابة لا تُظهر لها «الاستحقاق التالي» (وتقول «لا جدول أقساط» لا فراغًا) |
| 6 | إعادة إصدار فاتورة مُصدَرة | **تُرفض بـ`HB050`** القائم — كانت تمرّ صامتة، ومع v2 كانت ستولّد جدولًا ثانيًا |

**وتصحيح ترتيب وصل متأخّرًا:** `override_installment_schedule` **في طبقة أ** (المعماري أخرج `OD-33` من جدول الحدود — يعيش في `invoice_installments` بـ`SUPERSEDED` والختم على الفاتورة، ولا يحتاج `D-`)، ومعه `BILLING.SCHEDULE_OVERRIDE`. **`limit_overrides` وحده** ينتظر `D-41`.
| 2026-09-13 | §17.5 — ستّ نقاط حُسمت مع `0142` · `BL-56` متى يُستحقّ باقي المقدَّم · `INSTALLMENT_GRACE_DAYS = 0` |

**حسمُ الذراع الثالثة — 2026-09-13:** مدير المشروع لاحظ أن نصّ المعماري (`:361`–`:376`) يذكر ذراعين، وأنا كتبتُ ثلاثًا. **الحسم: ذراعان، ولا ثالثة أبدًا.** `PAYMENT_HOLD` **يعيش على الموعد لا على الطلب**: الشيء المحجوز والمحرَّر بالمهلة هو الموعد `BOOKED`، فمهلته `appointments.payment_hold_until` (فارغ لغير الاستشارة، يكتبه `book_consultation`، والصيانة تقرؤه، والتمديد تجاوزٌ على `appointment_id`). كنتُ قد وضعتها على `consultation_requests` (`09` §21) — والطلب حاوية، والموعد هو المحجوز. **فيسقط اعتماد `D-41` على `HBH-059`**، ويصير نصّ المعماري كما هو صحيحًا بلا ذراع مؤجَّلة.

**شرطا المعماري على `PAYMENT_HOLD` — مقبولان، 2026-09-13** (بند ١.٧ عُدِّل عنده؛ السطر ٣٦١ لم يتحرّك):
1. **قارئ واحد.** الصيانة **لا تقرأ `payment_hold_until` مباشرةً** — دالّة واحدة `effective_payment_hold(appointment_id)` تُرجع المهلة الفعلية = **العمود المجمَّد** + التجاوز الساري إن وُجد. **والعمود لا يُعاد كتابته عند التمديد** — يُجمَّد عند الحجز كسعر سطر الفاتورة، والتجاوز بمدّة يعود بانتهائه بلا كتابة. وإلّا صار رقم في مكانين يكتب فيهما شخصان.
2. **وحدة واحدة مكتوبة.** العمود `timestamptz` والتجاوز `integer`. **`new_value` لـ`PAYMENT_HOLD` = دقائق تمديد تُضاف إلى اللحظة المجمَّدة** بوحدة `CONSULT_PAYMENT_HOLD_MIN` — لا حدّ عددي كنظيريه (`MAKEUP_LIMIT` عدد جلسات · `RESCHEDULE_LIMIT` عدد مرّات). **بالدقائق — المالك اختارها حين سأله المعماري، ونصّ `D-41` صُحِّح بسطر مؤرَّخ 2026-09-13** (كان «ساعات» ساعةً واحدة، ووُحِّدت الوثائق عليه ثم أُعيدت). **والوقاية:** `COMMENT ON COLUMN` يقول «دقائق» بالاسم لهذا النوع، و`effective_payment_hold(appointment_id)` وحدها تحوّل (`+ make_interval(mins => new_value)`) — لا قارئ آخر.

**`BL-56` أُغلق — `OD-38` (2026-09-13):** الباقي ٥٠٪ يُستحقّ **بعد ٦ جلسات**. فبذرة `DEPOSIT_50` **تُبذر `ACTIVE`** بقسطين: `seq 1` = ٥٠٪ فورًا · `seq 2` = ٥٠٪ `AFTER_SESSIONS = 6` — ويُلغى افتراض §17.5 بند ٢ (`DRAFT`). **و`D-41` مقبول (`OD-37`)** — `limit_overrides` يُبنى بشكل §17.4 كاملًا.

**`D-41` مكتوب (2026-09-13، `01-stack-decisions.md:798`) — الشرطان ملزِمان لا اقتراح.** **و`D-40` قُبل معه (`:753`): كل فحص رفض في مجموعة `limit_overrides` يؤكّد اسم القيد** (`GET STACKED DIAGNOSTICS … CONSTRAINT_NAME`) لا `23514` وحده — القوس فيه قيدا `CHECK` على الأقل يرفعان الرمز نفسه. وهو ما كُتب في §17.3 عامًّا، وصار هنا قرارًا برقم.

**`0142` بُنيت كاملة (غير مطبَّقة — محجوزة حتى يسمّي الـAPI `HB265`…`HB273`) · 2026-09-13.** ٣٧/٣٧ على `PP-AC-01/02/04/05/07` بالرمز، والقيود **بالاسم** عبر `CONSTRAINT_NAME` (`D-40` أوّل استعمال). وقراران أُضيفا إلى الستّة، **مقبولان**:
7. **`SUPERSEDED`** — الانتقال إليها من `PENDING/DUE/OVERDUE` فقط؛ المسدَّد لا يُمَسّ. (كما §17.4.)
8. **خطّة `FULL` قسطها الوحيد يُستحقّ في `due_date` الفاتورة** (`INVOICE_DUE_DAYS = 14`) **لا فورًا** — وهو سلوك كل فاتورة اليوم، فإدخال الخطط لا يغيّر شيئًا حتى يختار المركز غيرها. **مقدَّم `DEPOSIT` وحده يُستحقّ يوم الإصدار.** مقبول: تغيير السلوك القائم بلا قرار مالك هو ما ننهى عنه.
- **فاتورة `total = 0` بلا جدول** — قسط بصفر لا معنى له. مقبول.

**وتنبيهان وصلا الداتابيز متأخّرَين** (رسائل في الطابور): `DEPOSIT_50` تُبذر **`ACTIVE`** لا `DRAFT` بعد `OD-38` (`seq 2` = ٥٠٪ `AFTER_SESSIONS = 6`) · وجواب النقطة ٤: `DUE` يوم الاستحقاق، `OVERDUE` بعد `due_date + INSTALLMENT_GRACE_DAYS` (بارامتر افتراضيه ٠)، إشعار مرّة لكل قسط — في طبقة أ.

**`0142` — التنبيهان وصلا وطُبِّقا · 2026-09-13 ظهرًا · ٥٣/٥٣ في معاملة متراجَع عنها.** ما زالت محجوزة (`db/held/0142_payment_plans/`) حتى تنزل `0141` (تزامن مسوّدة التقرير — جلسة أخرى) ثم تُبنى صورة الـAPI بالرموز `HB265`…`HB273`.

> **ترقيم لا تراجع:** كل ذكر لـ«`0141`» في هذا القسم حتى ظهر 2026-09-13 كان يعني خطط الدفع، وصار **`0142`**. السبب أن `p00` يرفض أي فجوة في دفتر الهجرات، فالأرقام تتبع **ترتيب التطبيق**: `0141` تزامن مسوّدة التقرير → صورة الـAPI → `0142` خطط الدفع → `0143` حذف `update_report` السداسية. المحتوى والرموز والبرهان (٥٣/٥٣ من الملفّ الجديد) بلا تغيير. **مقبول كلّه**، وما فيه يُقرأ هكذا:

| البند | ما بُني | أثره على الوثيقة |
|---|---|---|
| **`PP-03` — الساعة في طبقة أ** | `mark_installment_dues()` مهمّة في `run_maintenance`: `DUE` يوم الاستحقاق، `OVERDUE` حين اليوم > `due_date + INSTALLMENT_GRACE_DAYS` (بارامتر عامّ = ٠). قسط لم تره الصيانة `DUE` قطّ يقفز إلى `OVERDUE` في تشغيلة واحدة **وتُبلَّغ الأسرة «متأخّر» وحده** — لا إشعارين | `PP-03` نصفه الزمني ✅ · ونصفه `AFTER_SESSIONS` يبقى لطبقة ب (الصفّ لا تمسّه الساعة — مُثبَت) · `HBH-062` ينقص منها هذا البند |
| **`PP-05` / `NT-15`…`17`** | `INSTALLMENT_DUE` · `INSTALLMENT_OVERDUE` للأسرة · `STAFF_INSTALLMENT_OVERDUE` لموظّفي **مركز القسط** الذين تحمل أدوارهم `BILLING.MANAGE` — **مرّة لكل قسط** (تشغيلتان لا تكرّران — مُثبَت) | ✅ في طبقة أ · `HBH-063` ينقص منها الثلاثة |
| **درس تنفيذ يُسجَّل** | **`notify_role` لا تصلح للصيانة:** بلا هوية تخاطب الدور **في كل المراكز**، فالمستلمون يُحسبون من مركز القسط نفسه (مُثبَت: الموظّفون من المركز نفسه فقط) | يُنقل إلى دروس `CLAUDE.md` عند أوّل تعديل له — وهو عائلة «الصلاحية تقول ماذا لا أيّ صفّ» من جهة الإشعار |
| **`OD-38`** | `DEPOSIT_50` تُبذر `ACTIVE`: فاتورة ١٢٠٠ على البذرة → ٦٠٠ `DUE` ثم ٦٠٠ `PENDING` بعد ٦ جلسات. **والبذرة تُنشأ فقط إن غابت عن المركز** — حتى لا يعيد `migrate` تفعيل خطّة سحبها المركز | `BL-56` مغلق بالبرهان · وقاعدة البذرة الشرطية تنطبق على كل بذرة خطّة قادمة |
| **`HB269`** | **تاريخ القسط ثابت كمبلغه**؛ التغيير عبر التجاوز وحده (`BILLING.SCHEDULE_OVERRIDE` → `SUPERSEDED` + قسط جديد) | `PP-D3`: الجدول مضاف-فقط بمبلغه وتاريخه |
| **«لا جدول أقساط»** | للواجهة والـAPI لا للسكيما: فاتورة سابقة لـ`0142` لا صفوف لها في `invoice_installments`، وهذا ما تسأل عنه الشاشة وتقوله | `FE-C6` يعرض «بلا جدول» على الفاتورة القديمة ولا يبتكر قسطًا افتراضيًّا — **لا تعبئة رجعيّة** (القرار ٥ أعلاه) |
