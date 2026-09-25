from pathlib import Path
import re, json, shutil, datetime

root = Path(__file__).resolve().parents[1]
site = root / 'site'
if (site / 'editorial.js').exists():
    raise SystemExit('Refinement already applied; do not rerun this migration.')
backup = root / 'backups' / ('site-before-ux-refinement_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
shutil.copytree(site, backup)
html = (site / 'index.html').read_text(encoding='utf-8')
replacements = {
 'ابدأ طلب التحاق': 'اطلب تقييم لطفلك',
 'ابدأ بطلب التحاق': 'اطلب تقييم لطفلك',
 'ابدأ بطلب تقييم': 'اطلب تقييم لطفلك',
 'احجز تقييم طفلك': 'اطلب تقييم لطفلك',
 'طلب التحاق': 'اطلب تقييم لطفلك',
 'تتابع الأسرة الجلسة لحظة حدوثها من بوابتها. ولا شيء يُسجَّل أو يُحفظ أو يُنزَّل: المنع مفروض في قاعدة البيانات نفسها، لا في سياسة مكتوبة على ورق.': 'تابع جلسة طفلك مباشرة من بوابتك، بخصوصية واطمئنان. البث أثناء الجلسة فقط، بدون تسجيل أو حفظ أو تنزيل.',
 'وليّ الأمر يرى بيانات طفله فقط. الصلاحية تُفحص في الخادم عند كل طلب، ولا يغيّرها تعديل الرابط.': 'بيانات طفلك متاحة لك وللفريق المسؤول عن رعايته، مع الحفاظ على خصوصية كل أسرة.',
 'البثّ مباشر فقط. لا يوجد تسجيل ولا مكتبة مقاطع ولا رابط تنزيل، ولا طريقة لمشاهدة الجلسة بعد انتهائها. هذه ليست إعدادًا يمكن تغييره لاحقًا؛ النظام لا يقبل تخزين مقطع من الأساس.': 'تابع طفلك لحظة بلحظة أثناء الجلسة من بوابتك. البث مباشر فقط؛ لا تُسجَّل الجلسات ولا تُحفظ، ولا يمكن تنزيلها أو مشاهدتها بعد انتهائها.',
 'وليّ أمر الطفل، والأخصائيون المسؤولون عنه، وإدارة المركز في حدود عملها. لا يصل وليّ أمر إلى بيانات طفل آخر، والخادم هو ما يفرض ذلك عند كل طلب. وكل قراءة لبيانات حسّاسة تُسجَّل.': 'وليّ أمر الطفل، والأخصائيون المسؤولون عنه، وإدارة المركز في حدود عملها. لكل أسرة خصوصيتها، ولا يمكن لوليّ أمر الاطلاع على بيانات طفل آخر.',
 'من 9 صباحا ال9 مساءا': 'من 9 صباحًا إلى 9 مساءً',
 'الانتركم الزوار قبل الاخير فى حالة ان البوابة مغلقة': 'إذا كانت البوابة مغلقة، استخدم زر الزوار قبل الأخير في الإنتركم.',
 'أونلاين وإعداد أخصائيين': 'تدريب وإعداد الأخصائيين',
 'دورات تدريبية وإعداد أخصائيين في مجالات متنوعة، أونلاين وحضوريًا.': 'للأخصائيين: دورات تدريبية للتطوير المهني، أونلاين وحضوريًا. تواصل لمعرفة البرامج المتاحة.',
 'لأن احتياجات كل طفل مختلفة، نوفر مجموعة من البرامج والأنشطة المتخصصة التي تدعم نموه في مختلف الجوانب.': 'أنشطة وبرامج مكملة تُختار حسب احتياج الطفل، إلى جانب خدماتنا الأساسية. ويتوفر مسار منفصل لتدريب الأخصائيين.',
}
# Replace longest phrases first in fallback markup.
for old in sorted(replacements, key=len, reverse=True):
    html = html.replace(old, replacements[old])
# Keep generated exports intact. Apply only these exact approved old phrases,
# so future editorial changes in the console are not overwritten.
editorial = '/* Approved public-page wording; loaded after generated content.js. */\n(function () {\n  var changes = ' + json.dumps(replacements, ensure_ascii=False, indent=2) + ';\n  function visit(value) {\n    if (typeof value === "string") return Object.prototype.hasOwnProperty.call(changes, value) ? changes[value] : value;\n    if (value && typeof value === "object") Object.keys(value).forEach(function (key) { value[key] = visit(value[key]); });\n    return value;\n  }\n  visit(window.HBH_SITE_CONTENT);\n}());\n'
(site / 'editorial.js').write_text(editorial, encoding='utf-8')
html = html.replace('<script src="content.js"></script>', '<script src="content.js"></script>\n<script src="editorial.js"></script>')
# Six navigation choices; all other sections remain in the page and footer.
start = html.index('<nav class="nav"')
end = html.index('</nav>', start)
nav = html[start:end]
for anchor in ['programs', 'portal', 'faq']:
    nav = re.sub(r'\s*<a href="#' + anchor + r'"[^>]*>.*?</a>', '', nav)
html = html[:start] + nav + html[end:]
# Move complete, non-nested sections without changing their content.
sections = {}
for match in re.finditer(r'<section\b[^>]*>.*?</section>', html, re.S):
    ident = re.search(r'\bid="([^"]+)"', match.group().split('>')[0])
    if ident: sections[ident.group(1)] = match.group()
order = ['home','child-needs','services','programs','why','team','reviews','live','portal','how','packages','online-consultation','faq','contact','cta']
available = [key for key in order if key in sections]
slots = iter(available)
html = re.sub(r'<section\b[^>]*>.*?</section>', lambda m: sections[next(slots)] if any(m.group() == sections[k] for k in available) else m.group(), html, flags=re.S)
html = html.replace('اعرف تكلفة التقييم المناسب لطفلك', 'نؤكد نوع التقييم وتكلفته قبل الموعد')
html = html.replace('اسأل عن تنظيم جلسات طفلك ضمن خطة واضحة.', '8 جلسات ضمن خطة طفلك؛ نحدد توزيعها ومواعيدها معك بعد التقييم.')
html = html.replace('ناقش مع المركز الخطة الأنسب لاستمرار المتابعة.', '16 جلسة ضمن خطة طفلك؛ نحدد توزيعها ومواعيدها معك بعد التقييم.')
html = html.replace('ابدأ رحلة طفلك اليوم. لو لسه غير متأكد', 'أرسل طلبك، وسيتواصل معك المركز لتأكيد التفاصيل وموعد التقييم. لو لسه غير متأكد')
(site / 'index.html').write_text(html, encoding='utf-8')
with (site / 'journey-additions.css').open('a', encoding='utf-8') as f:
    f.write('\n/* Readable supporting copy while preserving the existing palette. */\n.section-title>p,.fine,.journey-fine,.journey-online-steps p:not(.journey-small-title){color:#50636b}\n.contact-card .fine{font-size:13px;line-height:1.8}\n.location-card p{font-size:16px;line-height:1.9}\n.nav{gap:18px}\n')
print('Backup:', backup)
print('Section order:', available)
