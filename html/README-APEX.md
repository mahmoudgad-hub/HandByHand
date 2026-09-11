# واجهات HTML — تطبيق العمليات + بوابة ولي الأمر

نماذج ثابتة (Mock-ups) بتصميم Hand By Hand، جاهزة للمعاينة في المتصفح ولِلَّصق داخل APEX 26.1.
لا JavaScript، لا مكتبات خارجية، لا Bootstrap — CSS و SVG فقط، RTL عربي.

## الشاشات

| الصفحة | التطبيق | الوصف |
|---|---|---|
| `admin-dashboard.html` | العمليات | لوحة تحكم المركز: مؤشرات اليوم، توزيع الجلسات، حالة الغرف، التنبيهات |
| `child-profile.html` | العمليات | ملف الطفل: الهوية، الأهداف، نسبة إنجاز الخطة، آخر تقدّم، آخر الجلسات |
| `appointments.html` | العمليات | التقويم الأسبوعي (الأحد→الخميس + عطلة الجمعة والسبت)، بانتظار التأكيد، التعارضات |
| `sessions-management.html` | العمليات | إدارة الجلسات: تبويبات العرض، فلاتر، جدول اليوم بحالات ملوّنة |
| `therapists.html` | العمليات | بطاقات الأخصائيين: جلسات اليوم، الأطفال، التقييم، نسبة الإشغال |
| `rooms-cameras.html` | العمليات | الغرف والكاميرات: شبكة 6 غرف بحالة بث لكل كاميرا |
| `live-view.html` | العمليات | البث المباشر: مشغّل، أدوات تحكّم، لحظات مهمة، سجلّ المشاهدة، حالة البث |
| `reports.html` | العمليات | التقارير: تبويبات النوع، فلاتر، جدول بحالات (مسودة ← اعتماد ← إرسال) |
| `billing.html` | العمليات | الفواتير: مؤشرات مالية، جدول الفواتير، أعمدة ضريبة محايدة الدولة |
| `communications.html` | العمليات | التواصل: قائمة محادثات + خيط رسائل + قوالب وتذكيرات |
| `leads.html` | العمليات | العملاء المحتملون: لوحة كانبان بخمس مراحل + مؤشرات التحويل |
| `settings.html` | العمليات | الإعدادات: قيم `HBH_CENTERS` و`HBH_SYS_PARAMS` مع القرارات المُقفلة |
| `parent-portal.html` | ولي الأمر | نسخة ويب مستجيبة: عمودان على الديسكتوب، عمود واحد + شريط سفلي على الموبايل |
| `parent-welcome.html` | ولي الأمر | شاشة الترحيب — أول شاشة بعد تسجيل الدخول: تحيّة باسم ولي الأمر، اختيار الطفل، وثلاث مستجدّات، ثم الدخول للبوابة |


> **`parent-welcome.html` ليست ملفًا ثابتًا في APEX.** الشاشة الحيّة تُرسَم من
> `HBH_PKG_UI.parent_welcome_html` في Region من نوع `PL/SQL Dynamic Content`،
> لأن محتواها كله بيانات لكل ولي أمر. الملف هنا هو المرجع البصري لها.
> الخطوات كاملة في [`docs/13-apex-parent-app-setup.md`](../docs/13-apex-parent-app-setup.md).

## ملفات التنسيق

| الملف | الغرض |
|---|---|
| `hbh-shared.css` | متغيّرات الهوية + المكوّنات المشتركة (بطاقة، Badge، زر، أيقونة) — **كل لون في المشروع معرّف هنا** |
| `hbh-admin.css` | هيكل تطبيق العمليات (شريط جانبي + محتوى) ولوحة التحكم |
| `hbh-screens.css` | مكوّنات الشاشات الداخلية (تبويبات، جداول، بطاقات غرف، مشغّل البث) |
| `hbh-parent.css` | بوابة ولي الأمر + شاشة الترحيب  |

كل الـ CSS مُغلَّف داخل `.hbh-app` حتى لا يتعارض مع Universal Theme.

## الشعار

| الملف | الاستخدام |
|---|---|
| `hbh-logo-mark.png` | الرمز (الدائرة + الفقاعة + الأطفال + الكفّان) — 256×261 |
| `hbh-logo-wordmark.png` | الكلمات (hand by hand / skills center / communicate • connect • grow) — 420×164 |

- الاتنين **PNG بخلفية شفافة** ومقصوصين على حدود المحتوى بالضبط، فيشتغلوا على أي لون خلفية.
- مُجهَّزين من ملفات العميل في `assets/source/`: شِلت الخلفية البيضا، قصّيت الهوامش، وصغّرت المقاس (350KB ← 118KB) لأن مساحة السكيما محدودة.
- **الشعار صورة نقطية مش متجه** — يعني مش هينفع نعيد تلوينه من الـ CSS، وهيبدأ يتنعّم فوق ضعف مقاسه.
- قفل الشعار بيحتفظ بترتيبه الأصلي: الحاويات فيها `direction:ltr` عشان الرمز يفضل على شمال الكلمات حتى في صفحة RTL.
- الـ wordmark فيه نص رمادي غامق، فمحتاج خلفية فاتحة. على الشريط الجانبي الفيروزي القفل كله موضوع على لوحة بيضا (`.hbh-side__brand`).
- في APEX ارفعهما كـ Static Application Files واستخدم `#APP_FILES#hbh-logo-mark.png` و `#APP_FILES#hbh-logo-wordmark.png`.

### بديل نصّي للكلمات
لسه موجود في الـ CSS للحالات اللي الصورة مش بتنفع فيها (نسخة عربية، بريد، طباعة):
```html
<span class="hbh-wm"><b>Hand</b> <i>by</i> <em>Hand</em></span>
```
`b` فيروزي · `i` أخضر · `em` مرجاني. على خلفية غامقة ضيف `hbh-wm--on-dark`.

## بنية المصادر والبناء

```
html/
  src/                  ← المصادر التي تُعدَّل
  parts/
    hbh-icons-sprite.html   مجموعة الأيقونات (مصدر واحد)
    hbh-sidebar.html        الشريط الجانبي (مصدر واحد)
  build.sh              ← يولّد الصفحات ومقاطع APEX
  *.html                ← صفحات المعاينة (مُولَّدة)
  apex-region/*.region.html  ← محتوى Region فقط (مُولَّد)
```

عدّل داخل `src/` و`parts/` ثم شغّل:

```bash
bash build.sh
```

العلامات داخل ملفات `src`:

| العلامة | ما يحلّ محلّها |
|---|---|
| `ICONS` | محتوى `parts/hbh-icons-sprite.html` |
| `SIDEBAR:key` | الشريط الجانبي مع تفعيل العنصر صاحب `data-nav="key"` |
| `REGION-START` … `REGION-END` | حدود ما يُستخرج إلى `apex-region/` |

> ملاحظة: لا تكتب هذه العلامات كنص داخل تعليق HTML آخر — `-->` يُنهي التعليق مبكرًا ويظهر الباقي كنص على الصفحة.

## المعاينة المحلية

افتح أي ملف `.html` من داخل مجلّد `html/` مباشرة بالمتصفح — ملفات الـ CSS مرتبطة نسبيًا.

## التركيب في APEX

1. **رفع ملفات الـ CSS**
   `Shared Components ▸ Static Application Files ▸ Upload`

2. **ربط الملفات بالتطبيق**
   `Shared Components ▸ User Interface Attributes ▸ Cascading Style Sheets ▸ File URLs`

   تطبيق العمليات:
   ```
   #APP_FILES#hbh-shared.css
   #APP_FILES#hbh-admin.css
   #APP_FILES#hbh-screens.css
   ```
   بوابة ولي الأمر:
   ```
   #APP_FILES#hbh-shared.css
   #APP_FILES#hbh-parent.css
   ```

3. **ما يوضع مرة واحدة في Page Template ▸ Body**
   - محتوى `parts/hbh-icons-sprite.html` (مجموعة الأيقونات).
   - محتوى `parts/hbh-sidebar.html` لتطبيق العمليات — أو أعِد بناءه كـ Navigation Menu حقيقية.
   لا تكرّرهما داخل كل صفحة.

4. **ما يوضع في كل صفحة**
   - أنشئ صفحة فارغة، `Template = Minimal (No Navigation)`.
   - أضف **Static Content Region** بقالب **Blank with Attributes**.
   - ألصق محتوى `apex-region/<الصفحة>.region.html` في `Source ▸ HTML Code`.

5. **الاتجاه واللغة**
   في `Shared Components ▸ Globalization` اجعل اللغة الأساسية عربية.
   إن لم يضبط قالب الصفحة `dir="rtl"`، أضف في `Page ▸ JavaScript ▸ Execute when Page Loads`:
   ```js
   document.documentElement.setAttribute('dir','rtl');
   document.documentElement.setAttribute('lang','ar');
   ```
   للتحويل إلى الإنجليزية LTR غيّر القيمة إلى `ltr` — كل التنسيقات تستخدم `inset-inline` و `margin-inline` فتنعكس تلقائيًا.

6. **الخط**
   `hbh-shared.css` يستدعي IBM Plex Sans Arabic من Google Fonts عبر `@import`.
   إذا منع المزوّد النداءات الخارجية، نزّل ملفات `.woff2` وارفعها كـ Static Application Files
   واستبدل الـ `@import` بـ `@font-face` تشير إلى `#APP_FILES#`.

## ربط البيانات (الخطوة التالية)

الأرقام الحالية بيانات عرض ثابتة. عند الربط الفعلي:

- **بطاقات المؤشرات** ← `Cards Region` على View مثل `HBH_VW_DASH_KPI`، أو Static Content مع عناصر صفحة `&P1_XXX.` تُملأ من `Pre-Rendering Process`.
- **الرسوم الدائرية** (توزيع الجلسات، نسبة إنجاز الخطة) ← **Chart Region** نوع Donut / Radial من Oracle JET. الـ `<svg>` هنا للـ Mock-up فقط — قاعدة `CLAUDE.md`: لا مكتبات رسم خارجية.
- **جداول الجلسات** ← `Interactive Report` أو `Interactive Grid` مع Faceted Search بدل الفلاتر الثابتة.
- **بطاقات الغرف** ← `Cards Region` بنفس أسماء الـ CSS classes.
- **العملة** ← من `HBH_CENTERS.CURRENCY_CODE` (مصر = `EGP`)، لا تُكتب ثابتة.
- **التاريخ والوقت** ← بتوقيت `Africa/Cairo` وتقويم ميلادي.

## ملاحظات أمنية مثبَّتة في الترميز

- بوابة ولي الأمر لا تقرأ إلا من `HBH_VWS_*` — ممنوع أي استعلام مباشر على جدول `HBH_*` من تطبيق 200.
- زر «شاهد طفلك مباشرة» وأزرار «عرض مباشر» في تطبيق العمليات كلها واجهة فقط. الصلاحية تُفرض في `HBH_PKG_SEC.assert_can_access_child` وبتوكن بث معتِم ≤ 15 دقيقة مربوط بالجلسة والكاميرا والمستخدم. إخفاء الزر ليس وسيلة تحكّم.
- لا يوجد أي تسجيل للفيديو. «تحديد لحظة مهمة» يُنشئ ملاحظة إكلينيكية بتوقيت داخل الجلسة، ولا يشير إلى أي مقطع محفوظ — والنص في الصفحة يوضّح ذلك.
- صفحة الغرف والكاميرات لا تعرف عناوين RTSP ولا IP ولا كلمات مرور — مسار البوابة ومرجع الاعتماد فقط.
- تغيير حالة الجلسة يمرّ بـ `HBH_PKG_SCHED` (آلة حالات + جدول تاريخ)، لا `UPDATE` مباشر من الصفحة.
- كل فتح لملف طفل أو تقرير أو بث يُسجَّل صراحةً — المشغّلات لا تلتقط عمليات القراءة.
- لا معرّف طفل في الروابط؛ استخدم عنصر صفحة محميًّا بـ Session State Protection وليس Query String.

## لوحة التحكم: من Mock-up إلى Region حيّ

`admin-dashboard.html` لم يعد يُلصق في APEX. الصفحة الآن **Region واحد** نوعه
`PL/SQL Dynamic Content` ومصدره سطر واحد:

```
HBH_PKG_UI.render_admin_dashboard;
```

الترميز نفسه يعيش في `db/05_packages/11_hbh_pkg_ui.sql` داخل المستودع، والأرقام
تأتي من `db/04_views/09_ui_views.sql`. السبب: لو لُصق الـ HTML في Static Content
لخرج التصميم من المستودع، وبقيت كل الأرقام ثابتة، وتوقّف `db/hbh_code_refresh.sql`
عن تحديث ما يراه المستخدم فعلًا.

### التركيب
1. شغّل `db/hbh_ui_install.sql` (SQL Workshop ▸ SQL Scripts ▸ Upload ▸ Run).
   يجب أن ينتهي بـ `UI LAYER ACCEPTED`.
2. صفحة 1 في تطبيق 115: Region واحد، النوع `PL/SQL Dynamic Content`،
   قالب Region = `Blank with Attributes`، والمصدر هو السطر أعلاه.
3. الـ CSS وشريط الأيقونات كما في الخطوات 1 إلى 3 بالأعلى.

### ما يظهر كشرطة `—` عمدًا
بطاقتا «رضا أولياء الأمور» و«العملاء المحتملون» لا يوجد لهما جدول قبل المرحلة
العاشرة. الشاشة تعرض شرطة وملاحظة بدل رقم مُختلَق — رقم يبدو معقولًا وجاء من
العدم أضرّ من فراغ ظاهر.

### قاعدتان تعلّمناهما أثناء التركيب
- **لا إيموجي في كود PL/SQL.** الرمز 👋 محرف خارج الـ BMP (أربعة بايت)، والمصدر
  يمرّ برفع عبر المتصفح ثم تخزين في `USER_SOURCE` قبل أن يراه أحد. بايت واحد
  يتشوّه ويسقط الحزمة كلها. الإيموجي مكانه البيانات لا الكود.
- **الفاصلة العربية `،` داخل قناع تاريخ يجب أن تُحاط بعلامتَي تنصيص مزدوجتين.**
  `TO_CHAR(d, 'fmDay، ...')` ترفع `ORA-01821`؛ الصحيح `'fmDay"،" ...'`.
  قناع التاريخ يقبل مجموعة ترقيم محدّدة فقط، و`U+060C` ليست منها.

### ما تم فعليًا في تطبيق 115 (2026-08-31)
| الخطوة | الحالة |
|---|---|
| `HBH_VW_DASH_KPI` / `HBH_VW_DASH_ALERTS` / `HBH_VW_DASH_ALERT_CNT` | مثبَّتة |
| `HBH_PKG_UI` (Package + Body) | **VALID**، والـ render يعمل |
| صفحة 1 ▸ Region «لوحة التحكم» نوع `Dynamic Content`، القالب `Blank with Attributes`، المصدر `RETURN HBH_PKG_UI.admin_dashboard_html;` | تم |
| `Shared Components ▸ User Interface Attributes ▸ CSS ▸ File URLs` = `hbh-shared.css` + `hbh-admin.css` + `hbh-screens.css` | تم |
| `Globalization ▸ Document Direction = Right-To-Left` | تم |
| شريط الأيقونات | لم يعد خطوة يدوية — `HBH_PKG_UI.icon_sprite` يُخرجه مرة واحدة لكل طلب |

**قرار مفتوح:** `Application Primary Language` لسه `English (en)`. الاتجاه RTL مضبوط
فالتصميم يظهر صح، لكن لو عايزين العربية تبقى اللغة الأساسية والإنجليزية طبقة
مترجَمة (زي ما في `CLAUDE.md`) فدة قرار يخص نموذج الترجمة كله — يتاخد صراحةً
مش كأثر جانبي لتعديل تنسيق.

## بنية الصفحات في تطبيق 115 — الحالة الفعلية 2026-08-31

**القاعدة:** الكارت الواحد = region واحد. والقائمة التي يفلترها الناس ويفرزونها
ويصدّرونها = **Interactive Report** على `HBH_VW_*`، لا PL/SQL.

### صفحة 1 — لوحة التحكم (خمسة regions)
| الترتيب | الاسم | المصدر | التخطيط |
|---|---|---|---|
| 10 | مؤشرات اليوم | `RETURN HBH_PKG_UI.dash_kpis_html;` | صف كامل |
| 20 | جدول اليوم | `RETURN HBH_PKG_UI.dash_today_html;` | صف جديد · Span 4 |
| 30 | حالة الغرف | `RETURN HBH_PKG_UI.dash_rooms_html;` | نفس الصف · Span 4 |
| 35 | التنبيهات | `RETURN HBH_PKG_UI.dash_alerts_html;` | نفس الصف · Span 4 |
| 40 | مؤشرات الأداء | `RETURN HBH_PKG_UI.dash_stats_html;` | صف كامل |

النوع في كلها `Dynamic Content` والقالب `Blank with Attributes`.
الصف الثلاثي من **Column Span** بتاع APEX، لا من CSS grid مكتوب بإيدنا.

### صفحة 4 — الغرف والكاميرات
region واحد: `RETURN HBH_PKG_UI.cameras_html;`
يقرأ `HBH_VW_CAMERAS` (بلا `IP_ADDRESS` ولا `CREDENTIAL_REF`) ويطبع تحذيرًا
ظاهرًا طالما `MEDIA_GATEWAY_IS_TEMPORARY_FLG='Y'`.

### الشاشات الباقية والشكل المقترح لكل واحدة
| الشاشة | الشكل | المصدر |
|---|---|---|
| الجلسات | Interactive Report | `HBH_VW_SESSIONS` |
| الفواتير | IR + شريط مؤشرات PL/SQL | `HBH_VW_INVOICES` |
| الأخصائيون | Cards Region | عرض على `HBH_THERAPISTS` |
| التقارير | Interactive Report | `HBH_VW_PROGRESS_REPORTS` |
| المواعيد | شبكة أسبوعية PL/SQL + IR لبانتظار التأكيد | `HBH_VW_APPOINTMENTS` |
| ملف الطفل | ترويسة PL/SQL + ثلاثة IR | عدة عروض |
| البث المباشر | PL/SQL — يحتاج توكن معتِم (P9b) | — |
| التواصل · العملاء المحتملون | مرحلة 10 — لا جداول بعد | — |

## الصفحات الباقية — جاهزة للإنشاء

كلها بنفس النمط: صفحة فارغة، ثم region واحد أو اثنان. **القائمة = Interactive
Report** على العرض مباشرة؛ لا تُرسَم جداول في PL/SQL.

### صفحة 6 — الأطفال · Interactive Report
```sql
SELECT CHILD_ID, CASE_NO, NAME_AR, AGE_LABEL_AR, GENDER_LABEL_AR,
       STATUS_LABEL_AR, PRIMARY_THERAPIST_AR, PRIMARY_DIAGNOSIS_AR,
       PRIMARY_GUARDIAN_AR, GUARDIAN_CNT, JOIN_DATE, MEDICAL_ALERT
FROM   HBH_VW_CHILDREN
WHERE  ACTIVE_FLG = 'Y'
```

### صفحة 7 — المواعيد · Interactive Report
```sql
SELECT APPT_NO, APPT_DATE, START_TIME, END_TIME, DURATION_MIN,
       CHILD_NAME_AR, CASE_NO, SERVICE_NAME_AR, THERAPIST_NAME_AR,
       ROOM_NAME_AR, STATUS_LABEL_AR, ATTENDANCE_STATUS, LATE_MIN,
       IS_CHARGEABLE_FLG, NOTES
FROM   HBH_VW_APPOINTMENTS
WHERE  ACTIVE_FLG = 'Y'
```

### صفحة 8 — الجلسات · Interactive Report
```sql
SELECT APPT_NO, APPT_DATE, SCHEDULED_START, CHILD_NAME_AR, CASE_NO,
       SERVICE_NAME_AR, RAN_BY_NAME_AR, ROOM_NAME_AR,
       ACTUAL_START_TS, ACTUAL_END_TS, DURATION_MIN,
       STATUS_LABEL_AR, IS_BILLABLE_FLG, COOPERATION_LEVEL, CHILD_MOOD_AR,
       NOTE_CNT, PUBLISHED_NOTE_CNT, ACTIVITY_CNT, MOMENT_CNT
FROM   HBH_VW_SESSIONS
```

### صفحة 9 — الأخصائيون · Dynamic Content
```
RETURN HBH_PKG_UI.therapists_html;
```
كروت لا IR **عن قصد**: القائمة تُقرأ كحائط وجوه وأحمال، اثني عشر شخصًا، لا
تُفلتَر ولا تُفرَز. أول ما يُطلب فرزها بتاريخ انتهاء الترخيص تتحوّل إلى IR
وتُحذف الدالة.

### صفحة 10 — الفواتير · region ثم IR
region 10 (Dynamic Content): `RETURN HBH_PKG_UI.billing_kpis_html;`
region 20 (Interactive Report):
```sql
SELECT INVOICE_NO, TYPE_LABEL_AR, INVOICE_DATE, DUE_DATE,
       CHILD_NAME_AR, GUARDIAN_NAME_AR, GUARDIAN_MOBILE,
       SUBTOTAL_AMT, DISCOUNT_AMT, TAX_AMT, TOTAL_AMT, CURRENCY_CODE,
       PAID_AMT, BALANCE_AMT, PAY_STATE_AR, DAYS_OVERDUE, LINE_CNT
FROM   HBH_VW_INVOICES
```

### صفحة 11 — التقارير · Interactive Report
```sql
SELECT REPORT_NO, TYPE_LABEL_AR, CHILD_NAME_AR, CASE_NO,
       THERAPIST_NAME_AR, PERIOD_FROM, PERIOD_TO,
       SESSIONS_SCHEDULED, SESSIONS_COMPLETED, SESSIONS_NO_SHOW,
       ATTENDANCE_PCT, OVERALL_PROGRESS_PCT,
       STATUS_LABEL_AR, AI_DRAFT_FLG, APPROVED_TS, PUBLISHED_TS
FROM   HBH_VW_PROGRESS_REPORTS
```

> **لماذا لا يوجد `CHILD_ID` في تقارير الأطفال المعروضة لولي أمر:** هذه الصفحات
> كلها لتطبيق العمليات (115). بوابة ولي الأمر لا تقرأ `HBH_VW_*` إطلاقًا — مصدرها
> الوحيد `HBH_VWS_*`، وشرط الربط داخل العرض نفسه.

### صفحة 7 — المواعيد: أضف region الأسبوع فوق الـ IR
region 10 (Dynamic Content): `RETURN HBH_PKG_UI.week_grid_html;`
عنصر صفحة `P7_WEEK_START` (نوع Hidden، اختياري) — فارغًا يعرض أسبوع اليوم.
أيام العمل تأتي من `HBH_PKG_CONFIG.day_type` لا من ثابت في الكود، فالعطلة
المصرية (الجمعة والسبت) **بيانات**؛ مركز يفتح السبت لا يحتاج تعديل كود.
واليوم غير العملي الذي عليه مواعيد يُقال صراحةً بالأحمر، لا يُخفى خلف شارة.

### صفحة 12 — ملف الطفل
عنصر صفحة `P12_CHILD_ID` (Hidden · Value Protected).
region 10 (Dynamic Content): `RETURN HBH_PKG_UI.child_header_html;`
ثم ثلاثة Interactive Reports مفلترة على نفس العنصر:

```sql
-- جلسات الطفل
SELECT APPT_DATE, SCHEDULED_START, SERVICE_NAME_AR, RAN_BY_NAME_AR,
       ROOM_NAME_AR, DURATION_MIN, STATUS_LABEL_AR, COOPERATION_LEVEL,
       CHILD_MOOD_AR, NOTE_CNT
FROM   HBH_VW_SESSIONS
WHERE  CHILD_ID = :P12_CHILD_ID
```
```sql
-- أهداف الخطة
SELECT GOAL_TEXT_AR, DOMAIN_NAME_AR, MEASURE_UNIT, BASELINE_VALUE, TARGET_VALUE, CURRENT_VALUE,
       PROGRESS_PCT, STATUS_LABEL_AR, TARGET_DATE, IS_OVERDUE_FLG
FROM   HBH_VW_PLAN_GOALS
WHERE  CHILD_ID = :P12_CHILD_ID
```
```sql
-- تقارير الطفل
SELECT REPORT_NO, TYPE_LABEL_AR, PERIOD_FROM, PERIOD_TO, ATTENDANCE_PCT,
       OVERALL_PROGRESS_PCT, STATUS_LABEL_AR, PUBLISHED_TS
FROM   HBH_VW_PROGRESS_REPORTS
WHERE  CHILD_ID = :P12_CHILD_ID
```
وفي صفحة 6 (الأطفال) اجعل عمود `NAME_AR` رابطًا إلى صفحة 12 يمرّر
`P12_CHILD_ID = #CHILD_ID#`.

**التنبيه الطبي يُطبع فوق كل شيء** قبل بطاقة الهوية وباللون الأحمر: هو الشيء
الوحيد في الشاشة الذي قد يغيّر ما يفعله أحدهم خلال الخمس دقائق القادمة.
وكل فتح لملف طفل يُسجَّل بـ `HBH_PKG_AUDIT.log_view` — المشغّلات لا ترى القراءة.

## أرقام الصفحات الفعلية في تطبيق 115 (2026-09-01)

APEX يرقّم الصفحات تلقائيًا، والأرقام أدناه هي **ما حدث فعلًا** لا ما خطّطنا له.
لا تعتمد على الأرقام في نص مكتوب — استخدم `APEX_PAGE.GET_URL`.

| صفحة | الاسم | المحتوى |
|---|---|---|
| 1 | Home | لوحة التحكم — خمسة regions |
| 4 | الغرف والكاميرات | `cameras_html` |
| 5 | بث مباشر | `live_view_html(:P5_CAMERA_ID)` · عنصر `P5_CAMERA_ID` |
| 6 | الأطفال | IR · عمود `NAME_AR` رابط لصفحة 17 يمرّر `P17_CHILD_ID=#CHILD_ID#` |
| 7 | المواعيد | IR |
| 10 | الجلسات | IR |
| 12 | تقارير التقدّم | IR |
| 14 | الفواتير | `billing_kpis_html` (seq 5) + IR (seq 10) |
| 16 | الأخصائيون | `therapists_html` |
| 17 | ملف الطفل | `child_header_html(:P17_CHILD_ID)` · عنصر `P17_CHILD_ID` |
| **18** | **حجز موعد — Modal** | ✅ **مبنيّة ومُختبَرة حيًّا 2026-09-01.** 8 عناصر · زرّان · DA تحقّق · معالجتان (`book` ثم Close Dialog). الزر في صفحة 7 يمين شريط البحث، ومعه `Dialog Closed → Refresh`. **حجزت APT-2026-00085 فعليًا** |
| **19** | **تسجيل طفل جديد — Modal** | ✅ **مبنيّة ومُختبَرة حيًّا 2026-09-01.** 8 عناصر · زر `حفظ` · معالجتان (`create_child` ثم Close Dialog). الزر في صفحة 6، ومعه `Dialog Closed → Refresh`. **سجّلت CH-043 فعليًا** |
| **20** | **تعديل بيانات طفل — Modal** | ✅ **مبنيّة ومُختبَرة حيًّا 2026-09-01.** أُنشئت بـ **Create Page as Copy** من صفحة 19 — APEX أعاد تسمية العناصر لـ `P20_` تلقائيًا. زائد `P20_CHILD_ID` (Hidden) و`P20_CLEAR_NATIONAL_ID` (Switch، **الافتراضي `N`**) و**معالجة Pre-Rendering** تحمّل بيانات الطفل. الزر «تعديل البيانات» في صفحة 17 (نافذة داخل نافذة). **عدّلت CH-043 فعليًا** |

| **21** | **إضافة ولي أمر — Modal** | ✅ **مبنيّة ومُختبَرة حيًّا 2026-09-01.** نسخة من صفحة 20 مع إعادة استخدام العناصر: `P21_EMAIL` ← `NAME_EN` · `P21_MOBILE` ← `SCHOOL_NAME` · `P21_RELATIONSHIP` ← `GENDER` (LOV صار SQL على `GUARDIAN_RELATIONSHIP` بـ **`VALUE_CODE`**) · مفتاحان جديدان من `MEDICAL_ALERT` و`CASE_NO`. حُذفت معالجة Pre-Rendering و`BIRTH_DATE`. الزر «إضافة ولي أمر» في صفحة 17. **أضافت وليّ أمر لـ CH-043 فعليًا (0 ← 1)** |

| **22** | **إسناد أخصائي — Modal** | ✅ **مبنيّة ومُختبَرة حيًّا 2026-09-01.** `P22_SERVICE_ID` · `P22_THERAPIST_ID` (**قائمة متتالية على الخدمة** — الأخصائي يظهر فقط لو التخصّص مطابق) · `P22_CHILD_ID` (Hidden) · `P22_IS_PRIMARY` (Switch، **الافتراضي `N`**). الزر «إسناد أخصائي» في صفحة 17. **أسندت سارة محمود لـ CH-043 فعليًا وانطفأ تنبيه «لا يوجد أخصائي معالج»** |

| **23** | **إجراء على موعد — Modal** (تشمل شاشة 25 «بدء جلسة») | ✅ **مبنيّة ومُختبَرة حيًّا 2026-09-01.** `P23_APPT_INFO` (Display Only، مصدره استعلام على `HBH_VW_APPOINTMENTS` — الاستقبال يشوف الموعد اللي بيتصرّف فيه) · `P23_ACTION` (قائمة **مبنيّة على آلة الحالة** — تحت) · `P23_REASON_ID` + `P23_BY_CENTER` (يظهروا فقط مع الإلغاء عبر Dynamic Action) · `P23_NOTE` · `P23_APPOINTMENT_ID` (Hidden). معالجة واحدة بـ `CASE` على `P23_ACTION` تنادي `confirm_appt` / `check_in_appt` / `cancel_appt` / `no_show_appt`. المدخل: **عمود رابط في تقرير صفحة 7** بـ `Clear Cache = 23`. **أكّدت APT-2026-00085 وألغت APT-2026-00074 فعليًا** |

> **القائمة هي التحقّق.** بدل أربعة أزرار ثابتة، `P23_ACTION` استعلام بينضم على `HBH_APPOINTMENTS` ويسأل `HBH_PKG_SCHED.legal_transition` — فالإجراء غير المسموح **مش بيتعرض أصلًا**، لا بيتعرض ويتقفل بخطأ. موعد مؤكَّد بيوفّر حضور/إلغاء/تخلّف فقط، والموعد المنتهي ما بيوفّرش حاجة.

> **`legal_transition` بتقول نعم للانتقال لنفس الحالة** — وده صح جوّه الـ API (إعادة تثبيت نفس الحالة عملية فاضية غير ضارّة) وغلط على قائمة: كانت بتعرض «تأكيد الموعد» لموعد **مؤكَّد بالفعل**، والضغطة تبان ناجحة وهي ما غيّرتش حاجة. الاستعلام بيضيف `AND a.st <> ap.STATUS`. **الدالة الصح ممكن تدّي شاشة غلط.**

> **صفحة مشروحة بحالة سابقة كذّابة.** أول فتح تاني للنافذة عرض «تأكيد الموعد» مختارة سلفًا — قيمة الإجراء السابق باقية في حالة الجلسة، وكمان الملاحظة والسبب. `Clear Cache = 23` في الرابط بيصفّرهم. أي نافذة إجراءات لازم تُفتح فاضية.

> **الرابط بيستبدل أعمدة التقرير، فالعمود لازم يكون في الاستعلام.** `#APPOINTMENT_ID#` كان بيتحوّل لفاضي لأن `SELECT` صفحة 7 ما كانش فيه `APPOINTMENT_ID` أصلًا. اتضاف كـ **Hidden Column**. الفشل صامت: الرابط بيفتح، والصفحة بتيجي بمعرّف NULL.

> **صفحة 23 كبرت لتغطي دورة حياة الموعد كلها.** أُضيف الإجراء **`START` — «بدء الجلسة»** (الحالة الهدف `IN_PROGRESS`)، ومعه حقلان يظهران له وحده عبر Dynamic Action تانية: `P23_SUBSTITUTE_ID` (أخصائي بديل — **مفلتَر بتخصّص خدمة الموعد**، فالبديل اللي مكانش ينفع يتحجز أصلًا مش بيتعرض) و`P23_ROOM_ID` (غرفة مختلفة). المعالجة بقت `DECLARE l_session_id NUMBER;` وبتنادي `HBH_PKG_FORM.start_session`.
>
> **السلسلة كاملة مُختبَرة حيًّا على APT-2026-00085:** محجوز ← **مؤكَّد** ← **تم الوصول** ← **جارية**، وظهر صفّ الجلسة في صفحة 10 بوقت بداية فعلي. والقائمة في كل خطوة عرضت الانتقالات المسموحة بس: موعد «تم الوصول» بيوفّر «بدء الجلسة» و«إلغاء الموعد» فقط.

> **نوع الـ LOV اتقلب لـ «Function Body returning SQL Query» تلات مرات من غير ما أختاره.** القائمة والحقل بيبقوا على بُعد ٢٦ بكسل في لوحة الخصائص، ونافذة المتصفّح كانت بتتغيّر عرضها بين لقطة الشاشة والنقرة — فالنقرة اللي المفروض تفتح محرّر الكود كانت بتقع على القائمة وتغيّر النوع. العَرَض عند التشغيل: **`PLS-00428: an INTO clause is expected in this SELECT statement`** باسم عنصر الصفحة. لو ظهر ده، النوع اتغيّر، مش الاستعلام. والإصلاح اللي نجح: حذف العنصر وإعادة إنشائه بـ Duplicate من عنصر سليم، وكتابة الاستعلام في **مربّع النص نفسه** لا في نافذة محرّر الكود.

> **`ORA-00904` في LOV بيتقال باسم العنصر لا باسم الخطأ.** أول تشغيل لصفحة 22 وقع بـ «Error during rendering of page item P22_SERVICE_ID»، والسبب الحقيقي `ORDER BY SORT_ORDER` في استعلام الـ LOV: `HBH_VW_LOV_SERVICES` بترتّب نفسها بالعمود ده لكنها **ما بتُظهرهوش** في الـ SELECT. الترتيب بعمود غير مُسقَط قانوني على جدول وممنوع عبر view. استعلامات الـ LOV ترتّب بـ `1`.

> **الإسناد مش تفصيلة إدارية.** `start_session` بترفض الأخصائي اللي مش على قائمة حالات الطفل بـ `-20003`، والرفض بيبان كأنه عطل في شاشة الجلسة. صفحة 22 هي اللي بتمنع ده.

| **26** | **إجراء على جلسة — Modal** (تشمل شاشة 27 «ملاحظة جلسة» و«إيقاف الجلسة») | ✅ **مبنيّة 2026-09-02، والقائمة والحقول مُختبَرة حيًّا.** `P26_SESSION_INFO` (Display Only على `HBH_VW_SESSIONS`) · `P26_ACTION` (قائمة من حالة الجلسة **ومن قواعد الـ API**) · `P26_MOOD_CODE` (`CHILD_MOOD` بـ **`VALUE_CODE`**) · `P26_COOPERATION` (رقم ١–٥) · `P26_NOTE_TYPE` (ست قيم ثابتة = قيد الـ CHECK) · `P26_NOTE` · `P26_IS_BILLABLE` (**افتراضي `Y`**) · `P26_PUBLISH` (**افتراضي `N`**) · `P26_SESSION_ID` (Hidden). المدخل: عمود رابط في صفحة 10 بـ `Clear Cache = 26` ومعه `Dialog Closed → Refresh`. **السلسلة كاملة مُختبَرة حيًّا بحساب سارة:** ملاحظة منشورة ← ظهرت «إنهاء الجلسة» في القائمة ← أُنهيت الجلسة بمزاج «سعيد ومتعاون» ودرجة تعاون 4 ← الحالة «مكتملة»، والجلسة المكتملة بقت توفّر «ملاحظة» فقط |

> **أربع Dynamic Actions، مجمَّعة بالحقل لا بالإجراء.** `P26_NOTE` بيظهر مع `NOTE` و`ABORT`، و`P26_IS_BILLABLE` مع `END` و`ABORT` — والحقل اللي بيخدم إجراءين لازم **DA واحدة** شرطها `Item is in list` بقيمة `NOTE,ABORT` أو `END,ABORT`. لو اتعملوا DA لكل إجراء، اتنين منهم بيتخانقوا على نفس الحقل في نفس اللحظة. مُختبَر حيًّا: مع `NOTE` ظهر (نوع الملاحظة · النص · النشر) واختفى (المزاج · التعاون · الفوترة)، ومع `ABORT` ظهر (النص · الفوترة) بس.


> **حساب الأخصائي لازم يتربط بسجلّ الأخصائي بإيده.** `HBH_PKG_SEC.create_staff_user` **مابتحطّش `THERAPIST_ID`** في الـ INSERT أصلًا، ولو الربط اتنسي فـ `current_therapist_id` بترجّع NULL، و`can_edit_session`/`can_close_session` بيفشلوا مقفولين: الأخصائية تدخل عادي، تشوف كل حاجة، وما تقدرش تكتب ملاحظة ولا تنهي جلستها هي. الحساب بيبان سليم في كل شاشة وهو مش شغّال. `db/hbh_create_therapist_user.sql` بيعمل الربط في خطوة منفصلة وبيتحقق منه (`therapist link 1/1`). حساب `sara` = سارة محمود (therapist 64) اتعمل بيه 2026-09-02.
> **«إنهاء الجلسة» ما ظهرتش أصلًا في الاختبار — وده الصح.** `end_session` بترفض جلسة من غير ملاحظة منشورة، فالقائمة بتخفي الإجراء لحد ما الملاحظة تتكتب. الجلسة المُختبَرة (`APT-2026-00085`) عرضت «إيقاف الجلسة» و«ملاحظة للجلسة» بس.

> **`ORA-02290` على `WWV_FLOW_PAGE_DA_E_EXEC` معناها Execution Type فاضي.** الـ DA المتعملة من قائمة السياق بتيجي أحيانًا من غير `Type = Immediate`، والحفظ بيترفض كله برسالة عن قيد داخلي في APEX مش عن الصفحة.

> **نافذة `Create Page as Copy` تعيد تسمية التسميات كمان.** الخطوة الأخيرة فيها جدول «New Names» بيخليك تغيّر تسمية كل عنصر أثناء النسخ — استعملها، توفّر تعديلًا منفصلًا لكل حقل. لكنها **تغيّر التسمية لا اسم العنصر**، فأسماء `Pxx_` لازم تتعدّل بعدين لو المعنى اتغيّر.

> **ولمّا تنسخ صفحة، افحص ما نُسخ معها.** صفحة 21 جت ومعها معالجة Pre-Rendering بتقرا `:P21_GENDER` و`:P21_CASE_NO` — أسماء اتغيّرت بعد النسخ، فكانت هتفشل عند فتح الصفحة. النسخ بيجيب **كل** حاجة، والزيادة تتحذف بوعي.

> **اختصار مهم:** `Create Page as Copy` (رابط أسفل نافذة Create Page) ينسخ الصفحة كاملة — العناصر والأزرار والمعالجات — **ويعيد ترقيم كل العناصر تلقائيًا** من `P19_` إلى `P20_`. بناء صفحة 19 عنصرًا بعنصر أخذ عشرات الجولات؛ نسخها أخذ ثلاث نقرات. استخدمه لكل شاشة تشبه شاشة موجودة.

### درس: اسم عنصر الصفحة لا يُكتب داخل الحزمة
النسخة الأولى كانت تقرأ `V('P12_CHILD_ID')` بنفسها. ثم أنشأ APEX الصفحة برقم 17
لا 12، فصارت الشاشة تظهر **فارغة بلا أي خطأ** — أسوأ أنواع الأعطال. الآن الصفحة
تمرّر عنصرها بنفسها:
```
RETURN HBH_PKG_UI.child_header_html(:P17_CHILD_ID);
RETURN HBH_PKG_UI.live_view_html(:P5_CAMERA_ID);
```
الصفحة تعرف عناصرها؛ الحزمة لا تعرفها ولا يجب أن تعرفها.

### ما زال ناقصًا على صفحة 17
ثلاثة Interactive Reports مفلترة على `:P17_CHILD_ID` (الجلسات · الأهداف ·
التقارير) — الاستعلامات مكتوبة أعلاه في قسم «صفحة 12 — ملف الطفل»، مع تبديل
`:P12_CHILD_ID` بـ `:P17_CHILD_ID`.

## قاعدة: الشاشات الفرعية تُفتح كـ Modal Dialog

`Page Mode = Modal Dialog` على الصفحة الهدف. APEX يتولّى الباقي: أي رابط إليها
من صفحة أخرى يفتحها كنافذة فوق نفس الشاشة، وحالة الصفحة الأصلية لا تضيع.

| صفحة | العرض |
|---|---|
| 17 ملف الطفل | 1100px |
| 5 بث مباشر | 960px |

وكل شاشة فرعية قادمة تتبع نفس القاعدة: نموذج تسجيل طفل، حجز موعد، تسديد دفعة،
تفاصيل فاتورة — كلها Modal فوق القائمة التي فُتحت منها.

**ولذلك حُذف زر «رجوع» من شاشة البث.** داخل نافذة، رابط يذهب إلى صفحة 4 لا
يُغلق النافذة — بل يحرّك الصفحة **خلفها**، فيجد المستخدم نفسه في المكان الصحيح
والبثّ ما زال يعمل فوقه. زر الإغلاق الخاص بالنافذة هو المخرج الوحيد.

## شاشات إدخال البيانات — القاعدة قبل التنفيذ

**لا تُستخدم "Form on Table" ولا Automatic Row Processing. أبدًا.**

النموذج التلقائي يكتب في الجدول مباشرة، وهذا يتخطّى كل ما بُني:

| ما يتخطّاه | مثال |
|---|---|
| فحص التعارض | موعد يُحجز على أخصائي مشغول أو غرفة مشغولة |
| آلة الحالات | `STATUS` يُغيَّر بلا صف في جدول التاريخ |
| سقف الخصم | خصم فوق الحد بلا صلاحية `DISCOUNT.APPROVE` |
| السجل | تعديل بلا أثر في `HBH_AUDIT_LOG` |
| دفتر الحصص | جلسة تُستهلك مرتين |

كل شاشة إدخال = عناصر صفحة + **Page Process واحد ينادي `HBH_PKG_FORM`**.

**ولا تنادي الصفحة حزمة المجال مباشرة.** الصفحة تنادي `HBH_PKG_FORM` فقط، وهي
التي تنادي `HBH_PKG_SCHED` / `HBH_PKG_CHILD` / `HBH_PKG_SESSION` /
`HBH_PKG_BILLING`. السبب ثلاثة أشياء تتكرّر في كل صفحة ولا يصحّ أن تُكتب في كل
صفحة:

1. **التحويل.** عنصر الصفحة نصّ دائمًا. `HBH_PKG_FORM` يستقبل `VARCHAR2` ويحوّل
   بنفسه، فالتاريخ يُقرأ بصيغة `YYYY-MM-DD` واحدة في مكان واحد، والحقل الفارغ
   يصل `NULL` لا صفرًا.
2. **الـ COMMIT.** الحزم لا تعمل COMMIT بقاعدة المشروع؛ المنادي هو صاحب
   المعاملة. الصفحة هي المنادي، فالـ COMMIT في `HBH_PKG_FORM` — حدّ المعاملة =
   ضغطة زر واحدة، مكتوبة في ملف واحد بدل أن تكون ضِمنية في عشرة Page Processes.
3. **العمليات المركّبة.** «إضافة ولي أمر لطفل» هي إنشاء + ربط في معاملة واحدة،
   و«حفظ ملاحظة ونشرها» هي `add_note` + `publish_note`. لو تُركت للصفحة لصار
   نصفها ينجح ونصفها يفشل.

### الشاشات المطلوبة ومصدر كل منها
كلها موجودة الآن في `db/05_packages/12_hbh_pkg_form.sql` — 31 مدخلًا عامًّا:

| الشاشة | نداء الصفحة |
|---|---|
| طفل جديد | `HBH_PKG_FORM.create_child` → `x_child_id`, `x_case_no` |
| تغيير حالة طفل | `change_child_status` |
| ولي أمر جديد وربطه | `add_guardian_to_child` (معاملة واحدة) |
| ربط ولي أمر موجود | `link_guardian` |
| ولي أمر بلا ربط | `create_guardian` |
| إسناد أخصائي | `assign_therapist` |
| موافقة ولي الأمر | `grant_consent` |
| حجز موعد | `check_slot_msg` ثم `book` |
| تعديل موعد | `reschedule` |
| تأكيد / حضور / إلغاء / تخلّف | `confirm_appt` · `check_in_appt` · `cancel_appt` · `no_show_appt` |
| بدء جلسة | `start_session` → `x_session_id` |
| إنهاء / إلغاء جلسة | `end_session` · `abort_session` |
| ملاحظة جلسة | `save_note` (`p_publish='Y'` تحفظ وتنشر) |
| نشاط داخل الجلسة | `add_activity` |
| لحظة مهمّة | `mark_moment` |
| بيع باقة | `sell_package` |
| فاتورة | `create_invoice` · `add_line` · `remove_line` · `issue_invoice` · `cancel_invoice` |
| دفعة | `receive_payment` (يوزّع تلقائيًا) · `allocate_payment` · `void_payment` |

| تعديل بيانات طفل | `update_child` |
| خطة علاجية | `create_plan` · `submit_plan` · `approve_plan` · `complete_plan` · `cancel_plan` |
| هدف داخل الخطة | `add_goal` · `achieve_goal` · `pause_goal` · `resume_goal` · `discontinue_goal` |
| قياس تقدّم | `record_progress` |
| تقرير تقدّم | `create_report` · `submit_report` · `approve_report` · `publish_report` · `unpublish_report` |

### تعديل الطفل — فخّ الرقم القومي
`update_child` **لا تغيّر الحالة**. الحالة تمرّ بـ `change_child_status` التي
تكتب صفًّا في `HBH_CHILD_STATUS_HISTORY`؛ شاشة تعديل تقدر تقلب الحالة كمان تبقى
باب تاني صامت للخروج من آلة الحالات.

وأهمّ من كده: **حقل الرقم القومي الفاضي معناه «سيبه زي ما هو»، مش «امسحه»**.
شاشة التعديل ما تقدرش تعرض الرقم المخزَّن إلا بنداء `read_national_id` وهو حدث
مسجَّل في التدقيق ومعظم المحرِّرين مش هيشغّلوه — يعني الحقل هيوصل فاضي في كل
حفظ تقريبًا. لو الفاضي معناه «امسح» كان الرقم هيتمسح لكل طفل اتعدّل ملفّه لأي
سبب تاني. المسح فعل مقصود وله مفتاح منفصل:
`p_clear_national_id => 'Y'`.

وصفّ التدقيق يسجّل **أسماء الأعمدة اللي اتغيّرت، لا قيمها** — لأن كتابة القيم
كانت هتنسخ الرقم القومي جوّه `HBH_AUDIT_LOG` حيث يقرأه أي حد يقرأ السجل، وقراءة
الرقم غير المقنَّع المفروض تكون هي نفسها حدثًا مسجَّلًا.

**مواصفة كل شاشة إدخال بالتفصيل — العناصر والاستعلامات وكود المعالجة:**
[`docs/14-data-entry-screens.md`](../docs/14-data-entry-screens.md) · 28 شاشة · كل الـ78 مدخلًا.

**ما زال خارج `HBH_PKG_FORM`:** التقييمات (`create_assessment` ·
`record_result` · `submit_assessment`) — تُضاف بالشكل نفسه عند بناء شاشتها.

### قوائم الاختيار الجاهزة
| العرض | الاستخدام |
|---|---|
| `HBH_VW_LOV_CHILDREN` | الأطفال القابلون للحجز (لا مُخرَج) |
| `HBH_VW_LOV_SERVICES` | الخدمات ومدّتها الافتراضية |
| `HBH_VW_LOV_THERAPISTS` | الأخصائيون النشطون، صف لكل تخصّص |
| `HBH_VW_LOV_ROOMS` | الغرف الصالحة، صف لكل خدمة تستضيفها |
| `HBH_VW_LOV_GUARDIANS` | أولياء الأمور |
| `HBH_VW_LOV_START_TIMES` | أوقات البداية مولَّدة من `WORKING_DAY_*` |
| `HBH_VW_LOV_LOOKUPS` | **كل** القوائم المرمّزة — فلترة بـ `TYPE_CODE` |
| `HBH_VW_LOV_PACKAGES` | الباقات القابلة للبيع اليوم |
| `HBH_VW_LOV_OPEN_INVOICES` | الفواتير المصدَّرة ولها رصيد |
| `HBH_VW_LOV_PLANS` | الخطط المفتوحة للتعديل — فلترة بـ `CHILD_ID` |
| `HBH_VW_LOV_GOALS` | الأهداف الجاري العمل عليها — فلترة بـ `PLAN_ID` أو `CHILD_ID` |
| `HBH_VW_LOV_DOMAINS` | مجالات المهارة — جدول مستقل، مش قائمة مرمّزة |
| `HBH_VW_LOV_CONSENT_TYPES` | أنواع الموافقات — `RETURN_VALUE` هو الرمز |
| `HBH_VW_LOV_DOMAINS` | مجالات المهارة — جدول مستقل، مش lookup |
| `HBH_VW_LOV_CONSENT_TYPES` | أنواع الموافقات — `RETURN_VALUE` هو الرمز |

`HBH_VW_LOV_LOOKUPS` عرض واحد لكل القوائم (صلة القرابة، طريقة الدفع، سبب
الإلغاء، المزاج، نتيجة النشاط، نوع الموافقة). الصفحة تفلتر:
```sql
SELECT DISPLAY_VALUE d, RETURN_VALUE r
FROM   HBH_VW_LOV_LOOKUPS
WHERE  TYPE_CODE = 'RELATIONSHIP'
ORDER  BY SORT_ORDER
```
`RETURN_VALUE` هو `LOOKUP_ID` للأعمدة التي تحمل مُعرِّفًا، و`VALUE_CODE` للأعمدة
التي تحمل الرمز نفسه — والاثنان ليسا الشيء نفسه.

**التسلسل المقترح:** الحجز أولًا (هو ما يشغّل المركز يوميًا)، ثم تسجيل الطفل
وولي الأمر، ثم الجلسة، ثم الفوترة. لا تُبنى شاشة إدخال قبل أن يكون الـ API
الذي تناديه مقبولًا في اختبار مرحلته — وكلها مقبولة بالفعل.

## صفحة 18 — حجز موعد (Modal)

**تم (2026-09-01):** الصفحة أُنشئت كـ `Modal Dialog`، وبداخلها region اسمه
«بيانات الموعد»، وفيه ثلاثة عناصر محفوظة وصحيحة:

| العنصر | النوع | التسمية | الحالة |
|---|---|---|---|
| `P18_CHILD_ID` | Select List | الطفل | ✅ على `HBH_VW_LOV_CHILDREN` |
| `P18_SERVICE_ID` | Select List | الخدمة | ✅ على `HBH_VW_LOV_SERVICES` |
| `P18_THERAPIST_ID` | Select List | الأخصائي | ✅ الاستعلام المتتالي أدناه |

**ناقص على العنصرين المتتاليين:** حقل `Cascading LOV Parent Item(s)` =
`P18_SERVICE_ID` لم يُضبط بعد على `P18_THERAPIST_ID` (ولا على `P18_ROOM_ID` عند
إنشائه). بدونه يعمل الاستعلام لكن القائمة لا تُحدَّث عند تغيير الخدمة.

**الباقي — أربعة عناصر وزرّان ومعالجة واحدة.** كلها في الـ region نفسه:

| العنصر | النوع | التسمية | مصدر القائمة |
|---|---|---|---|
| `P18_ROOM_ID` | Select List | الغرفة | القائمة المتتالية أدناه |
| `P18_APPT_DATE` | Date Picker | التاريخ | Format Mask = `YYYY-MM-DD` |
| `P18_START_TIME` | Select List | وقت البداية | `SELECT DISPLAY_VALUE d, RETURN_VALUE r FROM HBH_VW_LOV_START_TIMES` |
| `P18_NOTES` | Textarea | ملاحظات | — |
| `P18_CHECK_MSG` | Display Only | التوفّر | Based on = Item Value |

> **أسرع طريقة:** كليك يمين على `P18_THERAPIST_ID` في شجرة Rendering →
> **Duplicate**، ثم غيّر `Name` و`Label` واستبدل نص `SQL Query`. هذا يوفّر ضبط
> النوع والقالب في كل مرّة. للعناصر غير القائمة (`P18_APPT_DATE`,
> `P18_NOTES`, `P18_CHECK_MSG`) غيّر `Type` بعد النسخ، وسيختفي قسم
> `List of Values` من تلقائه.

**الأخصائي — قائمة متتالية على الخدمة** (`Cascading LOV Parent Item(s)` =
`P18_SERVICE_ID`):
```sql
SELECT DISTINCT t.DISPLAY_VALUE d, t.RETURN_VALUE r
FROM   HBH_VW_LOV_THERAPISTS t
WHERE  NOT EXISTS (SELECT 1 FROM HBH_VW_LOV_SERVICES s
                    WHERE s.RETURN_VALUE = :P18_SERVICE_ID
                      AND s.REQUIRED_SPECIALTY_ID IS NOT NULL)
   OR  t.SPECIALTY_ID = (SELECT s.REQUIRED_SPECIALTY_ID
                           FROM HBH_VW_LOV_SERVICES s
                          WHERE s.RETURN_VALUE = :P18_SERVICE_ID)
ORDER  BY 1
```

**الغرفة — قائمة متتالية على الخدمة** (`Parent Item(s)` = `P18_SERVICE_ID`):
```sql
SELECT DISTINCT DISPLAY_VALUE d, RETURN_VALUE r
FROM   HBH_VW_LOV_ROOMS
WHERE  SERVICE_ID = :P18_SERVICE_ID
ORDER  BY 1
```

### زر «تحقق من التوفّر» — Dynamic Action
Action = **Execute Server-side Code**، Items to Submit = العناصر الستة،
Items to Return = `P18_CHECK_MSG`:
```plsql
:P18_CHECK_MSG := HBH_PKG_FORM.check_slot_msg(
                    :P18_CHILD_ID, :P18_SERVICE_ID, :P18_THERAPIST_ID,
                    :P18_ROOM_ID,  :P18_APPT_DATE,  :P18_START_TIME);
```

### زر «حجز» — Submit، ثم Page Process من نوع PL/SQL
```plsql
DECLARE
  l_id NUMBER;
  l_no VARCHAR2(30);
BEGIN
  HBH_PKG_FORM.book(
    p_child_id     => :P18_CHILD_ID,
    p_service_id   => :P18_SERVICE_ID,
    p_therapist_id => :P18_THERAPIST_ID,
    p_room_id      => :P18_ROOM_ID,
    p_appt_date    => :P18_APPT_DATE,
    p_start_time   => :P18_START_TIME,
    p_notes        => :P18_NOTES,
    x_appt_id      => l_id,
    x_appt_no      => l_no);
  APEX_UTIL.SET_SESSION_STATE('P18_CHECK_MSG', 'تم الحجز — رقم الموعد ' || l_no);
END;
```
ثم Branch من نوع **Close Dialog**.

> **لا تضع أي `INSERT` في الصفحة.** الحجز كله يمرّ بـ `HBH_PKG_FORM.book` التي
> تنادي `HBH_PKG_SCHED.book_appointment` — هي التي تقفل الصفوف وتفحص التعارض
> وتكتب صف التاريخ وتسجّل في التدقيق. صفحة تكتب في `HBH_APPOINTMENTS` مباشرة
> تتخطّى ذلك كله بصمت.
