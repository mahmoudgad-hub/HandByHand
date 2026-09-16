# 03 — MASTER BUSINESS FLOW MAP

**١٤ فلو** `FL-01`…`FL-14`. الخطّ المتّصل = موصول ومُشي · الخطّ المتقطّع = القاعدة
موجودة والطريق مقطوع.

---

## الخريطة العليا — رحلة الطفل من الباب إلى التقرير

```mermaid
flowchart TD
  V[زائر · site/index.html] --> AP[طلب الالتحاق · POST /enrolments]
  AP --> EA[(enrolment_applications · NEW)]
  EA -->|الاستقبال يهاتف| CT[CONTACTED]
  CT --> CV[تحويل · POST /enrolments/:id/convert]
  CT -.->|SMS ENROLMENT_ASSESSMENT| AB[ASSESSMENT_BOOKED]
  AB --> CV
  CV --> G[(guardians)]
  CV --> C[(children)]
  CV --> GC[(guardian_children)]
  CV --> U[(users + role GUARDIAN)]
  U --> LOGIN[دخول الأسرة بـOTP]

  C --> CL[(caseload · إسناد لأخصائي)]
  CL --> SLOT[available_slots + validate_slot]
  SLOT --> APPT[(appointments · BOOKED)]
  APPT --> CONF[CONFIRMED]
  CONF --> CHK[CHECKED_IN]
  CHK --> SESS[(therapy_sessions · IN_PROGRESS)]
  SESS --> LIVE[بثّ مباشر · stream_tokens]
  SESS --> NOTE[(session_notes · INTERNAL)]
  SESS --> CLOSE[close_session · COMPLETED]
  CLOSE --> APPTC[appointments · COMPLETED]
  CLOSE -.->|مفقود| PKG[(package_ledger · خصم)]

  NOTE -->|publish| NOTEP[visibility = PARENT]
  C --> PLAN[(treatment_plans · DRAFT → ACTIVE)]
  PLAN --> GOAL[(plan_goals)]
  GOAL --> MEAS[(goal_measurements)]
  C --> HOME[(child_activities → activity_log)]
  C -.->|لا مسار| ASMT[(assessments)]
  C --> RPT[(progress_reports · DRAFT → PUBLISHED)]
  CLOSE --> INV[(invoices · DRAFT → ISSUED → PAID)]
  CLOSE --> NPS[(nps_surveys · بعد SESSION_COMPLETED)]

  NOTEP --> PORTAL[بوّابة الأسرة]
  RPT --> PORTAL
  INV --> PORTAL
  MEAS --> PORTAL
  LIVE --> PORTAL

  classDef broken stroke-dasharray: 5 5
  class PKG,ASMT broken
```

**اقرأ الخريطة هكذا:** الطرفان ممتازان — الطلب والتحويل من جهة، والجلسة والفاتورة
والتقرير من جهة. **والمسافة بينهما هي التي تُصنع مرّةً واحدة لكل طفل** (منح الحساب ·
الإسناد · كتابة الخطة)، وهي التي لم تُختبَر لأن كل تجهيزة اختبار تنطلق من حالة
تُبنى بـ`INSERT` مباشر بدور المالك.
> **ما يُختبر هو ما يتكرّر، وما يُنسى هو ما يحدث مرّة.**

---

## FL-01 · Parent Enrolment Flow (الالتحاق)

| الحقل | القيمة |
|---|---|
| **Starting Point** | الموقع التعريفي → رابط البوّابة → `/apply` |
| **Actors** | زائر (مجهول) → RECEPTION / CENTER_ADMIN |
| **Preconditions** | لا شيء. **أوّل كتابة غير مصادَقة في السكيما** |
| **Statuses** | `NEW → CONTACTED → ASSESSMENT_BOOKED → ENROLLED` · `REJECTED` · `DUPLICATE` |
| **Screens** | `portal/features/apply/apply.ts` → `ops` `/enrolments` |
| **Backend** | `POST /api/v1/enrolments` → `PATCH /api/v1/enrolments/{id}` → `POST .../convert` |
| **Entities** | `enrolment_applications` → `guardians` + `children` + `guardian_children` + `users` + `user_roles` |
| **Notifications** | SMS `ENROLMENT_SUBMITTED` · `ENROLMENT_ASSESSMENT` |
| **Final Result** | أسرة لها سجلّ حقيقي وحساب بوّابة |
| **Related** | FL-02 · FL-03 · FL-13 |

```mermaid
flowchart LR
  A[نموذج الالتحاق] --> B{حدّ المعدّل<br/>لكل جوال/يوم · لكل IP/ساعة}
  B -->|تجاوز| X[HB093 TOO_MANY]
  B -->|مسموح| C[submit_enrolment]
  C --> D[application_no · ENR-YYYY-NNNNN]
  D --> E[الاستقبال يقرأ · ENROLMENT.MANAGE]
  E --> F[يهاتف → CONTACTED]
  F --> G{تحويل?}
  G -->|لا| H[REJECTED / DUPLICATE]
  G -->|نعم| I[convert_enrolment]
  I --> J[guardians + children + link]
  J --> K[grant_portal_access]
  K --> L[users + GUARDIAN role]
  L --> M[ENROLLED]
```

**Alternative Flow:** `NEW → REJECTED` أو `NEW → DUPLICATE` مباشرة.
**Exception Flow:** `HB091` تحويل من حالة غير مسموحة · `HB090` انتقال حالة غير
قانوني · تصادم جوال عند منح الحساب (`0126`).

**Preconditions التي يفرضها الكود:** التحويل مرفوض من أي حالة غير `CONTACTED` أو
`ASSESSMENT_BOOKED` — أي أن **إنسانًا قد هاتف الأسرة وحرّك الصفّ بيده** قبل أن يصل
التحويل. وهذا بالضبط ما جعل ضمّ منح الحساب إلى التحويل آمنًا في `0125`: تصحيحٌ
أُدخل بالخطأ لا يصل إلى هنا، وملفٌّ يُفتح قبل موافقة الأسرة كذلك.

---

## FL-02 · Parent Account & Login Flow

| الحقل | القيمة |
|---|---|
| **Starting Point** | `/login` في البوّابة |
| **Actors** | GUARDIAN |
| **Preconditions** | صفّ في `hbh.users` بجوال الأسرة **مقيَّسًا** — يُنشأ حصرًا عبر FL-01 |
| **Backend** | `POST /auth/otp/request` → `POST /auth/otp/verify` → توكن Bearer |
| **Entities** | `users` · `otp_codes` · `auth_sessions` · `sms_outbox` |
| **Final Result** | جلسة عمرها ٤٨٠ دقيقة |
| **Related** | FL-01 · FL-13 |

```mermaid
flowchart TD
  A[الجوال كما كُتب] --> B[canonical_mobile → +20...]
  B --> C{المستخدم موجود?}
  C -->|لا| D[202 بلا كشف<br/>الردّ نفسه في الحالتين]
  C -->|نعم| E[request_otp · SECURITY DEFINER<br/>ترجع center_id الذي وجدته]
  E --> F[otp_codes + enqueue_sms · OTP_LOGIN]
  F --> G[الأسرة تُدخل الرمز]
  G --> H{IS DISTINCT FROM?}
  H -->|خطأ أو NULL| I[عدّ المحاولة ثم ارجع حالة<br/>لا RAISE — وإلّا ضاع العدّ]
  H -->|صحيح| J[create_auth_session]
  J --> K[Bearer token]
```

**Exception Flow:** `OTP_MAX_ATTEMPTS` (٥) · انقضاء `OTP_TTL_MINUTES` (١٥) ·
`OTP_RESEND_SECONDS` (٦٠) · حدّ معدّل IP.
**قاعدة الكشف:** الردّ على جوال **موجود** لا يُفرَّق عنه على جوال **غير موجود** —
وإلّا تعلّم من يجرّب الأرقام أيّها حقيقي. **ويُكتب الفحص بمقارنة جسمين من نفس
النقطة، لا بجسم متوقَّع منسوخ** (و`request_id` وحده يُستثنى: هو الحقل الذي **يجب**
أن يختلف).

---

## FL-03 · Assignment Flow (الإسناد)

| الحقل | القيمة |
|---|---|
| **Starting Point** | `/caseload` في الكونسول (شاشة مورد عامّة) |
| **Actors** | CENTER_ADMIN · RECEPTION |
| **Preconditions** | طفل نشط + أخصائي + خدمة |
| **Backend** | `POST /api/v1/caseload` (CRUD عامّ · **بلا دالّة تحمل قواعده**) |
| **Entities** | `caseload` |
| **Notifications** | `STAFF_CHILD_ASSIGNED` |
| **Final Result** | الأخصائي مسؤول عن هذا الطفل في هذه الخدمة — **شرطُ بدء الجلسة** |
| **Status** | 🟡 موصول بلا قواعد |

**الناقص المُثبت:** لا شيء يفحص أن الأخصائي **يقدّم** هذه الخدمة
(`therapist_services`)، ولا أن الطفل نشط، ولا يمنع إسنادين متعارضين. القواعد
موجودة كبيانات ولا تُسأل. الباكلوج `HBH-049` (دالّة) و`HBH-013` (مسار).

---

## FL-04 · Booking Flow (الحجز)

| الحقل | القيمة |
|---|---|
| **Starting Point** | `/appointments` (شاشة اليوم) |
| **Actors** | RECEPTION · CENTER_ADMIN (`APPOINTMENT.BOOK`) |
| **Preconditions** | خدمة في الكتالوج · أخصائي له `therapist_services` و`therapist_working_hours` · غرفة (إن `IN_PERSON`) |
| **Backend** | `GET /appointments/slots` → `POST /appointments/validate` → `POST /appointments` |
| **Entities** | `appointments` · `appointment_status_history` · `meetings` (إن `ONLINE`) |
| **Notifications** | `APPOINTMENT_BOOKED` / `APPOINTMENT_RESCHEDULED` · `STAFF_APPOINTMENT_BOOKED` · SMS `APPOINTMENT_BOOKED` |

```mermaid
flowchart TD
  A[اختر أخصائي + خدمة + يوم] --> B[available_slots]
  B --> C[لكل مرشّح: validate_slot]
  C --> D{مقبول?}
  D -->|لا| E[REASON: OUTSIDE_HOURS · ROOM_BUSY ·<br/>THERAPIST_BUSY · BLOCKED · NOT_OFFERED ·<br/>SERVICE_NEEDS_ROOM · UNKNOWN]
  D -->|نعم| F[الفتحة تُعرض]
  F --> G[book_appointment]
  G --> H{EXCLUDE USING gist}
  H -->|تصادم| I[HB021 / HB022]
  H -->|حرّ| J[appointments · BOOKED · APT-YYYY-NNNNN]
  J --> K{delivery_mode}
  K -->|IN_PERSON| L[room_id مطلوب]
  K -->|ONLINE| M[room_id يجب أن يكون NULL<br/>+ trg_appointment_meeting ينشئ meetings]
```

**قاعدة معمارية لا تُنقض:** **الحجز المزدوج يُمنَع بقيد استبعاد داخل جدول واحد.**
جدولٌ ثانٍ للاستشارات يمنح وقت الأخصائي **مصدرين** ولا شيء في المحرّك يستطيع أن
يمنع استشارةً وجلسةَ علاج في نفس الدقيقة. **ولهذا الاستشارة الأونلاين موعدٌ في
نفس الجدول** (`D-13` · `0117`).

**Exception Flow:** `ALLOW_BACKDATED_BOOKING_DAYS` يحكم الحجز بأثر رجعي ·
`SLOT_GRANULARITY_MIN` (١٥) يحكم دقّة الفتحة · `block_conflicts` يحترم
`schedule_blocks`.

---

## FL-05 · Appointment Status Flow

```mermaid
stateDiagram-v2
  [*] --> BOOKED
  BOOKED --> CONFIRMED
  BOOKED --> CANCELLED
  BOOKED --> NO_SHOW
  CONFIRMED --> CHECKED_IN
  CONFIRMED --> CANCELLED
  CONFIRMED --> NO_SHOW
  CHECKED_IN --> COMPLETED
  CHECKED_IN --> CANCELLED
  COMPLETED --> [*]
  CANCELLED --> [*]
  NO_SHOW --> [*]
```

| الحقل | القيمة |
|---|---|
| **Backend** | `PATCH /api/v1/appointments/{id}/status` |
| **Enforcement** | `trg_appointment_status` (BEFORE) + `legal_appointment_transition` — الرفض `HB020` |
| **History** | `trg_appointment_history` (AFTER) — **الآلة تعمل قبل التاريخ، فانتقالٌ غير قانوني لا يخلّف أثرًا على الصفّ** |
| **Permissions** | `APPOINTMENT.BOOK` للتأكيد والحضور · `APPOINTMENT.CANCEL` للإلغاء |
| **Notifications** | `APPOINTMENT_CANCELLED` · `STAFF_APPOINTMENT_CANCELLED` (**معرَّف وغير مُرسَل**) |

> 🔴 **درس محرّك:** جملةٌ تنقل موعدًا من `BOOKED` إلى `CONFIRMED` ثم إلى `CHECKED_IN`
> **تتركه عند `CONFIRMED`** — الصفّ لا يُحدَّث إلّا مرّة واحدة في الجملة الواحدة،
> والثاني يُهمَل **بصمت**. فيُرفض الاختبار التالي بـ`HB024` بدل `HB023`: **رفضٌ
> للسبب الخطأ لا يثبت شيئًا. كل انتقال حالة جملة مستقلّة.**

---

## FL-06 · Session Flow (الجلسة)

| الحقل | القيمة |
|---|---|
| **Starting Point** | `/my-day` (الأخصائي) أو `/sessions` |
| **Actors** | THERAPIST (`SESSION.START` · `SESSION.COMPLETE`) |
| **Preconditions** | الموعد `CHECKED_IN` · الخدمة `creates_session_flg` · وصفّ `caseload` إن `needs_caseload_flg` |
| **Backend** | `POST /appointments/{id}/session` → `PUT /sessions/{id}/note` → `PATCH /sessions/{id}/close` |
| **Entities** | `therapy_sessions` · `session_status_history` · `session_notes` · `stream_tokens` |
| **Statuses** | `IN_PROGRESS → COMPLETED` \| `ABORTED` |
| **Final Result** | جلسة مغلقة · موعد `COMPLETED` · ملاحظة `INTERNAL` |

```mermaid
flowchart TD
  A[موعد CHECKED_IN] --> B{can_start_session}
  B -->|لا caseload| C[HB023]
  B -->|الخدمة لا تُنشئ جلسة| D[HB251 SERVICE_NEEDS_ROOM]
  B -->|ليس IN_PERSON مع خدمة تحتاج غرفة| E[HB250 NOT_IN_PERSON]
  B -->|مسموح| F[start_session → therapy_sessions IN_PROGRESS]
  F --> G[البثّ المباشر اختياريًّا]
  F --> H[write_session_note → INTERNAL]
  F --> I{can_close_session}
  I -->|إكلينيكي| J[صاحب الجلسة فقط]
  I -->|إداري| K[user_type = STAFF]
  J --> L[close_session]
  K --> L
  L --> M[COMPLETED أو ABORTED]
  M --> N[الموعد CHECKED_IN → COMPLETED]
  M -.->|غير موصول| O[خصم الباقة]
  M --> P[NPS مستحقّ · SESSION_COMPLETED]
```

**Exception Flow:** `HB026` ليست جلستك · انتقال غير قانوني `HB025`.
> **الجلسة تُولد عند البدء، لا قبله.** لا صفّ في `therapy_sessions` قبل ضغط
> «ابدأ» — راجع 17.

---

## FL-07 · Live Viewing Flow (البثّ)

| الحقل | القيمة |
|---|---|
| **Starting Point** | بوّابة `/live` · كونسول `/sessions/:id/live` |
| **Actors** | GUARDIAN (بموافقة `LIVE_VIEW`) · THERAPIST · CENTER_ADMIN |
| **Preconditions** | جلسة `IN_PROGRESS` · كاميرا مربوطة بغرفة الموعد · موافقة مسجَّلة · `LIVE.VIEW` |
| **Backend** | `POST /sessions/{id}/stream` → كوكي `HttpOnly` → ترحيل البايتات → `POST /stream/close` |
| **Entities** | `cameras` · `stream_tokens` · `stream_views` · `consents` |

```mermaid
flowchart LR
  A[وليّ الأمر يفتح /live] --> B{can_view_live}
  B -->|لا موافقة LIVE_VIEW| C[رفض صريح تتصرّف به الشاشة]
  B -->|الجلسة ليست IN_PROGRESS| D[رفض]
  B -->|مسموح| E[issue_stream_token<br/>32 بايت · SHA-256 عند التخزين]
  E --> F[كوكي HttpOnly — لا يلمس JavaScript]
  F --> G[الخدمة تُرحّل البايتات من البوّابة]
  G --> H[stream_views · ختم بدء]
  H --> I{إغلاق}
  I -->|صراحةً| J[revoke_stream_token]
  I -->|الجلسة انتهت| K[close_session_streams]
  I -->|الصيانة| L[run_maintenance يُبطل توكنات جلسة غير IN_PROGRESS]
```

**لا يظهر في أي ردّ:** توكن · مسار كاميرا · عنوان IP · اعتماد. ١٨ فحصًا تثبت ذلك.

---

## FL-08 · Clinical Record Flow (الخطة والقياس والملاحظة والتقرير)

```mermaid
flowchart TD
  C[(الطفل)] --> P[treatment_plans · DRAFT]
  P -->|PLAN.MANAGE| PA[ACTIVE]
  PA --> G[plan_goals]
  G --> M[goal_measurements · GOAL.MEASURE]
  M --> VG[v_goal_progress]
  VG --> PORTAL1[بوّابة /progress]

  S[(الجلسة)] --> N[session_notes · INTERNAL]
  N -->|NOTE.PUBLISH| NP[PARENT]
  NP --> PORTAL2[بوّابة — ملاحظات]

  C --> R[progress_reports · DRAFT · REPORT.WRITE]
  R -->|REPORT.PUBLISH| RP[PUBLISHED · مجمَّد HB033]
  RP --> PORTAL3[بوّابة /reports]

  C -.->|لا مسار| A[assessments · DRAFT → COMPLETED → PUBLISHED]
  A -.-> PORTAL4[بوّابة — لا شيء يصل]

  PA -->|ACTIVE → COMPLETED / CANCELLED| PE[نهاية الخطة]
```

**سلّم الرؤية — ١١ فحصًا في مجموعة الـAPI:**

| الأثر | ما تراه الأسرة |
|---|---|
| ملاحظة جلسة | `visibility = PARENT` **و** ليست مسودّة **و** لها معتمِد — **وكل ملاحظة تُولد `INTERNAL`** |
| تقرير تقدّم | `PUBLISHED` وحده |
| تقييم | `PUBLISHED` وحده — ولا مسار يصنعه |

> **الملاحظة الداخلية لا تصل، ومسودّة التقرير عن طفله هو تُجيب `404`** — وليس `403`،
> لأن `403` تخبر بوجود ما لا يجوز له معرفته.

---

## FL-09 · Home Programme Flow (البرنامج المنزلي)

```mermaid
flowchart LR
  T[الأخصائي] -->|يصف| CA[child_activities]
  CA --> LIB[(activity_library)]
  CA --> PORTAL[بوّابة /activities]
  PORTAL -->|وليّ الأمر يسجّل| LOG[activity_log]
  LOG --> UQ{فهرس فريد<br/>نشاط واحد · يوم واحد}
  UQ -->|تكرار| X[مرفوض]
  LOG --> ADH[v_activity_adherence]
  ADH --> T
```

**الخطّ:** الأهل **يسجّلون** ولا **يصفون**. وليّ أمر يستطيع تعديل الوصفة يستطيع
أن يعيد كتابة البرنامج بهدوء ثم يبلّغ التزامًا كاملًا به.

---

## FL-10 · Billing Flow (الفاتورة)

```mermaid
stateDiagram-v2
  [*] --> DRAFT
  DRAFT --> ISSUED : issue_invoice · BILLING.MANAGE
  DRAFT --> CANCELLED
  ISSUED --> PARTIALLY_PAID : دفعة < الإجمالي
  ISSUED --> PAID : دفعة = الإجمالي
  ISSUED --> CANCELLED
  PARTIALLY_PAID --> PAID
  PARTIALLY_PAID --> CANCELLED
  PAID --> [*]
  CANCELLED --> [*]
```

| الحقل | القيمة |
|---|---|
| **Screens** | `billing-overview.ts` · `billing-ledger.ts` · `INVOICES_SPEC` · بوّابة `/billing` |
| **Backend** | `POST /invoices` → `POST .../lines` → `POST .../issue` → `POST .../payments` |
| **Entities** | `invoices` · `invoice_lines` · `payments` · `v_child_balance` |
| **Notifications** | `INVOICE_ISSUED` |

**قواعد:** **الإجمالي مشتقّ ولا يُدخَل** — مشغّل من البنود، و`paid_amt` من الدفعات.
`trg_line_guard` يمنع تعديل بنود فاتورة صادرة. `trg_payment_guard` يمنع دفعة على
مسوّدة (`HB052`). والفاتورة `PAID` لا تعود.
**والباقة:** `sell_package` تكتب رصيدًا و`package_ledger` مضاف-فقط — **ولا شيء
يخصم**. راجع 18 · C-01.

---

## FL-11 · Parent Request Flow (الطلبات)

```mermaid
flowchart LR
  P[وليّ الأمر] --> K{النوع}
  K --> RS[RESCHEDULE]
  K --> CN[CANCEL]
  K --> CB[CALLBACK]
  RS --> REQ[parent_requests · NEW · REQ-YYYY-NNNNN]
  CN --> REQ
  CB --> REQ
  REQ -->|لا مفتاح أجنبي يحرّك حجزًا| NOOP[لا موعد يتغيّر]
  REQ --> RC[الاستقبال · REQUEST.MANAGE]
  RC --> D{decide_request}
  D --> ACC[ACCEPTED]
  D --> REJ[REJECTED]
  ACC --> NTF[REQUEST_DECIDED → البوّابة]
  REJ --> NTF
  ACC -.->|باليد| BOOK[الاستقبال ينقل الموعد فعلًا]
```

**«الطلب ليس فعلًا»** — والبتّ **لا ينقل الموعد تلقائيًّا**؛ الاستقبال ينقله بيده
بعد القبول. راجع `OQ-08` أدناه.

---

## FL-12 · Online Consultation Flow (الاستشارة)

| الحقل | القيمة |
|---|---|
| **Starting Point** | الاستقبال يحجز موعدًا `delivery_mode = 'ONLINE'` |
| **Actors** | **وليّ الأمر هو الحاضر، لا الطفل** — وهذه وحدها تكسر ثلاثة افتراضات |
| **Preconditions** | خدمة بـ`creates_session_flg = false` · موعد `CONFIRMED` · نافذة الوقت فُتحت |
| **Backend** | `POST /appointments/{id}/consultation` |
| **Entities** | `appointments` · `meetings` · `meeting_tokens` |

```mermaid
flowchart TD
  A[حجز ONLINE · لا غرفة] --> B[trg_appointment_meeting → meetings]
  B --> C[وليّ الأمر يفتح /consultation/:appointmentId]
  C --> D{authorize_meeting_entry — PL/pgSQL}
  D -->|الموعد غير مؤكَّد| E[HB253 NOT_CONFIRMED]
  D -->|قبل النافذة| F[HB252 NOT_YET_OPEN]
  D -->|غير موجود| G[HB240-family NOT_FOUND]
  D -->|مسموح| H[Grant: roomRef · provider · moderator · expiresAt]
  H --> I[meeting.Mint — توقيع JWT بمفتاح JaaS]
  I --> J[record_meeting_token]
  J --> K[المتصفّح يتفاوض مع Jitsi مباشرةً]
```

**الحدّ المعماري:** `meeting.Mint` **لا تأخذ إلّا `Grant`**، والشيء الوحيد الذي
يبنيه هو دالّة المخزن التي تنادي القاعدة. **لا طريق مُصدَّر لقول «أعطني توكنًا
للغرفة X»** — ذلك بابٌ ثانٍ بجوار الباب الذي عليه كل الفحوص.
**والحزمة لا تعرف ما هو الطفل** — القاعدة ٢.

**الناقص:** لا شاشة كونسول يدخل منها الأخصائي · لا جدول `consultation_requests` ·
ولا طريق يجعل `registration_source = 'ONLINE_CONSULTATION'` قيمةً يكتبها أحد.

---

## FL-13 · Staff Onboarding & Access Flow

```mermaid
flowchart TD
  A[CENTER_ADMIN · /access] --> B[create_user · USER.MANAGE]
  B --> C[set_user_roles]
  C --> D[issue_password_setup → رابط عمره 1440 دقيقة]
  D --> E[الموظّف يفتح الرابط]
  E --> F[redeem_password_setup → set_password]
  F --> G[دخول بـ/auth/staff/login]
  G --> H[auth_sessions]
  A --> I[staff_profiles + staff_documents · STAFF.PII]
  A --> J[PUT /roles/:code/permissions · set_role_permissions]
  J --> K{guard_last_admin}
  K -->|آخر USER.MANAGE| L[مرفوض]
  A --> M[DELETE /users/:id — أرشفة لا حذف]
  M --> N[trg_revoke_sessions_on_offboard → إبطال كل جلساته]
```

---

## FL-14 · Site Content & Publish Flow

```mermaid
flowchart LR
  A[CENTER_ADMIN · /site · /site/team] -->|SITE.EDIT| B[12 جدول site_*]
  B --> C{SITE.PUBLISH}
  C -->|نشر| D[trg_site_publish_stamp]
  D --> E[scripts/site-export.sh]
  E --> F[site/ — ملفّات ثابتة]
  F --> G[site.native.mjs · قائمة سماح لأنواع الملفّات]
  G --> H[الإنترنت المفتوح]
  B --> I[موافقة صاحب الشهادة/الوسيط<br/>trg_site_consent_stamp]
  I -->|بلا موافقة| J[محجوب عن النشر]
```

**الأمان هنا سلبيّ لا إيجابيّ:** لا شيء في هذا السطح يمرّر إلى الخدمة — و
**بندُ بطاقة النشر الأوّل ليس تصميمًا بل `grep` مسجَّل على `proxy_pass`.**
> **واختبار النشر يسأل عمّا يجب ألّا يُجاب، لا عمّا يجب أن يُجاب:** `/` بـ`200` لا
> يثبت شيئًا، و`/api/v1/...` بغير `404` يثبت كل شيء.

---

## الفلوهات المقطوعة — ملخَّص

| الفلو | القطع | الدليل |
|---|---|---|
| **قائمة الانتظار** | صفر مسار فوق ٧ دوالّ | `grep add_to_waiting_list api/ web/` = ٠ |
| **الحجز المتكرّر** | صفر مسار فوق `book_recurring` | كذلك |
| **التقييمات** | صفر مسار فوق ٤ جداول و٦ دوالّ | كذلك |
| **المرفقات** | صفر مسار عامّ (عدا صورة الطفل) | كذلك |
| **خصم الباقة** | صفر منادٍ لـ`consume_package_session` في أي طبقة | `grep` على db و api و web |
| **إغلاق الجدول** | `schedule_blocks` تُقرأ ولا تُكتب | ليست في `store.Resources()` |
| **حساب بوّابة لأسرة من المركز** | لا مسار لـ`grant_portal_access` | يُنادى من `convert_enrolment` وحده |
| **الخطّ الزمني للحالة** | `v_case_timeline` بلا قارئ | `HBH-045` |
| **تنبيه التوقّف الصامت** | `v_backup_health` · `v_maintenance_health` · `v_sms_health` بلا قارئ | `HBH-008` |

---

## OPEN QUESTIONS

| # | السؤال | الأثر |
|---|---|---|
| **OQ-08** | قبول طلب `RESCHEDULE` — هل يُنقل الموعد تلقائيًّا أم يبقى نقلًا يدويًّا؟ ومن يتحمّل لو نُسي؟ | FL-11 · FL-04 · الإشعار · ثقة الأسرة |
| **OQ-09** | هل يجوز إلغاء موعد **مؤكَّد** بعد الدفع؟ وما أثره على الفاتورة والباقة والاسترداد؟ | FL-05 · FL-10 · F-35 |
| **OQ-10** | من يملك بدء الاستشارة الأونلاين من جهة المركز، ومن أي شاشة؟ | FL-12 · F-36 |
| **OQ-11** | جلسة `ABORTED` — هل تُحتسَب على الأسرة (باقةً أو فاتورةً)؟ | FL-06 · FL-10 |
