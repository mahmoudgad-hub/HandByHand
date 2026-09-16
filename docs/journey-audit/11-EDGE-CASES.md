# الحالات غير السعيدة وحدود التحقق

هذه مصفوفة تغطية من شروط القوالب وعقود النتائج؛ ليست سجل نجاح اختبارات حية. شاشة فيها skeleton ليست مكتملة تلقائيًا. المعرّفات من [09](09-SCREEN-TO-SCREEN-MAP.md)، والتحليل من [10](10-UX-CLARITY-AUDIT.md).

## مفتاح القراءة

`م` = معالج في المصدر، `ج` = جزئي/عام، `ح` = guard مصادقة/صلاحية مع رفض row من الخادم، `غ` = فجوة، `—` = لا ينطبق. E=Empty/No records؛ L=Loading؛ X=Error/retry؛ P=Permission denied؛ M=Missing information. لا تعني «م» أن النص/التخطيط اجتاز اختبار مستخدم. الحالات المحاسبية الخاصة منفصلة أسفل الجدول.

## البوابة — شاشة بشاشة

| Screen | E | L | X | P | M | ملاحظة عملية ومعيار الخروج |
|---|---|---|---|---|---|---|
| P01 login | — | م busy | م failure | ج locked عبر OTP | م phone validation | ENROLMENT_PENDING لا يذهب لشاشة انتظار رمز غير مرسل |
| P02 OTP | — | م | م wrong/expired/locked | ج | م code | يوضح المحاولات وإعادة البدء؛ input/paste يحتاج تحققًا |
| P03 apply | — | م submit busy | م field/network/429 | — public | ج required basics | فشل لا يمحو البيانات؛ consent checkbox ليس إثبات mobile |
| P04 welcome | م no children | م | م | ح | غ completion | لا طفل لا يعني أن الأسرة يجب أن تعيد نفس الطلب |
| P05 home | م no next | م | م مع partial balance | ح | ج | لا تعرض 0 مستحق عند فشل القراءة |
| P06 schedule | م upcoming/past | م | م retry | ح | ج | CANCELLED/NO_SHOW تبقيان مرئيتين حسب النطاق لا حجز جديد |
| P07 progress | م no goals | م | م | ح | م not measured | لا تعرض baseline كإنجاز جديد |
| P08 reports | م no reports | م | م | ح | غ report due | «لا منشور» يختلف عن «التقرير متأخر» |
| P09 notes | م no notes | م | م | ح | غ note due | لا كشف INTERNAL لمعالجة الفراغ |
| P10 report | ج unavailable | م | م 404/retry | ح | ج | رفض غير مملوك لا يكشف عنوانًا أو طفلًا |
| P11 activities | م no programme | م | م | ح | ج | double submit لا يسجل اليوم مرتين؛ بعض الأفعال تُعطّل بعد التنفيذ |
| P12 billing | م invoices؛ ج packages | م | م retries لكل جزء | ح | غ receipt/installment | لا رصيد وهمي ولا مساواة بيع الباقة بالدفع |
| P13 requests | م empty list | م | ج generic save | ح + child | م appointment/date/time | فشل تحميل المواعيد يمنع طلب تغيير غير مرتبط |
| P14 messages | م no messages | م | م preserve draft | ح | ج no contact | request_id يعاد استخدامه عند إعادة نفس محاولة الإرسال |
| P15 consultation | — | م | م refusals | م not-found | ج | يفرق unavailable/expired؛ مشكلة CONFIRMED/CHECKED_IN قائمة |
| P16 live | م no live/refusal | م | م | م consent/window | ج | لا تسجيل/مشاهدة بعد انتهاء session |
| P17 therapist | ج unavailable | م | م | ح | ج unpublished | غياب profile منشور ليس خطأ booking |
| P18 notifications | م empty | م | م | ح | غ target/context | اضغط NOTE فيفتح notes للطفل الصحيح؛ غير متحقق الآن |
| P19 profile | ج children/contact | م | م save failure | ح | غ completeness | switches لا تتظاهر أن رفضها عطل عابر |
| NPS | م no due | ج | ج | ح | — | التخطي ينهي الإلحاح طبقًا للـcooldown |

المصادر: قوالب features في portal، [HTTP adapter](../../web/portal/src/app/core/api/http-portal-api.ts)، [Portal errors](../../web/portal/src/app/core/api/portal-error.ts)، [Guard](../../web/portal/src/app/core/auth/auth.guard.ts).

## Console/Admin — شاشة بشاشة

| Screen | E | L | X | P | M | أهم الاستثناءات |
|---|---|---|---|---|---|---|
| O01 login | — | م | م | ج | م | حساب غير جاهز/كلمة مرور/قفل؛ تحقق حي مطلوب |
| O02 dashboard | ج | م أجزاء | ج أجزاء | ح tiles | ج | نص no remaining مربوط بشرط غير صحيح JG-21 |
| O03 tasks | م filtered/empty | م | م partial/all | ح per source | غ missing task types | لا تكتب «لا مهام» إذا source فشل أو النوع غير مبني |
| O04 notifications | م unread/all | م | م | ح | ج | read receipt ليس task completion |
| O05 guardians | م no records/no search match | م | م | ح | ج | contact/grant portal gap؛ المراجع بالأسماء أضيفت |
| O06 guardian detail | م not-found | م parts | م partial | م denied | ج | فشل المال لا يمحو بقية الأسرة |
| O07 children | م search/empty | م | م | ح | ج | incomplete record لا يعالج تلقائيًا |
| O08 child profile | م لكل tab | م أجزاء | م retries | م denied | ج | assessment غياب ميزة لا «طفل بلا تقييم» مؤكدة |
| O09 card | ج | ج | ج | ح | ج | الاسم/الصورة/الطباعة يختبر فعليًا؛ لا نفترض نجاحها |
| O10 new report | — | م | م save/conflict | ح | م title/period | مسودة لم تحفظ لا يصح نشرها |
| O11 edit report | ج not-found | م | م conflict/latest | ح | ج | PUBLISHED غير قابل للتحرير كالمسودة |
| O12 therapists | م | م | م | ح | ج | services matrix بلا خدمات/أخصائيين لها empty |
| O13 profile editor | ج | م | م | ح row ownership | ج consent | تأكد أن مالك الملف فقط يمنح موافقته |
| O14 rooms | م | م | م | ح | ج | absent camera/room ليس no appointments |
| O15 plans | م | م | م | ح | غ approval | وجود DRAFT بلا action تفعيل يوقف الدورة |
| O16 catalog | م | م | م | ح | ج | عدم وجود سعر/خدمة يفسر في الحجز لا يفاجئ بعده |
| O17 site | م resource/team | م | م | ح edit/publish | ج blockers | بعض الموارد fixed rows؛ لا زر إنشاء يوهم بإمكان ممنوع |
| O18 appointments | م table/week | م | م slot/filter | ح book/start | م preflight | conflict/no slots/permission distinct؛ booking race يرفض DB |
| O19 sessions | م | م | م | ح | غ missing note/report | لا task missing note من صفوف sessions حاليًا |
| O20 reports | م | م | م | ح | غ never created | مسودة موجودة غير تقرير كان ينبغي أن يوجد |
| O21 billing | م ledger | م | م | ح view/manage | غ receipt/schedule | فشل المصدر لا يظهر أنه صفر حسابات |
| O22 requests | م | م | م | ح | ج optional note | قبول بلا تنفيذ؛ رفض بلا تفسير كافٍ محتمل |
| O23 enrolments | م board/table | م | م | ح | غ assessment date | ASSESSMENT_BOOKED يتطلب تاريخًا لا يسأل النموذج عنه |
| O24 enrolment detail | م not-found | م | م | م denied | غ assignment/assessment | timeline لا يخترع أحداثًا لا timestamps لها |
| O25 live | ج | م | م | ح + API | ج | provider/window/offline، ليس join استشارة |
| O26 users | م filtered | م | م | ح | ج | منع عرض أفعال admin لمن لا يحملها مع رفض DB |
| O27 satisfaction | م no responses | م | م | ح | — | عدم وجود ردود لا يساوي رضا 100% |
| O28 ops-log | م | م | م | ح | غ full health | log API لا يثبت سلامة reminder/SMS/backup |
| O29 settings | ج | م | م | ح | م typed values | إزالة override تعرض العودة للقيمة العامة |
| O30 denied | — | — | — | م | — | code مفيد للإدارة؛ اسم المسؤول عن المساعدة مطلوب |
| O31 communications | م | م | م | ح | ج | تبديل الأسرة يحتفظ بمسودتها، الرد يحتاج can_send |

المصادر: [DayScreen](../../web/ops/src/app/features/day/day-screen.html)، [ResourceScreen](../../web/ops/src/app/features/resource/resource-screen.html)، قوالب تفاصيل guardian/child/enrolment، report-editor، tasks، و[FamilyMessages](../../web/shared/src/ui/family-messages.ts). معنى ح هو وجود guard/RLS في التصميم؛ لم يُثبت sweep حي لكل permission في هذه الجولة.

## الأحداث الطرفية العابرة للشاشات — مصفوفة قبول

| ID | السيناريو / الحالة | الواقع المثبت أو الحد | صاحب العلاج المستهدف | النجاح الذي يجب أن يراه المستخدم |
|---|---|---|---|---|
| X01 | نفس الهاتف لوليي أمر | OD-26 يسمح به؛ find_guardian_matches يفضل حسابًا وحيدًا، convert الحالي LIMIT 1 لا يستعمله | Manager | لا دمج اعتباطي؛ اختيار موثق عند ambiguity |
| X02 | نفس الطفل بطلبين | conversion ينشئ child جديدًا ولا يستعمل find_child_matches | Reception/Manager | فتح الموجود بدل تكرار الملف أو حالة مراجعة تعارض |
| X03 | إرسال ناجح ورد الشبكة ضاع | apply لا يحمل idempotency key صريحًا | System | لا duplicate application من مجرد retry؛ أظهر نتيجة مؤكدة |
| X04 | أسرة بلا user بعد الإدخال المباشر | grant موجود DB ولا CTA مباشر | Admin | إتاحة دخول من شاشة الأسرة مع تفسير التعارض |
| X05 | OTP قديم/خاطئ/مقفول | واجهة نتائج وعد تنازلي؛ القاعدة تدير العمر والمحاولات | Guardian/System | إعادة محاولة آمنة لا loop لا ينتهي |
| X06 | رقم دولي في apply | form يفرض 01 + 11 رقمًا؛ DB يدعم canonical mobile دوليًا | Product/System | تنسيق متسق مع سياسة الجمهور المستهدف؛ لا رفض متناقض |
| X07 | طلب تقييم بلا assessment_at | 0110 constraint؛ status payload لا يحمل التاريخ | Reception | اختيار وقت حقيقي أو لا تعرض الحالة كإجراء متاح |
| X08 | فتحة شغلها موظف آخر | validate ثم book لا يغني عن DB conflict | Reception/System | يحتفظ بالاختيارات ويعرض بدائل جديدة، لا حجز مزدوج |
| X09 | تغيير مقبول والبديل فشل | القرار لا ينفذ شيئًا | Reception | يبقى «بانتظار التنفيذ» ولا يبلغ تغييرًا لم يحدث |
| X10 | أخصائي لا يقدم الخدمة | slot validation/matrix يتحققان؛ caseload العام مختلف | Manager | منع الإسناد غير المناسب قبل يوم الجلسة |
| X11 | إلغاء أخصائي بعد دفع | لا refund/makeup workflow مرتبط | Manager/Finance | حالة المبلغ والبديل والسبب واضحة للأسرة |
| X12 | No-show | حالة متاحة؛ لا متابعة تلقائية | Reception | اتصال/سبب/قرار تعويض أو تحصيل بحسب السياسة |
| X13 | session ABORTED | session تختلف عن Appointment الذي قد يصبح COMPLETED | Specialist | «توقفت الجلسة» لا «نجاح علاجي»؛ سبب وفاتورة منفصلان |
| X14 | إغلاق بلا note/report | مسموح من المسار الحالي | Specialist/Manager | تقرير قيد الإعداد بموعد، ومهمة missing documentation |
| X15 | حفظ تقرير من نافذتين | 0141 expected version وUI conflict | Specialist | رسالة تغيير وحل واضح، لا overwrite صامت |
| X16 | رابط تقرير غير مملوك/مسودة | 404/RLS | System | غير متاح دون كشف بيانات |
| X17 | إشعار طفل B والطفل A مختار | adapter يحمل childId، navigation لا يختاره | System | title والصفحة والطفل المقصود متطابقون |
| X18 | فشل balance دون invoices | retry مستقل وnull balance | System | «تعذر حساب المستحق» لا 0 |
| X19 | إثبات مرفوض | لا receipt workflow | Reviewer | سبب، إعادة رفع، مهلة الحجز والمبلغ |
| X20 | مهلة دفع منتهية وإثبات متأخر | لا payment-window workflow موصول | Finance/Reception | لا تأكيد فتحة غير متاحة؛ راجع المبلغ والبديل |
| X21 | مراجعان يوافقان الإيصال نفسه | غير مبني | System/Reviewer | قرار ودفعة واحدة؛ يعرض القرار السابق للثاني |
| X22 | دفعة جزئية | PARTIALLY_PAID ومبلغ مدفوع متاحان | Finance | مستحق متبقٍ مع معنى التفعيل من payment plan |
| X23 | إغلاق جلستين على آخر رصيد | consumer FOR UPDATE لكن غير منادى | System | تخصيص رصيد بلا مضاعفة/سالب بعد التوصيل |
| X24 | Package expiry | expire_packages يحتاج maintenance | System/Finance | انتهاء وماذا حدث للمتبقي، لا إنذار وهمي |
| X25 | Freeze/upgrade/compensation | design فقط في المسار الحالي | Manager | شروط وسبب وأثر على الجدول والرصيد والمال |
| X26 | قسط AFTER_SESSIONS | 0142 يقبله كتعريف ويتركه PENDING حتى layer B | Finance | لا تعرض موعد استحقاق مختلق ولا reminder مفقود كأنه نجح |
| X27 | online CHECKED_IN | gate يرفض لأنه ليس CONFIRMED | System/Reception | حضور لا يسحب أهلية لقاء مدفوع |
| X28 | online CONFIRMED بلا payment | gate status-only + confirmation مستقل | System | فحص الاستحقاق الحقيقي قبل pass |
| X29 | provider غير جاهز/رخصة منتهية | consultation refusal وexpiry | Ops | إعادة اتصال/تواصل دون إعادة حجز أو دفع غير لازم |
| X30 | سحب موافقة بث | Staff path موصول، parent switches غير موصولة | Reception/System | تحكم واضح مع نتيجة فعلية؛ لا toast عام يترك الأسرة محتارة |
| X31 | SMS provider أو maintenance توقف | outbox موجود، نجاح insert ليس delivery | Ops | تنبيه تشغيلي وfallback داخل البوابة من دون إعلان وصول كاذب |
| X32 | موظف دور عرض فقط | guard/action permission | Admin | «قراءة فقط؛ راجع المسؤول» لا زر يرفض كل مرة |
| X33 | لا نتائج بحث | resource-screen يميز search empty | Staff | مسح الفلتر لا إنشاء سجل مكرر فورًا |
| X34 | موبايل ضيق/تكبير/كيبورد | CSS فقط فُحص | Design/QA | CTA/error/focus يظلون قابلين للوصول |

## صفحات غير موجودة لا يجوز احتساب states لها ناجحة

لا Empty/Loading/Error منفذة لـ receipt review أو self-book consultation أو assessment editor أو approve plan أو freeze package أو completion wizard. تُكتب states المطلوبة مع بناء هذه الأفعال داخل السطح الموجود، لا توضع علامة مكتمل لأنها تشبه dialog عام.

## سجل التحقق والتشغيل اللاحق

المراجعة الحالية لم تكتب fixtures أو تشغل migrations أو acceptance scripts. بعد إتاحة نسخة اختبار مرتبطة بالمصدر الحالي: ابدأ بحسابات صناعية لأدوار Guardian/Reception/Therapist/Center Admin؛ نفذ رحلة جديدة من واجهة النظام دون INSERT يدوي؛ مرّ على X01–X34 مع بيانات غير حقيقية. افحص RLS بوصول غير مملوك، ودفعًا مكررًا، وموبايلًا حقيقيًا؛ لا تعلن نتائج قبل تنفيذها.
