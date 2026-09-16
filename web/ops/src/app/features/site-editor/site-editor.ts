import { Component, ChangeDetectionStrategy, DestroyRef, inject, signal, computed } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { OpsApi, Row } from '../../core/api/ops-api';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { readAllPages } from '../../core/api/read-all-pages';
import { SITE_FIELDS } from './site-field-catalog';

@Component({selector:'hbh-site-editor', imports:[FormsModule, TranslatePipe], templateUrl:'./site-editor.html', styleUrl:'./site-editor.css', changeDetection:ChangeDetectionStrategy.OnPush})
export class SiteEditor {
  private readonly api=inject(OpsApi);
  private readonly destroy=inject(DestroyRef);
  protected readonly auth=inject(OpsAuthService);
  protected readonly rows=signal<readonly Row[]>([]);
  protected readonly loading=signal(false);
  protected readonly busy=signal(false);
  protected readonly message=signal('');
  protected readonly group=signal('slide1');
  protected readonly query=signal('');
  protected readonly selected=signal<Row|null>(null);
  protected value=''; protected english=''; protected status='DRAFT';
  protected field(row:Row){return SITE_FIELDS[String(row['text_key'])] ?? {group:'other',label:'siteEditor.other',image:false,order:9999};}
  protected readonly groups=computed(()=>[...new Set(this.rows().map(r=>this.field(r).group))]);
  protected readonly visible=computed(()=>this.rows().filter(r=>(!this.group()||this.field(r).group===this.group())&&String(r['text_ar']).includes(this.query().trim())));
  constructor(){this.load();}
  protected load(){
    this.loading.set(true); this.message.set('');
    readAllPages(page=>this.api.list('site-texts',{page,limit:100})).pipe(takeUntilDestroyed(this.destroy)).subscribe({next:rows=>{this.rows.set([...rows].sort((a,b)=>this.field(a).order-this.field(b).order));this.loading.set(false);},error:()=>{this.loading.set(false);this.message.set('siteEditor.error');}});
  }
  protected edit(row:Row){this.selected.set(row);this.value=String(row['text_ar']??'');this.english=String(row['text_en']??'');this.status=String(row['status']);this.message.set('');}
  protected asset(path:string){const name=path.split('/').pop();return name?'/api/v1/site-media/'+encodeURIComponent(name):'';}
  protected upload(event:Event){const input=event.target as HTMLInputElement;const file=input.files?.[0];input.value='';if(!file)return;this.busy.set(true);this.api.upload(file).pipe(takeUntilDestroyed(this.destroy)).subscribe({next:r=>{this.value=r.path;this.busy.set(false);},error:()=>{this.busy.set(false);this.message.set('siteEditor.error');}});}
  protected save(){
    const row=this.selected();if(!row||!this.value.trim()||this.busy())return;
    this.busy.set(true);this.message.set('');
    this.api.update('site-texts',Number(row['text_id']),{text_ar:this.value,text_en:this.english||null,status:this.status}).pipe(takeUntilDestroyed(this.destroy)).subscribe({next:()=>{this.rows.update(rows=>rows.map(r=>r['text_id']===row['text_id']?{...r,text_ar:this.value,text_en:this.english,status:this.status}:r));this.selected.set(null);this.busy.set(false);this.message.set('siteEditor.saved');},error:()=>{this.busy.set(false);this.message.set('siteEditor.error');}});
  }
}
