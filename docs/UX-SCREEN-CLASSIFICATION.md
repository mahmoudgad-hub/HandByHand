# UX-SCREEN-CLASSIFICATION — مراجعة الوضع الحالي

**2026-09-14 · تحليل فقط، لا تنفيذ معتمد.** القسم الأعلى هو المرجع الحالي. التحليل السابق محفوظ في آخر الملف للأرشفة ولا يمثل العمل المتبقي.

## تصنيف واحد لكل جزء

السطح والفعل والحالة صفوف منفصلة: live PAGE، مشاهدة ACTION، IN_PROGRESS STATUS؛ Drawer MODAL ولو عرض تفاصيل كيان. لا نخلط PAGE/TASK في خلية. نمطا إنشاء/تعديل التقرير مساران لنفس المحرر.

| Part | Classification | Reason |
| --- | --- | --- |
| ops /login | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /communications | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /tasks | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /notifications | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /dashboard | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /guardians | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /guardians/:guardianId | DETAIL PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /children | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /children/:childId | DETAIL PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /children/:childId/reports/new | DETAIL PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /children/:childId/reports/:reportId | DETAIL PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /children/:childId/card | DETAIL PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /therapists | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /rooms | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /plans | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /catalog | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /site | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /appointments | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /sessions | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /reports | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /billing | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /requests | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /enrolments/:applicationId | DETAIL PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /enrolments | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /therapists/:therapistId/profile | DETAIL PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /sessions/:sessionId/live | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /users | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /satisfaction | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /ops-log | REPORT | سطح حالي؛ لا يساوي نوع بياناته |
| ops /settings | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| ops /denied | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /login | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /login/otp | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /apply | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /welcome | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /communications | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /home | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /schedule | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /progress | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /activities | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /live | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /consultation/:appointmentId | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /reports | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /reports/:reportId | DETAIL PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /billing | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /requests | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /therapists/:therapistId | DETAIL PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /notifications | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| portal /profile | PAGE | سطح حالي؛ لا يساوي نوع بياناته |
| site/index.html | PAGE | الموقع |
| site/privacy.html | PAGE | الخصوصية |
| Appointment Drawer | MODAL | تفاصيل داخل dialog |
| Invoice Drawer | MODAL | تفاصيل داخل dialog |
| قائمة المزيد المستهدفة | MODAL | لا route |
| عنصر إشعار | NOTIFICATION | حدث لشخص |
| غير مقروء فقط | FILTER | تصفية |
| view=mine | FILTER | عرض المواعيد |
| NEW / CONTACTED وسائر قيم الحالات | STATUS | قيمة مخزنة لا صفحة |
| اختيار status بالقائمة | FILTER | عنصر تصفية |
| زر تحويل الطلب | ACTION | فعل |
| تأكيد التحويل | MODAL | حوار |
| assessment في تفاصيل الطلب | TAB | قد يكون فارغًا بلا API |
| نتائج الرضا | REPORT | داخل صفحة |
| tabs الموارد والتفاصيل | TAB | حاويات فرعية |
| أزرار حفظ/نشر/طباعة/بث | ACTION | أفعال مستقلة عن سطحها |
| ENROLMENT_TRIAGE | TASK | APPLICATION; ENROLMENT.MANAGE |
| ENROLMENT_BOOK_ASSESSMENT | TASK | APPLICATION; ENROLMENT.MANAGE |
| ENROLMENT_CONVERT | TASK | APPLICATION; ENROLMENT.MANAGE |
| APPOINTMENT_CONFIRM | TASK | APPOINTMENT; APPOINTMENT.BOOK |
| APPOINTMENT_CHECK_IN | TASK | APPOINTMENT; APPOINTMENT.BOOK |
| SESSION_START | TASK | APPOINTMENT; SESSION.START |
| SESSION_CLOSE | TASK | SESSION; SESSION.COMPLETE |
| REPORT_FINISH | TASK | REPORT; REPORT.WRITE |
| REQUEST_DECIDE | TASK | REQUEST; REQUEST.MANAGE |
| INVOICE_ISSUE | TASK | INVOICE; BILLING.MANAGE |
| INVOICE_OVERDUE | TASK | INVOICE; BILLING.VIEW |
| CHILD_ASSIGN_THERAPIST | TASK | BENEFICIARY; STAFF.MANAGE |
| THERAPIST_PROFILE_CONSENT | TASK | THERAPIST; PORTAL.VIEW |
| SCHEDULE_CONFLICT | TASK | APPOINTMENT; APPOINTMENT.BOOK |

أقسام النماذج التفصيلية ومواضع التحكم في [UX-AUDIT-SOURCE-INDEX.md](UX-AUDIT-SOURCE-INDEX.md). FORM اسم جرد تقني لا صنف UX إضافي: يصنف بحسب حاويته PAGE أو MODAL، وخيارات الحالة STATUS، وعناصر التصفية FILTER. حالات انتظار الأخصائي/ولي الأمر المذكورة في المثال ليست أجزاء منفذة هنا، فلا تنشأ ولا تدخل العدد.


<details>
<summary>أرشيف التحليل السابق — غير معتمد كوصف للحالة الحالية أو تكليف تنفيذ</summary>

# UX Screen Classification — تصنيف كل جزء

**المرحلة ٩.** كل جزء في المشروع مصنَّف إلى **واحد فقط** من: `PAGE` · `DETAIL PAGE` · `TAB` · `MODAL` · `TASK` · `STATUS` · `FILTER` · `ACTION` · `NOTIFICATION` · `REPORT`. العمود «اليوم» يقول ما هو الآن في الكود، و«الهدف» ما ينبغي أن يكون. حين يتطابقان لا تغيير.

---

## ١ · كونسول المركز

| الجزء | اليوم | الهدف | ملاحظة |
|---|---|---|---|
| دخول الموظفين `/login` | PAGE | PAGE | |
| لوحة التحكم `/dashboard` | PAGE | PAGE | |
| صندوق الوارد `/inbox` | PAGE (اسمه يوحي بـTASK) | **NOTIFICATION** (شاشة الإشعارات) | تسمية + رابط ميّت |
| «غير المقروء فقط» في الوارد | FILTER | FILTER | |
| المهامّ `/tasks` | — | **PAGE** (صندوق المهامّ) | جديد |
| بطاقات الداشبورد `wantsAction` (التحاق جديد · طلبات جديدة · تقارير مسودّة · فواتير غير مسدّدة) | FILTER بعدّ (تربط بـ`?status=`) | **TASK** (معاينة) | نفس المصدر |
| لوحة «التنبيهات والمتابعة» | PAGE-panel | **TASK** (أوّل 5) | |
| لوحة «يومك» للأخصائي | PAGE-panel | **TASK** (بدء الجلسة) | |
| بطاقات العدّ الأخرى (مواعيد اليوم · حضروا · جلسات جارية · الأطفال) | FILTER بعدّ | FILTER | صحيحة |
| المؤشّرات السفلية (حضور · رضا · التحاق الشهر · مستحقّات) | REPORT | REPORT | |
| الأطفال `/children` | PAGE (تبويبان) | **PAGE** «المستفيدون» | أولياء الأمور يخرجون |
| تبويب «أولياء الأمور» + master-detail المضمَّن | TAB | **PAGE** `/guardians` + **DETAIL PAGE** `/guardians/:id` | |
| ملفّ الطفل `/children/:id` | DETAIL PAGE | DETAIL PAGE | + CTA وأفعال |
| تبويبات الملفّ (مواعيد · جلسات · خطط · تقارير · باقات · فواتير · ملاحظات · أولياء الأمور · activityLog) | TAB ×9 | TAB ×9 (+ «الأخصائي المسؤول» · 🔴 التقييمات · 🔴 الخطّ الزمني) | `activityLog` → «البرنامج المنزلي» |
| «نشر ملاحظة» (تبويب الملاحظات) | ACTION | ACTION | |
| تبديل موافقة البثّ (تبويب أولياء الأمور) | ACTION | ACTION (كل الأنواع) | |
| كرت هويّة الطفل `/children/:id/card` | PAGE | **ACTION** (طباعة) بمسار | لا يدخل القائمة |
| محرّر التقرير `/children/:id/reports/*` | PAGE | DETAIL PAGE (للتقرير) | |
| «معاينة» في المحرّر | TAB (وضع) | TAB | |
| «نشر لوليّ الأمر» | ACTION | ACTION | |
| الأخصائيون `/therapists` | PAGE (3 تبويبات) | PAGE (4 تبويبات) | |
| تبويب «ساعات العمل» | TAB | TAB | |
| تبويب «إسناد الحالات» | TAB (CRUD) | TAB (قراءة) + **ACTION** «تعيين أخصائي» من ملفّ المستفيد + **TASK** K-16 | |
| خدمات الأخصائيين `/therapist-services` | PAGE | **TAB** «الخدمات» في الأخصائيين | إعادة توجيه |
| ملفّ الأخصائي `/therapists/:id/profile` | DETAIL PAGE | DETAIL PAGE + بند «ملفّي» | |
| موافقة نشر الملفّ · نشر الملفّ | ACTION | ACTION (+ **TASK** K-19 للأخصائي) | |
| الغرف والكاميرات `/rooms` | PAGE | PAGE (تحت الإعدادات) | |
| عرض الكروت / الجدول في الغرف | FILTER (عرض) | FILTER | |
| الخطط العلاجية `/plans` | PAGE (4 تبويبات) | PAGE (قائمة عبر الأطفال) | الأهداف/القياسات/البرنامج → TAB «الخطّة» في ملفّ المستفيد |
| الخدمات والباقات `/catalog` | PAGE (4 تبويبات) | PAGE (3 تبويبات) «الكتالوج» | الاستبيانات تخرج |
| تبويب «استبيانات الرضا» | TAB (في الكتالوج) | **TAB** في «رضا الأسر» | |
| رضا الأسر `/satisfaction` | REPORT بمسار | **PAGE** (تبويبان: الاستبيانات · النتائج) | النتائج REPORT داخلها |
| الموقع التعريفي `/site` | PAGE (7 تبويبات) | PAGE (8 تبويبات) | |
| فريق العمل `/site/team` | PAGE | **TAB** «الفريق على الموقع» | إعادة توجيه |
| المواعيد `/appointments` | PAGE | PAGE | |
| جدول / التقويم الأسبوعي | FILTER (عرض) | FILTER `?view=` | |
| يومي `/my-day` | PAGE (فلتر `mine=1` بمسار) | **FILTER** `?view=mine` | إعادة توجيه |
| فلاتر الأخصائي/الغرفة/الخدمة/اليوم/الحالة | FILTER | FILTER | |
| لوحة «بانتظار التأكيد» | PAGE-panel (disclosure) | **TASK** K-04 (تبقى في مكانها + في المهامّ) | |
| لوحة «تداخلات الأخصائي أو الغرفة» | PAGE-panel | **TASK** K-20 | |
| حجز موعد (حوار) | MODAL + ACTION | MODAL + ACTION | يُفتح أيضًا من ملفّ المستفيد وتفصيل الطلب |
| تغيير حالة الموعد (حوار) | MODAL + ACTION | MODAL + ACTION | |
| بدء الجلسة | ACTION | ACTION + **TASK** K-06 | |
| BOOKED · CONFIRMED · CHECKED_IN · COMPLETED · CANCELLED · NO_SHOW | STATUS (فلتر) | STATUS | لم تصر شاشات — يُحافَظ |
| تفصيل الموعد | — | **MODAL** (درج) `?open=` | جديد |
| الجلسات `/sessions` | PAGE | PAGE | |
| مشاهدة (رابط) · ملاحظة (حوار) · إغلاق (حوار) | ACTION ×3 | ACTION ×3 + **TASK** K-07/K-08 | |
| IN_PROGRESS · COMPLETED · ABORTED | STATUS | STATUS | |
| البثّ المباشر `/sessions/:id/live` | PAGE | **ACTION** (مشاهدة) بمسار ملء الشاشة | |
| «لحظة مهمّة» (الكونسول) | ACTION | ACTION | |
| التقارير `/reports` | PAGE | PAGE | صفّ → المحرّر |
| نشر تقرير | ACTION | ACTION + **TASK** K-09 | |
| DRAFT · PUBLISHED | STATUS | STATUS | |
| من/إلى · تصدير CSV | FILTER · ACTION | FILTER · ACTION | |
| الفواتير والمدفوعات `/billing` | PAGE (4 تبويبات) | PAGE | |
| تبويبات المدفوعات · الباقات · الأرصدة (BillingLedger) | TAB ×3 | TAB ×3 | |
| ملخّص الفوترة (BillingOverview) | REPORT | REPORT | |
| عدّادات الحالة | FILTER | FILTER | |
| فاتورة جديدة · بيع باقة · إضافة سطر · إصدار · دفعة | ACTION ×5 (MODAL) | ACTION ×5 + **TASK** K-11/K-12/K-14 | + حذف سطر (موجود في الـAPI) |
| DRAFT · ISSUED · PARTIALLY_PAID · PAID · CANCELLED | STATUS | STATUS | «متأخّرة» = STATUS مشتقّة تُعرض لا تُخزَّن |
| تفصيل الفاتورة | — | **MODAL** (درج) | جديد |
| طلبات أولياء الأمور `/requests` | PAGE | PAGE | |
| قرار (حوار) | ACTION | ACTION + **TASK** K-10 | القبول يفتح الحجز |
| NEW · ACCEPTED · REJECTED · نوع الطلب | STATUS · FILTER | STATUS · FILTER | |
| المحادثات `/communications` | PAGE | PAGE | أيقونة مختلفة |
| طلبات الالتحاق `/enrolments` | PAGE | PAGE | |
| لوحة المراحل (kanban) | FILTER (عرض) | FILTER | صحيحة: الحالات أعمدة لا شاشات |
| تغيير الحالة · تحويل (حواران) | ACTION ×2 | ACTION ×2 + **TASK** K-01…K-03 | |
| NEW · CONTACTED · ASSESSMENT_BOOKED · ENROLLED · REJECTED · DUPLICATE | STATUS | STATUS | |
| تفصيل طلب الالتحاق | — | **DETAIL PAGE** `/enrolments/:id` | جديد |
| الصلاحيات والشاشات `/access` | PAGE (3 تبويبات) | **PAGE** «المستخدمون والأدوار» (4 تبويبات) | حارس `USER.MANAGE` |
| تبويب «الأشخاص» (إنشاء · أدوار · حالة · رمز · بيانات شخصية · مستندات) | TAB | TAB «المستخدمون» + TAB «ملفّات الموظّفين» (`STAFF.PII`) | فصل الوظيفتين |
| تبويب «الأدوار» | TAB | TAB | |
| تبويب «الشاشات» (تشخيص) | TAB | TAB | |
| حوار إضافة مستخدم | MODAL | MODAL | |
| سجلّ التشغيل `/ops-log` (3 تبويبات) | REPORT بمسار | REPORT (تحت الإعدادات) | |
| الإعدادات `/settings` | PAGE | PAGE «بارامترات المركز» | حارس `SETTINGS.MANAGE` |
| حوارا المركز والبارامتر | MODAL ×2 | MODAL ×2 | |
| الرفض `/denied` | PAGE | PAGE | يعرض `need` |

## ٢ · بوّابة وليّ الأمر

| الجزء | اليوم | الهدف | ملاحظة |
|---|---|---|---|
| الدخول `/login` | PAGE | PAGE | |
| الرمز `/login/otp` | MODAL بمسار | MODAL | سليم |
| طلب التحاق `/apply` | PAGE (معالج 4 خطوات) | PAGE | 🔴 + خطوة الرمز |
| خطوات المعالج الأربع | TAB ×4 (خطوات) | TAB ×4 | |
| أهلًا بك `/welcome` | PAGE (منتقي) | **ACTION** (اختيار المستفيد) — يبقى مسارًا لأوّل دخول | مبدّل في الرأس |
| «ما يحتاج انتباهك» | TASK-list (في `/welcome`) | **TASK** (في الرئيسية) | |
| الرئيسية `/home` | PAGE | PAGE | |
| المواعيد `/schedule` | PAGE | PAGE | |
| القادمة / السابقة | FILTER (تبويب) | FILTER | |
| «طلب تغيير أو إلغاء» | ACTION (يقفز) | ACTION (حوار مربوط بالموعد) | |
| استشارة أونلاين `/consultation/:id` | PAGE | **ACTION** (ادخل) بمسار ملء الشاشة | |
| بثّ مباشر `/live` | PAGE | **STATUS** (جلسة جارية) بمسار ملء الشاشة | |
| «لحظة مهمّة» (البوّابة) | ACTION (يفشل دائمًا) | **يُحذف من الواجهة** | لا مسار |
| التقدّم `/progress` | PAGE | **TAB** في «متابعة طفلي» | |
| التقارير والملاحظات `/reports` | PAGE (تبويبان) | **TAB ×2** في «متابعة طفلي» | إعادة توجيه |
| التقرير `/reports/:id` | DETAIL PAGE | DETAIL PAGE | |
| البرنامج المنزلي `/activities` | PAGE | PAGE | |
| تعليم النشاط | ACTION | ACTION | إلغاء التعليم يُخفى حتى R-09 |
| الفواتير والباقات `/billing` | PAGE | PAGE | «طرق الدفع» toast → نصّ صادق |
| طلباتي `/requests` | PAGE | PAGE (تبويبان: الطلبات · رسائل المركز) | |
| SUBMITTED · UNDER_REVIEW · ACCEPTED · DECLINED | STATUS (مفردات الواجهة) | STATUS (مفردات القاعدة: NEW · ACCEPTED · REJECTED) | R-12 |
| المحادثات `/communications` (مكوّن الموظّفين) | PAGE | **TAB** «رسائل المركز» بمكوّن أسرة | |
| الإشعارات `/notifications` | NOTIFICATION | NOTIFICATION | جرس على الهاتف |
| ملفّ الأخصائي `/therapists/:id` | DETAIL PAGE | DETAIL PAGE | |
| حسابي `/profile` | PAGE | PAGE | مفاتيح الموافقة بلا مصدر تُخفى |
| بطاقة الموافقات | ACTION (يفشل دائمًا) | **قراءة** فقط (تُدار من المركز) | |
| حوار NPS | MODAL | MODAL | |

## ٣ · الخلاصة العددية

| التصنيف | الكونسول (اليوم → الهدف) | البوّابة (اليوم → الهدف) |
|---|---|---|
| PAGE (بمدخل قائمة) | 22 → **20** بندًا في 8 مجموعات | 5+6 → 5 تبويبات + «المزيد» |
| DETAIL PAGE | 2 (الطفل، التقرير) + 1 (الأخصائي) → **5** (+ الطلب، وليّ الأمر) | 2 → 2 |
| MODAL/درج جديد | — → 2 (الموعد، الفاتورة) | — |
| صار TAB | — → 4 (`therapist-services`, `site/team`, استبيانات الرضا، الخطط التفصيلية) | — → 3 (`progress`, `reports`, `communications`) |
| صار FILTER | — → 1 (`my-day`) | — |
| STATUS كانت PAGE | **0** (الحالات فلاتر أصلًا) | 1 (`/live` — يبقى بمسار لملء الشاشة) |
| TASK مُعرَّفة | 0 → **23 نوعًا** (19 متاحة الآن) | 2 (ضمنيًّا) → 5 (+2 🔴) |
| NOTIFICATION | 1 (باسم خطأ) → 1 (باسم صحيح) | 1 → 1 |
| يُحذف من الواجهة (لا من النظام) | 0 | 3 أفعال محكوم عليها بالفشل |

</details>
