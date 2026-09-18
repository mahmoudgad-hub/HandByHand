import {ActivatedRoute} from '@angular/router';
import {Icon} from '../icon/icon';
import {TranslatePipe} from '../i18n/translate.pipe';
import {I18nService} from '../i18n/i18n.service';
import {Component,inject,signal,DestroyRef,input,ElementRef,viewChild,Injector,afterNextRender} from '@angular/core';
import {interval,forkJoin,of,map,catchError,finalize} from 'rxjs';
import {HttpClient,HttpParams} from '@angular/common/http';
import {takeUntilDestroyed} from '@angular/core/rxjs-interop';
import {HBH_CONFIG} from '../config/app-config';
import {FormatService} from '../format/format.service';
import {UserAvatar,UserAvatars} from './user-avatar';
interface Contact{guardian_id:number;user_id?:number;kind?:'staff'|'guardian'|'legacy';role?:'reception'|'therapist'|'manager';name:string;can_send:boolean;last_message?:string;last_at?:string;unread:number;can_manage:boolean}
interface Message{message_id:number;body:string;mine:boolean;created_at:string}
@Component({selector:'hbh-family-messages', imports:[Icon,TranslatePipe,UserAvatar], templateUrl:'./family-messages.html', styleUrl:'./family-messages.css'})
export class FamilyMessages{
 protected readonly avatars=inject(UserAvatars);
 private readonly i18n=inject(I18nService);
 readonly active = input(true);
 readonly guardianPortal = input(false);
 protected recipientRole=signal<'reception'|'therapist'|'manager'>('therapist');
 protected readonly roleLabels={reception:'موظف الاستقبال',therapist:'أخصائي',manager:'مدير المركز'};
 protected readonly roleOptions=['reception','therapist','manager'] as const;
 protected bulkRecipients(){return this.contacts().filter(c=>c.can_send&&c.kind!=='legacy'&&(!this.guardianPortal()||c.role===this.recipientRole()));}
 protected openRole(role:'reception'|'therapist'|'manager'){
  if(this.sending())return;
  this.recipientRole.set(role);this.recipients.set([]);this.allStaff.set(false);this.bulkStatus.set('');this.openBulk();
 }
 protected chooseRecipient(contact:Contact){this.closeBulk();this.select(contact);}
 protected selectAllTherapists(){this.recipients.set(this.bulkRecipients().map(c=>c.guardian_id));}
 private injector=inject(Injector);
 private messageList=viewChild<ElementRef<HTMLElement>>('messageList');
 private bulkDialog=viewChild<ElementRef<HTMLDialogElement>>('bulkDialog');
 protected openBulk(){if(!this.sending())this.bulkDialog()?.nativeElement.showModal();}
 protected closeBulk(){if(!this.sending())this.bulkDialog()?.nativeElement.close();}
 private route=inject(ActivatedRoute,{optional:true});
 private pendingPeer:number|null=null;
 // CH-05. A conversation you may not see reads as an empty list and a send to
 // it is refused 403 - never 404, because the existence check IS the leak: it
 // would tell anybody trying user_id numbers which are real and which are
 // parents. That silence belongs in the service and not on the screen, so ONE
 // sentence covers both a hidden account and one that was never there, and it
 // does not invite a retry that is refused for the same reason every time.
 private peerRefused(){this.selectionMade=true;this.error.set(this.i18n.translate('chat.cannotMessage'));}
 protected audience=signal('all');
 protected allStaff=signal(false);
 private broadcastAttempt:{body:string;id:string}|null=null;
 protected visibleContacts(){return this.contacts().filter(c=>(!this.guardianPortal()||(!!c.last_at&&!!c.role&&c.name.includes(this.appliedQuery)))&&(this.audience()==='all'||c.kind===this.audience()));}
 // Negative UI keys identify private account conversations; positive keys retain family history.
 private threadUrl(key:number){return this.base+(key<0?'/direct-messages/'+(-key):'/family-messages/'+key);}
 private selectionMade=false;
 protected initials(name:string){return name.trim().split(/\s+/).slice(0,2).map(part=>part[0]).join(' ');}
 protected backToContacts(){if(this.sending())return;const contact=this.selected();if(contact)this.drafts.set(contact.guardian_id,this.draft());this.version++;this.selected.set(null);this.messages.set([]);this.loading.set(false);this.error.set('');}
 private positionMessages(older:boolean,height:number,top:number,follow:boolean){afterNextRender(()=>{const list=this.messageList()?.nativeElement;if(!list)return;if(older)list.scrollTop=top+list.scrollHeight-height;else if(follow)list.scrollTop=list.scrollHeight;},{injector:this.injector});}

 private http=inject(HttpClient);private base=inject(HBH_CONFIG).apiBaseUrl+'/api/v1';private destroy=inject(DestroyRef);protected format=inject(FormatService);
 protected query=signal('');protected contacts=signal<Contact[]>([]);protected contactsLoading=signal(false);protected moreContacts=signal(false);protected selected=signal<Contact|null>(null);
 protected messages=signal<Message[]>([]);protected draft=signal('');protected error=signal('');protected sending=signal(false);protected loading=signal(false);protected more=signal(false);
 private messagesPending=0;private contactsPending=0;private appliedQuery='';
 private version=0;private contactVersion=0;private drafts=new Map<number,string>();private attempt:{guardian:number;body:string;id:string}|null=null;
 protected canManage=(c:Contact)=>c.can_manage;
 protected recipients=signal<number[]>([]);protected bulkBody=signal('');protected bulkStatus=signal('');private bulkAttempts=new Map<number,{body:string;id:string}>();
 protected templates=[{title:'تذكير بالموعد',body:'مرحبًا، نرجو مراجعة موعد طفلكم القادم في قسم المواعيد بالبوابة وتأكيد الحضور. شكرًا لتعاونكم.'},{title:'تقرير جديد',body:'مرحبًا، يمكنكم الاطلاع على التقارير المتاحة لطفلكم من قسم التقارير بالبوابة.'},{title:'التواصل مع المركز',body:'مرحبًا، يرجى التواصل مع فريق المركز بخصوص متابعة طفلكم. يسعدنا مساعدتكم.'}];
 protected useTemplate(body:string){if(body)this.draft.set((this.draft()?this.draft()+'\n':'')+body);}
 protected toggleRecipient(id:number){this.recipients.update(ids=>ids.includes(id)?ids.filter(v=>v!==id):[...ids,id]);}
 private sendStaffBroadcast(){const body=this.bulkBody().trim();if(!body||this.sending()||!this.contacts().some(this.canManage))return;
 if(!this.broadcastAttempt||this.broadcastAttempt.body!==body)this.broadcastAttempt={body,id:crypto.randomUUID()};
 this.sending.set(true);this.bulkStatus.set('جارٍ الإرسال…');
 this.http.post<{count:number}>(this.base+'/chat-broadcast',{body,request_id:this.broadcastAttempt.id}).pipe(takeUntilDestroyed(this.destroy)).subscribe({next:r=>{this.sending.set(false);this.bulkStatus.set('تم الإرسال إلى '+r.count+' مستلم.');this.bulkBody.set('');this.broadcastAttempt=null;this.search(true);},error:()=>{this.sending.set(false);this.bulkStatus.set('تعذر تأكيد الإرسال. أعد المحاولة.');}});
 }
 protected sendBulk(){if(this.allStaff()&&!this.guardianPortal()){this.sendStaffBroadcast();return;}const body=this.bulkBody().trim(),ids=this.recipients().filter(id=>this.bulkRecipients().some(c=>c.guardian_id===id));if(!body||!ids.length||this.sending()||(!this.guardianPortal()&&!this.contacts().some(this.canManage)))return;this.sending.set(true);this.bulkStatus.set('جارٍ الإرسال…');
 forkJoin(ids.map(id=>{let attempt=this.bulkAttempts.get(id);if(!attempt||attempt.body!==body){attempt={body,id:crypto.randomUUID()};this.bulkAttempts.set(id,attempt)}return this.http.post(this.threadUrl(id),{body,request_id:attempt.id}).pipe(map(()=>({id,ok:true})),catchError(()=>of({id,ok:false})))})).pipe(takeUntilDestroyed(this.destroy)).subscribe(results=>{const failed=results.filter(r=>!r.ok).map(r=>r.id);for(const r of results)if(r.ok)this.bulkAttempts.delete(r.id);this.recipients.set(failed);this.sending.set(false);this.bulkStatus.set('تم الإرسال إلى '+(results.length-failed.length)+' مستلم.'+(failed.length?' تعذر تأكيد '+failed.length+' رسائل؛ أعد المحاولة للمستلمين المتبقين.':''));if(!failed.length)this.bulkBody.set('');this.search(true)});
 }
 constructor(){this.route?.queryParamMap.pipe(takeUntilDestroyed(this.destroy)).subscribe(params=>{const peer=Number(params.get('peer'));this.pendingPeer=peer>0?peer:null;if(this.pendingPeer){const contact=this.contacts().find(c=>c.user_id===peer);if(contact){this.select(contact);this.pendingPeer=null;}}});this.search();interval(15000).pipe(takeUntilDestroyed(this.destroy)).subscribe(()=>{if(this.active()&&document.visibilityState==='visible'&&!this.loading()&&!this.sending()&&!this.contactsLoading()&&!this.messagesPending&&!this.contactsPending){this.search(true);if(this.selected())this.load(false,true)}})}
 protected search(quiet=false){const version=++this.contactVersion;if(!quiet)this.appliedQuery=this.query().trim();this.contactsPending++;if(!quiet){this.contactsLoading.set(true);this.error.set('');}this.http.get<{rows:Contact[];more:boolean}>(this.base+'/chat-contacts',{params:new HttpParams().set('q',this.guardianPortal()?'':this.appliedQuery)}).pipe(finalize(()=>this.contactsPending--),takeUntilDestroyed(this.destroy)).subscribe({next:r=>{if(version!==this.contactVersion)return;this.contacts.set(r.rows);r.rows.forEach(c=>this.avatars.load(c.user_id??null));if(this.error()==='تعذر تحميل المحادثات. حاول البحث مرة أخرى.')this.error.set('');if(this.pendingPeer){const contact=r.rows.find(c=>c.user_id===this.pendingPeer);this.pendingPeer=null;if(contact)this.select(contact);else this.peerRefused();}this.moreContacts.set(r.more);this.contactsLoading.set(false);if(!this.selected() && !this.selectionMade && r.rows.length===1&&(!this.guardianPortal()||!!r.rows[0].last_at))this.select(r.rows[0])},error:()=>{if(version!==this.contactVersion)return;this.contactsLoading.set(false);if(!quiet)this.error.set('تعذر تحميل المحادثات. حاول البحث مرة أخرى.')}})}
 protected select(contact:Contact){if(this.sending())return;this.selectionMade=true;const previous=this.selected();if(previous)this.drafts.set(previous.guardian_id,this.draft());this.selected.set(contact);this.draft.set(this.drafts.get(contact.guardian_id)??'');this.messages.set([]);this.more.set(false);this.load()}
 protected load(older=false,quiet=false){if(!this.active())return;const contact=this.selected();if(!contact)return;const version=++this.version;this.messagesPending++;if(!quiet){this.loading.set(true);this.error.set('');}let params=new HttpParams();if(older&&this.messages().length)params=params.set('before',this.messages()[0].message_id);
 this.http.get<{rows:Message[];more:boolean}>(this.threadUrl(contact.guardian_id),{params}).pipe(finalize(()=>this.messagesPending--),takeUntilDestroyed(this.destroy)).subscribe({next:r=>{if(version!==this.version)return;const list=this.messageList()?.nativeElement,height=list?.scrollHeight??0,top=list?.scrollTop??0,follow=!quiet||!list||height-top-list.clientHeight<80;const rows=[...r.rows].reverse();if(quiet){
 const merged=new Map(this.messages().map(message=>[message.message_id,message]));
 for(const message of rows)merged.set(message.message_id,message);
 const next=[...merged.values()].sort((a,b)=>a.message_id-b.message_id);
 if(JSON.stringify(next)!==JSON.stringify(this.messages()))this.messages.set(next);
 }else{this.messages.set(older?[...rows,...this.messages()]:rows);this.more.set(r.more);}this.loading.set(false);this.positionMessages(older,height,top,follow);if(this.active()&&!older&&rows.length&&document.visibilityState==='visible')this.http.post(this.threadUrl(contact.guardian_id)+'/read',{message_id:rows[rows.length-1].message_id}).pipe(takeUntilDestroyed(this.destroy)).subscribe({next:()=>this.contacts.update(cs=>cs.map(c=>c.guardian_id===contact.guardian_id?{...c,unread:0}:c)),error:()=>{}})},error:()=>{if(version!==this.version)return;this.loading.set(false);if(!quiet)this.error.set('تعذر تحميل الرسائل. اضغط تحديث الرسائل.')}})}
 protected send(){const contact=this.selected(),body=this.draft().trim();if(!contact?.can_send||!body||this.sending())return;if(!this.attempt||this.attempt.body!==body||this.attempt.guardian!==contact.guardian_id)this.attempt={guardian:contact.guardian_id,body,id:crypto.randomUUID()};this.sending.set(true);this.error.set('');this.http.post(this.threadUrl(contact.guardian_id),{body,request_id:this.attempt.id}).pipe(takeUntilDestroyed(this.destroy)).subscribe({next:()=>{this.sending.set(false);this.draft.set('');this.drafts.delete(contact.guardian_id);this.attempt=null;this.load();if(this.guardianPortal())this.search(true)},error:(failure:{status?:number})=>{this.sending.set(false);
  // 403 is the service saying this account is not yours to write to, and the
  // next attempt fails identically. "Saved here, try again" is true of a
  // dropped connection and a lie about a refusal, so the two are told apart.
  if(failure?.status===403)this.peerRefused();
  else this.error.set('تعذر تأكيد الإرسال. الرسالة محفوظة هنا ويمكن إعادة المحاولة.')}})}
}
