import {of} from 'rxjs';
import {TASK_CATALOG, TaskContext} from './task-catalog';

describe('Conversation tasks',()=>{
 it('includes only unread private conversations with personal assignment and the correct link',()=>{
  const chatContacts=jasmine.createSpy().and.returnValue(of([
   {user_id:7,name:'Colleague',unread:2,last_message:'Hello',last_at:'2026-09-14T12:00:00Z'},
   {user_id:8,name:'Read thread',unread:0},
   {guardian_id:4,name:'Legacy thread',unread:1},
  ]));
  const source=TASK_CATALOG.find(source=>source.type==='CHAT_READ')!;
  expect(source.permission).toBe('PORTAL.VIEW');
  source.fetch({crud:{chatContacts}} as unknown as TaskContext).subscribe(tasks=>{
   expect(tasks.length).toBe(1);expect(tasks[0].id).toBe('CHAT_READ:7');
   expect(tasks[0].assignedUser).toBe('me');
   expect(tasks[0].primaryAction.link).toEqual(['/communications']);
   expect(tasks[0].primaryAction.query).toEqual({peer:'7'});
  });
 });
 it('removes a conversation task once its messages have been read',()=>{
  const source=TASK_CATALOG.find(source=>source.type==='CHAT_READ')!;
  source.fetch({crud:{chatContacts:()=>of([{user_id:7,unread:0}])}} as unknown as TaskContext).subscribe(tasks=>expect(tasks).toEqual([]));
 });
 it('keeps enrolment and parent requests assigned to their responsible permissions',()=>{
  expect(TASK_CATALOG.find(s=>s.type==='ENROLMENT_TRIAGE')?.permission).toBe('ENROLMENT.MANAGE');
  expect(TASK_CATALOG.find(s=>s.type==='REQUEST_DECIDE')?.permission).toBe('REQUEST.MANAGE');
 });
});
