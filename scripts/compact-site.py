from pathlib import Path
import re, shutil, datetime
root=Path(__file__).resolve().parents[1]
site=root/'site'
p=site/'index.html'
html=p.read_text(encoding='utf-8')
if 'compact-disclosure' in html: raise SystemExit('Already compacted')
shutil.copytree(site,root/'backups'/('site-before-compacting_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S')))
sections={}
depth=0
for m in re.finditer(r'</?section\b[^>]*>',html):
    if not m.group().startswith('</'):
        if depth==0: start=m.start()
        depth+=1
    else:
        depth-=1
        if depth==0:
            block=html[start:m.end()]
            ident=re.search(r'\bid="([^"]+)"',block.split('>')[0])
            if ident: sections[ident.group(1)]=block
hero=sections['home']
first=re.search(r'<section class="hp-slide hp-active">.*?</section>',hero,re.S).group()
first=re.sub(r'<a[^>]*data-portal="login".*?</a>','',first,flags=re.S)
hero='<section class="hero premium-hero" id="home" aria-label="تعرف على مركز Hand by Hand"><div class="hp-slides">'+first+'</div></section>'
def disclosure(title,body,extra=''):
    return '<details class="compact-disclosure" '+extra+'><summary>'+title+'</summary><div class="compact-details-body">'+body+'</div></details>'
def append_inside(block,addition):
    at=block.rfind('</div>')
    return block[:at]+addition+block[at:]
needs='<div id="child-needs" class="compact-needs"><h3>هل طفلك يحتاج دعمًا؟</h3><p>تأخر كلام · تشتت انتباه · صعوبات تعلم · تحديات سلوكية · تواصل اجتماعي · احتياجات حسية أو حركية</p><p>مش مطلوب منك تعرف اسم الخدمة. احكِ لنا ما يقلقك، ونساعدك تحدد البداية المناسبة.</p></div>'
services=sections['services'].replace('<div class="services-grid">',needs+'<div class="services-grid">',1)
services=append_inside(services,disclosure('فرص أكبر .. لتنمية شاملة — استكشف البرامج الإضافية',sections['programs']))
why=sections['why']
# Keep one concise explanation of follow-up, with details on demand.
why=append_inside(why,disclosure('كيف تتابع طفلك؟ البوابة والبث المباشر والخصوصية',sections['live']+sections['portal']))
online='<div class="compact-online" id="online-consultation"><div><h3>بعيد عننا؟ ابدأ أونلاين</h3><p>استفسر عن استشارة أونلاين لفهم احتياج طفلك وتحديد الخطوة التالية.</p></div><a class="btn outline" href="#contact">استفسر عن الاستشارة</a></div>'
how=append_inside(sections['how'],online+disclosure('خيارات الجلسات والباقات — اعرف التفاصيل',sections['packages']))
faq=sections['faq']
faq=re.sub(r'<div class="faq-list journey-extra-faq">.*?</div>','',faq,flags=re.S)
# The strongest closing phrase stays as a small lead-in to contact, not a second CTA section.
contact=sections['contact'].replace('<h2 data-i18n="contact.title">','<span class="journey-kicker">كل طفل قصة نجاح جديدة</span><h2 data-i18n="contact.title">',1)
contact=contact.replace('<p data-i18n="contact.sub">','<p class="compact-promise">مستقبل أكثر إشراقًا لطفلك يبدأ بخطوة.</p><p data-i18n="contact.sub">',1)
new='\n\n'.join([hero,services,why,sections['team'],sections['reviews'],how,faq,contact,sections['cta']])
main=re.search(r'<main\b[^>]*>',html)
end=html.index('</main>',main.end())
html=html[:main.end()]+'\n'+new+'\n'+html[end:]
html=html.replace('<script src="hero-slider.js" defer></script>','<script src="compact-page.js" defer></script>')
# The navigation should not lead into closed content.
navstart=html.index('<nav class="nav"')
navend=html.index('</nav>',navstart)
nav=html[navstart:navend].replace('<a href="#packages">الباقات</a>','')
html=html[:navstart]+nav+html[navend:]
p.write_text(html,encoding='utf-8')
print('Compacted page; previous version saved in backups.')
