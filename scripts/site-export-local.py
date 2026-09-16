"""Export published DEV site content using the same query as site-export.sh.
Run once, or with --watch to refresh changed content every 10 seconds.
No web/API endpoint or database credentials are exposed to the browser.
"""
from pathlib import Path
import subprocess, json, time, sys, os, datetime
ROOT=Path(__file__).resolve().parents[1]
DOCKER='C:/Users/mgad8/AppData/Local/Programs/DockerDesktop/resources/bin/docker.exe'
def export():
    script=(ROOT/'scripts/site-export.sh').read_text(encoding='utf-8')
    query=script.split("<<'SQL'\n",1)[1].split('\nSQL\n',1)[0].replace(":'center_code'","'HBH'")
    result=subprocess.run([DOCKER,'exec','-i','hbh-db','psql','-X','-U','hbh_owner','-d','hbh','-v','ON_ERROR_STOP=1','-At','-f','-'],input=query,encoding='utf-8',capture_output=True,timeout=30)
    if result.returncode:raise RuntimeError(result.stderr.strip())
    data=json.loads(result.stdout)
    if not isinstance(data,dict) or not isinstance(data.get('texts'),dict):raise RuntimeError('Invalid export; current file preserved')
    target=ROOT/'site/content.js'
    old=json.loads(target.read_text(encoding='utf-8').split('window.HBH_SITE_CONTENT =',1)[1].strip().rstrip(';'))
    changed={k:v for k,v in old.items() if k!='generatedAt'}!={k:v for k,v in data.items() if k!='generatedAt'}
    if changed:
        tmp=target.with_suffix('.js.tmp')
        tmp.write_text('/* Generated from published DEV database rows. Do not edit. */\nwindow.HBH_SITE_CONTENT = '+json.dumps(data,ensure_ascii=False,indent=2)+';\n',encoding='utf-8')
        tmp.replace(target)
    return changed
if __name__=='__main__':
    watch='--watch' in sys.argv
    status=ROOT/'backups/site-export-local-status.json'
    while True:
        try:
            changed=export()
            status.write_text(json.dumps({'pid':os.getpid(),'checkedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'ok':True,'changed':changed}),encoding='utf-8')
            if not watch:print('Published content exported.' if changed else 'Published content is up to date.')
        except Exception as exc:
            status.write_text(json.dumps({'pid':os.getpid(),'ok':False,'error':str(exc)}),encoding='utf-8')
            if not watch:raise
        if not watch:break
        time.sleep(10)
