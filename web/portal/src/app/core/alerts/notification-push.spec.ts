import { TestBed, fakeAsync, tick } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { NavigationEnd, Router, provideRouter } from '@angular/router';
import { of, Subject, throwError } from 'rxjs';
import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { TabBadge } from '@hbh/shared/a11y/tab-badge';
import { PortalApi } from '../api/portal-api';
import { ChildContextService } from '../auth/child-context.service';
import { NotificationFeed, PortalNotification } from '../models/portal.models';
import { NotificationPush } from './notification-push';
import { NotificationBadge } from './notification-badge';

describe('Guardian notification push',()=>{
  const item=(id:number,kind='CHAT_MESSAGE'):PortalNotification=>({id:String(id),kind,title:`Notice ${id}`,body:'New update',childId:null,childName:null,createdAt:'2026-09-14T12:00:00Z',read:false,target:['/requests'],targetQuery:{tab:'messages',peer:'8'}});
  let feed:NotificationFeed;
  let notifications:jasmine.Spy,read:jasmine.Spy,navigate:jasmine.Spy,select:jasmine.Spy,events:Subject<NavigationEnd>,family:Subject<any>,tab:jasmine.Spy;
  beforeEach(()=>{
    feed={rows:[item(1)],unread:1,total:1};events=new Subject();family=new Subject();
    notifications=jasmine.createSpy().and.callFake(()=>of(feed));read=jasmine.createSpy().and.returnValue(of(undefined));
    navigate=jasmine.createSpy().and.returnValue(Promise.resolve(true));select=jasmine.createSpy();tab=jasmine.createSpy();
    TestBed.configureTestingModule({providers:[provideHttpClient(),provideHttpClientTesting(),provideRouter([]),
      {provide:HBH_CONFIG,useValue:DEFAULT_HBH_CONFIG},{provide:TabBadge,useValue:{setCount:tab}},
      {provide:ChildContextService,useValue:{select}},{provide:PortalApi,useValue:{notifications,markNotificationRead:read,family:()=>family}},
    ]});
    navigate=spyOn(TestBed.inject(Router),'navigate').and.returnValue(Promise.resolve(true));
  });
  it('baselines old items and announces every new kind once without changing read state on dismissal',fakeAsync(()=>{
    const f=TestBed.createComponent(NotificationPush),vm=f.componentInstance as any;
    expect(vm.pending()).toEqual([]);
    feed={rows:[item(4,'INVOICE_ISSUED'),item(3,'REQUEST_DECIDED'),item(2),item(1)],unread:4,total:4};
    tick(15000);expect(vm.pending().length).toBe(3);expect(tab).toHaveBeenCalledWith(3);
    f.detectChanges();expect(f.nativeElement.querySelectorAll('.portal-push__item').length).toBe(3);
    expect(f.nativeElement.querySelector('aside').textContent).toContain('Notice 4');
    expect(TestBed.inject(NotificationBadge).unread()).toBe(4);
    vm.dismiss();tick(15000);expect(vm.pending()).toEqual([]);expect(read).not.toHaveBeenCalled();
    f.destroy();const calls=notifications.calls.count();tick(30000);expect(notifications.calls.count()).toBe(calls);
    expect(TestBed.inject(NotificationBadge).unread()).toBeNull();
  }));
  it('keeps notifications after a transient fetch failure and handles more than one page',fakeAsync(()=>{
    const f=TestBed.createComponent(NotificationPush),vm=f.componentInstance as any;
    notifications.and.returnValue(throwError(()=>new Error('offline')));tick(15000);expect(TestBed.inject(NotificationBadge).unread()).toBe(1);
    notifications.and.callFake((_limit:number,offset=0)=>of(offset?{rows:[item(2),item(1)],unread:102,total:102}:{rows:Array.from({length:100},(_,n)=>item(102-n)),unread:102,total:102}));
    tick(15000);expect(vm.pending().length).toBe(101);expect(notifications).toHaveBeenCalledWith(100,100);f.destroy();
  }));
  it('opens the message peer and marks read only after navigation succeeds',fakeAsync(()=>{
    const f=TestBed.createComponent(NotificationPush),vm=f.componentInstance as any;
    vm.open(item(2));tick();expect(navigate).toHaveBeenCalledWith(['/requests'],{queryParams:{tab:'messages',peer:'8'}});expect(read).toHaveBeenCalledWith('2');f.destroy();
  }));
  it('removes only the opened notification and orders popups by creation time',fakeAsync(()=>{
    const f=TestBed.createComponent(NotificationPush),vm=f.componentInstance as any;
    feed={rows:[{...item(3),createdAt:'2026-09-13T12:00:00Z'},{...item(2),createdAt:'2026-09-14T12:00:00Z'},item(1)],unread:3,total:3};
    tick(15000);expect(vm.pending().map((r:any)=>r.id)).toEqual(['2','3']);
    vm.open(vm.pending()[0]);tick();expect(vm.pending().map((r:any)=>r.id)).toEqual(['3']);f.destroy();
  }));
  it('refuses to open a sibling when the notification child is no longer accessible',fakeAsync(()=>{
    const f=TestBed.createComponent(NotificationPush),vm=f.componentInstance as any;
    vm.open({...item(2),childId:'8'});family.next({children:[{id:'9'}]});tick();
    expect(navigate).not.toHaveBeenCalled();expect(select).not.toHaveBeenCalled();expect(read).not.toHaveBeenCalled();expect(vm.error()).toBe('notifications.childUnavailable');f.destroy();
  }));
  it('does not overlap polls or finish a request after logout destroys the watcher',fakeAsync(()=>{
    const response=new Subject<NotificationFeed>();notifications.and.returnValue(response);
    const f=TestBed.createComponent(NotificationPush);tick(30000);expect(notifications).toHaveBeenCalledTimes(1);
    f.destroy();response.next({rows:[item(5)],unread:5,total:1});expect(TestBed.inject(NotificationBadge).unread()).toBeNull();
  }));
});
