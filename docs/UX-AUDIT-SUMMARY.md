# ملخص مراجعة UX — 2026-09-14

**العدد الحالي: 49 شاشة تطبيق = 31 للمركز + 18 للبوابة. المستهدف: 47 = 31 + 16، بدمجين مقترحين في البوابة.** نعد كل route يرسم شاشة بما فيه الدخول والرفض والطباعة ونمطا إنشاء/تحرير التقرير؛ لا نعد shell أو redirects أو wildcard. لذلك هذا عدد مسارات شاشات وليس عدد المكونات أو بنود القائمة. الموقع العام site يضيف صفحتين، فيصير الإجمالي الموسع 51 → 49. website/index.html وhtml/ وfigma/ مراجع منفصلة لا يثبت وجودها أنها تشغيل فعلي.

**صفر حالات مستخدمة كصفحات انتظار مستقلة.** /live أداة مشاهدة قائمة، لا حالة متنكرة في شاشة. /my-day كان فلترًا بمسار وأصبح redirect بالفعل. لا صفحات انتظار ولي أمر/إسناد أخصائي في routes الحالية.

**حدود الإثبات:** جرد ساكن لكل routes ومصادر النماذج والأفعال وAPI، وتحليل للمنطق في Go والمهاجرات المتاحة، مع مشاهدة حية للدخول ولوحة المدير والمهام. لم تُختبر كل شاشة وكل دور عمليًا، ولم تُنفذ كتابة أعمال أو إرسال رسائل. تعذرت قراءة 0005_scheduling.up.sql و0006_plans_and_notes.up.sql بصلاحيات البيئة؛ لا ندعي اكتمال تدقيق SQL. تشغيل DB الحي قد يختلف عن ملفات الهجرة. تفاصيل الأدلة في [UX-AUDIT-SOURCE-INDEX.md](UX-AUDIT-SOURCE-INDEX.md)، والمسارات المحسوبة في [UX-AUDIT-ROUTES.json](UX-AUDIT-ROUTES.json).

## النتائج

**متابعة عملية:** [مراجعة رحلة الالتحاق وترتيب الإصلاح](UX-ENROLMENT-JOURNEY-REVIEW.md) تربط المنفذ بقرارات المالك OD-01/07/32/39، وتحدد حزمة واجهة مستقلة وبطاقة R01 للخلفية ومعايير قبول. هذه المتابعة تحليلية؛ لا تغييرات في قواعد العمل أو بيانات التشغيل.

- R01: مرحلة التقييم لا تكتمل بالعقد الحالي.
- R02: العدد في المهام جزئي دون بيان كاف.
- R03: ملف الأسرة قد يخفي طلبات قديمة.
- R04: الجلسة المفتوحة أمس تختفي من طابور الإغلاق.
- R05: مهمة الإسناد تفقد سياق الطفل.
- R06: الرابط العميق للموعد محدود باليوم وأول صفحة.
- R07: قبول تغيير الموعد لا يغير الموعد.
- R08: خدمات الأسرة غير متاحة دائمًا من شريط الهاتف.
- R09: الخطط والأهداف تحرر بأرقام مراجع.
- R10: الوثائق وبعض النصوص ثابتة ومتقادمة.

14 نوع مهمة فعلي؛ 8 مرشحات غير منفذة وفئة تخطيط مستقبلية لا تدخل الرقم. ثلاثة دمجات مركز تاريخية منفذة، ودمجان بوابة مقترحان فقط.

Sidebar: لوحة التحكم، المهام، الإشعارات؛ العملاء (الالتحاق، الأسر، المستفيدون)؛ التشغيل (المواعيد، الجلسات، الخطط، التقارير)؛ الماليات؛ التواصل؛ الفريق؛ الإعدادات.

## الملفات

تحديث 10 وثائق موجودة مع حفظ الأرشيف:

- [UX-SCREEN-INVENTORY.md](UX-SCREEN-INVENTORY.md)
- [UX-PROBLEMS.md](UX-PROBLEMS.md)
- [UX-BUSINESS-FLOW-MAP.md](UX-BUSINESS-FLOW-MAP.md)
- [UX-TASK-INBOX.md](UX-TASK-INBOX.md)
- [UX-TARGET-INFORMATION-ARCHITECTURE.md](UX-TARGET-INFORMATION-ARCHITECTURE.md)
- [UX-DETAIL-PAGES.md](UX-DETAIL-PAGES.md)
- [UX-ROLE-BASED-VIEWS.md](UX-ROLE-BASED-VIEWS.md)
- [UX-CURRENT-TO-TARGET.md](UX-CURRENT-TO-TARGET.md)
- [UX-SCREEN-CLASSIFICATION.md](UX-SCREEN-CLASSIFICATION.md)
- [UX-REDESIGN-IMPLEMENTATION-PROMPT.md](UX-REDESIGN-IMPLEMENTATION-PROMPT.md)

إنشاء UX-AUDIT-ROUTES.json وUX-AUDIT-SOURCE-INDEX.md وUX-AUDIT-SUMMARY.md.

ملف التكليف: [UX-REDESIGN-IMPLEMENTATION-PROMPT.md](UX-REDESIGN-IMPLEMENTATION-PROMPT.md). لا تنفيذ Frontend/Backend/DB في هذه المراجعة.
