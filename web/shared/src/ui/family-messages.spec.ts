import {TestBed, fakeAsync, tick} from '@angular/core/testing';
import {provideHttpClient} from '@angular/common/http';
import {provideHttpClientTesting, HttpTestingController} from '@angular/common/http/testing';
import {FamilyMessages} from './family-messages';
import {UserAvatars} from './user-avatar';
import {HBH_CONFIG} from '../config/app-config';
import {ActivatedRoute, convertToParamMap} from '@angular/router';
import {of} from 'rxjs';

describe('Family message background refresh',()=>{
 const contact={guardian_id:1,name:'Family',can_send:true,can_manage:true,unread:0};
 const message=(id:number)=>({message_id:id,body:String(id),mine:false,created_at:'2026-09-14T10:00:00Z'});
 beforeEach(()=>{
  TestBed.configureTestingModule({imports:[FamilyMessages],providers:[provideHttpClient(),provideHttpClientTesting(),{provide:HBH_CONFIG,useValue:{apiBaseUrl:''}}]});
  TestBed.overrideComponent(FamilyMessages,{set:{template:'',imports:[],styles:[],styleUrl:undefined}});
  spyOnProperty(document,'visibilityState','get').and.returnValue('visible');
 });
 it('polls with older history present and preserves the draft and loaded messages',fakeAsync(()=>{
  const fixture=TestBed.createComponent(FamilyMessages), component=fixture.componentInstance as any, http=TestBed.inject(HttpTestingController);
  http.expectOne('/api/v1/chat-contacts?q=').flush({rows:[contact],more:false});
  http.expectOne('/api/v1/family-messages/1').flush({rows:[message(2)],more:true});
  http.expectOne('/api/v1/family-messages/1/read').flush({});
  component.draft.set('Unsent draft');component.query.set('unfinished search');
  tick(15000);
  expect(component.loading()).toBeFalse();expect(component.contactsLoading()).toBeFalse();
  http.expectOne('/api/v1/chat-contacts?q=').flush({rows:[contact],more:false});
  http.expectOne('/api/v1/family-messages/1').flush({rows:[message(3)],more:true});
  http.expectOne('/api/v1/family-messages/1/read').flush({});
  expect(component.messages().map((m:any)=>m.message_id)).toEqual([2,3]);
  expect(component.draft()).toBe('Unsent draft');expect(component.more()).toBeTrue();
  fixture.destroy();http.verify();
 }));
 it('keeps transient polling failures quiet and retries on the next interval',fakeAsync(()=>{
  const fixture=TestBed.createComponent(FamilyMessages), component=fixture.componentInstance as any, http=TestBed.inject(HttpTestingController);
  http.expectOne('/api/v1/chat-contacts?q=').flush({rows:[],more:false});
  tick(15000);
  http.expectOne('/api/v1/chat-contacts?q=').flush({}, {status:503,statusText:'Unavailable'});
  expect(component.error()).toBe('');
  tick(15000);
  http.expectOne('/api/v1/chat-contacts?q=').flush({rows:[],more:false});
  fixture.destroy();http.verify();
 }));

 it('sends and marks private account messages through the private endpoints',fakeAsync(()=>{
  const fixture=TestBed.createComponent(FamilyMessages),component=fixture.componentInstance as any,http=TestBed.inject(HttpTestingController);
  http.expectOne('/api/v1/chat-contacts?q=').flush({rows:[{...contact,guardian_id:-7,user_id:7,kind:'staff'}],more:false});
  http.expectOne('/api/v1/users/7/photo').flush(new Blob(['avatar'], {type:'image/jpeg'}));
  http.expectOne('/api/v1/direct-messages/7').flush({rows:[message(1)],more:false});
  http.expectOne('/api/v1/direct-messages/7/read').flush({});
  component.draft.set('test only');component.send();
  const sent=http.expectOne('/api/v1/direct-messages/7');expect(sent.request.method).toBe('POST');sent.flush({message_id:2});
  http.expectOne('/api/v1/direct-messages/7').flush({rows:[message(2),message(1)],more:false});
  http.expectOne('/api/v1/direct-messages/7/read').flush({});
  expect(component.draft()).toBe('');fixture.destroy();http.verify();
 }));

 it('broadcasts to all staff using one server request',fakeAsync(()=>{
  const fixture=TestBed.createComponent(FamilyMessages),component=fixture.componentInstance as any,http=TestBed.inject(HttpTestingController);
  http.expectOne('/api/v1/chat-contacts?q=').flush({rows:[contact,{...contact,guardian_id:2}],more:false});
  component.allStaff.set(true);component.bulkBody.set('test broadcast');component.sendBulk();
  const request=http.expectOne('/api/v1/chat-broadcast');expect(request.request.method).toBe('POST');expect(request.request.body.request_id).toBeTruthy();request.flush({count:3});
  http.expectOne('/api/v1/chat-contacts?q=').flush({rows:[],more:false});
  expect(component.bulkBody()).toBe('');expect(component.bulkStatus()).toContain('3');fixture.destroy();http.verify();
 }));
});


describe('Guardian recipient scope',()=>{
 const rows=[
  {guardian_id:-1,user_id:1,name:'Reception',role:'reception',kind:'staff',can_send:true,can_manage:false,unread:0},
  {guardian_id:-2,user_id:2,name:'Assigned A',role:'therapist',kind:'staff',can_send:true,can_manage:false,unread:0,last_at:'2026-09-14T10:00:00Z'},
  {guardian_id:-3,user_id:3,name:'Assigned B',role:'therapist',kind:'staff',can_send:true,can_manage:false,unread:0},
  {guardian_id:-4,user_id:4,name:'Manager',role:'manager',kind:'staff',can_send:true,can_manage:false,unread:0},
 ];
 beforeEach(()=>{
  TestBed.configureTestingModule({imports:[FamilyMessages],providers:[provideHttpClient(),provideHttpClientTesting(),{provide:HBH_CONFIG,useValue:{apiBaseUrl:''}}]});
  TestBed.overrideComponent(FamilyMessages,{set:{template:'',imports:[],styles:[],styleUrl:undefined}});
  spyOn(TestBed.inject(UserAvatars),'load');
 });
 it('shows history only, chooses roles and selects only assigned specialists',()=>{
  const f=TestBed.createComponent(FamilyMessages),c=f.componentInstance as any,h=TestBed.inject(HttpTestingController);
  f.componentRef.setInput('guardianPortal',true);
  h.expectOne('/api/v1/chat-contacts?q=').flush({rows:[...rows,{guardian_id:9,name:'legacy family',kind:'legacy',last_at:'2026-09-14',can_send:true}],more:false});
  expect(c.visibleContacts().map((r:any)=>r.user_id)).toEqual([2]);
  c.openRole('therapist');expect(c.bulkRecipients().map((r:any)=>r.user_id)).toEqual([2,3]);
  c.selectAllTherapists();expect(c.recipients()).toEqual([-2,-3]);
  c.openRole('reception');expect(c.recipients()).toEqual([]);expect(c.bulkRecipients().map((r:any)=>r.user_id)).toEqual([1]);
  c.openRole('manager');expect(c.bulkRecipients().map((r:any)=>r.user_id)).toEqual([4]);
  f.destroy();h.verify();
 });
 it('sends privately to selected specialists and retries only failed recipients with the same ID',()=>{
  const f=TestBed.createComponent(FamilyMessages),c=f.componentInstance as any,h=TestBed.inject(HttpTestingController);
  f.componentRef.setInput('guardianPortal',true);
  h.expectOne('/api/v1/chat-contacts?q=').flush({rows,more:false});
  c.openRole('therapist');c.selectAllTherapists();c.bulkBody.set('test message');c.sendBulk();
  const a=h.expectOne('/api/v1/direct-messages/2'),b=h.expectOne('/api/v1/direct-messages/3');
  const id=b.request.body.request_id;expect(a.request.body.request_id).not.toBe(id);
  a.flush({});b.flush({}, {status:503,statusText:'Unavailable'});
  h.expectOne('/api/v1/chat-contacts?q=').flush({rows,more:false});
  expect(c.recipients()).toEqual([-3]);c.sendBulk();
  const retry=h.expectOne('/api/v1/direct-messages/3');expect(retry.request.body.request_id).toBe(id);retry.flush({});
  h.expectOne('/api/v1/chat-contacts?q=').flush({rows,more:false});
  expect(c.bulkBody()).toBe('');f.destroy();h.verify();
 });
 it('keeps role recipients available while searching history and never broadcasts to all staff',()=>{
  const f=TestBed.createComponent(FamilyMessages),c=f.componentInstance as any,h=TestBed.inject(HttpTestingController);
  f.componentRef.setInput('guardianPortal',true);
  h.expectOne('/api/v1/chat-contacts?q=').flush({rows,more:false});
  c.query.set('absent');c.search();h.expectOne('/api/v1/chat-contacts?q=').flush({rows,more:false});
  expect(c.visibleContacts()).toEqual([]);c.openRole('therapist');expect(c.bulkRecipients().length).toBe(2);
  c.recipients.set([-1]);c.allStaff.set(true);c.bulkBody.set('test');c.sendBulk();
  h.expectNone('/api/v1/chat-broadcast');f.destroy();h.verify();
 });
});

/**
 * CH-05 in this screen: the refusal is SAID, and it is said the same way
 * for an account that is hidden and one that does not exist.
 *
 * The service answers a conversation you may not see with an empty list and
 * a send to it with 403, on purpose - a 404 would need an existence check,
 * and the existence check IS the leak: anybody trying user_id numbers would
 * learn which are real, which are in their centre, and which are parents.
 *
 * That silence is right in the service and wrong on the screen. A link
 * carrying ?peer=<someone else> did nothing at all here: no conversation
 * opened, no sentence appeared, and the person was left looking at a contact
 * list wondering whether the link was broken. And a send that came back 403
 * read "could not confirm - you may retry", which is advice that cannot
 * work: the second attempt is refused for exactly the same reason as the
 * first. Same family as HBH-050.
 */
describe('A conversation you may not have (CH-05)',()=>{
 const contact={guardian_id:-7,user_id:7,kind:'staff',name:'Colleague',can_send:true,can_manage:false,unread:0};
 const withPeer=(peer:string)=>{
  TestBed.configureTestingModule({imports:[FamilyMessages],providers:[
   provideHttpClient(),provideHttpClientTesting(),{provide:HBH_CONFIG,useValue:{apiBaseUrl:''}},
   {provide:ActivatedRoute,useValue:{queryParamMap:of(convertToParamMap({peer}))}},
  ]});
  TestBed.overrideComponent(FamilyMessages,{set:{template:'',imports:[],styles:[],styleUrl:undefined}});
 };
 beforeEach(()=>{TestBed.resetTestingModule();spyOnProperty(document,'visibilityState','get').and.returnValue('visible');});

 it('says why a linked conversation did not open, instead of ignoring the link',()=>{
  withPeer('999');
  const f=TestBed.createComponent(FamilyMessages),c=f.componentInstance as any,h=TestBed.inject(HttpTestingController);
  h.expectOne('/api/v1/chat-contacts?q=').flush({rows:[contact],more:false});
  h.expectOne('/api/v1/users/7/photo').flush(new Blob(['avatar'],{type:'image/jpeg'}));
  expect(c.selected()).toBeNull();
  expect(c.error()).toBe('chat.cannotMessage');
  // And nothing was asked about 999. A request to its thread would be the
  // existence check the service refuses to perform.
  h.expectNone('/api/v1/direct-messages/999');
  f.destroy();h.verify();
 });

 /**
  * The acceptance half. A refusal test with no acceptance beside it proves
  * the door is shut, not that it opens - and a `peer` that stopped working
  * for everybody would keep the test above green.
  */
 it('still opens the conversation when the link names one you do have',()=>{
  withPeer('7');
  const f=TestBed.createComponent(FamilyMessages),c=f.componentInstance as any,h=TestBed.inject(HttpTestingController);
  h.expectOne('/api/v1/chat-contacts?q=').flush({rows:[contact],more:false});
  h.expectOne('/api/v1/users/7/photo').flush(new Blob(['avatar'],{type:'image/jpeg'}));
  h.expectOne('/api/v1/direct-messages/7').flush({rows:[],more:false});
  expect(c.selected()?.user_id).toBe(7);
  expect(c.error()).toBe('');
  f.destroy();h.verify();
 });

 it('does not offer a retry for a send the service refused',()=>{
  withPeer('7');
  const f=TestBed.createComponent(FamilyMessages),c=f.componentInstance as any,h=TestBed.inject(HttpTestingController);
  h.expectOne('/api/v1/chat-contacts?q=').flush({rows:[contact],more:false});
  h.expectOne('/api/v1/users/7/photo').flush(new Blob(['avatar'],{type:'image/jpeg'}));
  h.expectOne('/api/v1/direct-messages/7').flush({rows:[],more:false});
  c.draft.set('test only');c.send();
  h.expectOne('/api/v1/direct-messages/7').flush({},{status:403,statusText:'Forbidden'});
  expect(c.error()).toBe('chat.cannotMessage');
  // The draft is NOT thrown away. The sentence says this account cannot be
  // written to; the words the person typed are still theirs.
  expect(c.draft()).toBe('test only');
  f.destroy();h.verify();
 });

 /**
  * A transient failure is a different thing and keeps its own sentence:
  * "could not confirm, it is saved here, try again" is true of a dropped
  * connection and false of a refusal.
  */
 it('keeps the retry sentence for a failure that a retry could fix',()=>{
  withPeer('7');
  const f=TestBed.createComponent(FamilyMessages),c=f.componentInstance as any,h=TestBed.inject(HttpTestingController);
  h.expectOne('/api/v1/chat-contacts?q=').flush({rows:[contact],more:false});
  h.expectOne('/api/v1/users/7/photo').flush(new Blob(['avatar'],{type:'image/jpeg'}));
  h.expectOne('/api/v1/direct-messages/7').flush({rows:[],more:false});
  c.draft.set('test only');c.send();
  h.expectOne('/api/v1/direct-messages/7').flush({},{status:503,statusText:'Unavailable'});
  expect(c.error()).not.toBe('chat.cannotMessage');
  expect(c.error()).toBeTruthy();
  f.destroy();h.verify();
 });
});
