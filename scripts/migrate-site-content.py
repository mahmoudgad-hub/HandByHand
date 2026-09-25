"""One-time DEV content migration. Reuses the published site tables and exporter."""
from pathlib import Path
from html.parser import HTMLParser
import subprocess, json, re, html, shutil, datetime

ROOT=Path(__file__).resolve().parents[1]
DOCKER=Path('C:/Users/mgad8/AppData/Local/Programs/DockerDesktop/resources/bin/docker.exe')
NODE=Path('C:/Users/mgad8/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe')
def sql(query):
    r=subprocess.run([str(DOCKER),'exec','-i','hbh-db','psql','-X','-U','hbh_owner','-d','hbh','-v','ON_ERROR_STOP=1','-At','-f','-'],input=query,text=True,encoding='utf-8',capture_output=True)
    if r.returncode: raise RuntimeError(r.stderr)
    return r.stdout.strip()
def exported():
    source=(ROOT/'scripts/site-export.sh').read_text(encoding='utf-8')
    query=source.split("<<'SQL'\n",1)[1].split('\nSQL\n',1)[0].replace(":'center_code'","'HBH'")
    return json.loads(sql(query))

source=(ROOT/'site/index.html').read_text(encoding='utf-8')
if 'data-content-src' in source: raise SystemExit('Migration already applied.')
stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
backup=ROOT/'backups'/('site-db-migration_'+stamp)
shutil.copytree(ROOT/'site',backup/'site')
before=exported()
(backup/'published-before.json').write_text(json.dumps(before,ensure_ascii=False,indent=2),encoding='utf-8')
tables=['site_texts','site_contact','site_programs','site_team']
raw={t:json.loads(sql("SELECT coalesce(jsonb_agg(to_jsonb(t)),'[]') FROM hbh."+t+" t WHERE center_id=(SELECT center_id FROM hbh.centers WHERE code='HBH');")) for t in tables}
(backup/'rows-before.json').write_text(json.dumps(raw,ensure_ascii=False,indent=2),encoding='utf-8')
js="const fs=require('fs'),vm=require('vm');let c={window:{}};vm.createContext(c);for(let f of ['content.js','editorial.js'])vm.runInContext(fs.readFileSync('site/'+f,'utf8'),c);process.stdout.write(JSON.stringify(c.window.HBH_SITE_CONTENT));"
effective=json.loads(subprocess.check_output([str(NODE),'-e',js],cwd=ROOT,encoding='utf-8'))
locked={r['text_key'] for r in raw['site_texts'] if r['is_locked']}
seed={}
edits=[]
void={'img','input','meta','link','br','hr','source','wbr','area','base','embed','param','track'}
class Parser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False);self.stack=[];self.counters={};self.nodes=[]
        self.lines=[0]
        for m in re.finditer('\n',source):self.lines.append(m.end())
    def pos(self):
        row,col=self.getpos();return self.lines[row-1]+col
    def key(self,kind):
        scope=next((n['a'].get('id') for n in reversed(self.stack) if n['tag']=='section' and n['a'].get('id')), 'general')
        scope=re.sub('[^a-zA-Z0-9]','',scope)
        base='page.'+scope+'.'+kind;self.counters[base]=self.counters.get(base,0)+1
        return base+str(self.counters[base])
    def skipped(self):
        return any(n['skip'] for n in self.stack)
    def handle_starttag(self,tag,attrs):
        a=dict(attrs);classes=a.get('class','').split()
        skip=tag in ['script','style','svg'] or a.get('aria-hidden')=='true' or bool(set(classes)&{'member-card','program-card','services-grid','review-grid','faq-list','contact-map-canvas'}) or a.get('id','').startswith('contact') and a.get('id') not in ['contact']
        n={'tag':tag,'a':a,'start':self.pos(),'raw':self.get_starttag_text(),'text':[],'skip':skip or self.skipped()}
        if not n['skip'] and tag=='img':
            additions=''
            for attr in ['src','alt']:
                if a.get(attr):
                    key=self.key(attr);seed[key]=a[attr];additions+=' data-content-'+attr+'="'+key+'"'
            edits.append((n['start'],n['start']+len(n['raw']),n['raw'][:-1]+additions+'>'))
        if tag not in void:self.stack.append(n)
    def handle_endtag(self,tag):
        if not any(n['tag']==tag for n in self.stack):return
        while self.stack:
            n=self.stack.pop()
            if n['tag']==tag:break
        if not n['skip'] and n['a'].get('data-i18n'):
            key=n['a']['data-i18n'];value=effective.get('texts',{}).get(key,{}).get('ar') or ''.join(n['text']).strip()
            if key in locked:
                # Keep schema-protected statements exactly as stored.
                value=before['texts'].get(key,{}).get('ar',value)
            if value:seed[key]=value
    def handle_data(self,data):
        for n in self.stack:n['text'].append(data)
        if self.skipped() or not re.search('[A-Za-z\u0600-\u06ff]',data):return
        if any(n['a'].get('data-i18n') for n in self.stack):return
        if self.stack and self.stack[-1]['tag']=='title':
            key='page.meta.title';seed[key]=data.strip()
            n=self.stack[-1];edits.append((n['start'],n['start']+len(n['raw']),'<title data-i18n="'+key+'">'));return
        if not any(n['tag']=='body' for n in self.stack):return
        key=self.key('text');seed[key]=html.unescape(data.strip())
        start=self.pos();edits.append((start,start+len(data),'<span data-i18n="'+key+'">'+data+'</span>'))
parser=Parser();parser.feed(source)
for a,b,text in sorted(edits,reverse=True):source=source[:a]+text+source[b:]
source=source.replace('<script src="editorial.js"></script>','').replace('<script src="team-media.js"></script>','')
# Existing published text keys are retained; apply the approved editorial wording
# once in the database, never on every browser load. Protected rows are untouched.
for key,row in effective.get('texts',{}).items():
    if key not in locked and row.get('ar'):seed.setdefault(key,row['ar'])
payload=json.dumps(seed,ensure_ascii=False)
q="BEGIN;\nSELECT set_config('app.user','site-content-migration',true);\n"
q+="INSERT INTO hbh.site_texts(center_id,text_key,text_ar,status,published_at) SELECT c.center_id,j.key,j.value,'PUBLISHED',now() FROM hbh.centers c CROSS JOIN jsonb_each_text($content$"+payload+"$content$::jsonb) j WHERE c.code='HBH' ON CONFLICT (center_id,text_key) WHERE active_flg DO UPDATE SET text_ar=EXCLUDED.text_ar,status='PUBLISHED',published_at=coalesce(hbh.site_texts.published_at,now()) WHERE NOT hbh.site_texts.is_locked;\n"
contact=effective.get('contact',{})
def quote(v):return "'"+str(v).replace("'","''")+"'"
for field,col in [('hoursAr','hours_ar'),('arrivalAr','arrival_ar')]:
    if contact.get(field):q+="UPDATE hbh.site_contact SET "+col+'='+quote(contact[field])+" WHERE center_id=(SELECT center_id FROM hbh.centers WHERE code='HBH') AND active_flg AND status='PUBLISHED';\n"
for program in effective.get('programs',[]):
    q+='UPDATE hbh.site_programs SET title_ar='+quote(program['titleAr'])+',desc_ar='+quote(program['descAr'])+' WHERE program_id='+str(int(program['id']))+" AND center_id=(SELECT center_id FROM hbh.centers WHERE code='HBH');\n"
# The existing published promotional files are already the member's photo_path.
# Store that explicit profile reference; do not invent consent/media records.
q+="UPDATE hbh.site_team SET profile_href=photo_path WHERE center_id=(SELECT center_id FROM hbh.centers WHERE code='HBH') AND active_flg AND status='PUBLISHED' AND profile_href IS NULL AND photo_path IS NOT NULL;\nCOMMIT;"
(backup/'migration.sql').write_text(q,encoding='utf-8')
sql(q)
(ROOT/'site/index.html').write_text(source,encoding='utf-8')
after=exported()
(ROOT/'site/content.js').write_text('/* Generated from published DEV database rows. Do not edit. */\nwindow.HBH_SITE_CONTENT = '+json.dumps(after,ensure_ascii=False,indent=2)+';\n',encoding='utf-8')
(backup/'key-manifest.json').write_text(json.dumps(seed,ensure_ascii=False,indent=2),encoding='utf-8')
print('Managed copy/asset keys:',len(seed),'Exported keys:',len(after['texts']))
print('Backup:',backup.name)
