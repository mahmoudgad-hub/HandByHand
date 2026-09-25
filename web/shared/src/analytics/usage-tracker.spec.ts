import { provideHttpClient, withInterceptors, HttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { ActivatedRouteSnapshot, NavigationEnd, Router, convertToParamMap } from '@angular/router';
import { Subject } from 'rxjs';
import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '../config/app-config';
import { UsageTelemetry, usageFeature, usageInterceptor } from './usage-tracker';

describe('Product usage telemetry',()=>{
  let http: HttpTestingController;
  const root=(title:string,query:Record<string,string>={})=>({data:{titleKey:title},queryParamMap:convertToParamMap(query),firstChild:null}) as unknown as ActivatedRouteSnapshot;
  function setup() {
    const events=new Subject<NavigationEnd>();
    const router={events,navigated:true,routerState:{snapshot:{root:root('nav.home')}}};
    TestBed.configureTestingModule({providers:[provideHttpClient(withInterceptors([usageInterceptor])),provideHttpClientTesting(),
      {provide:Router,useValue:router},{provide:HBH_CONFIG,useValue:{...DEFAULT_HBH_CONFIG,useFixtures:false}}]});
    http=TestBed.inject(HttpTestingController);return {router,events,usage:TestBed.inject(UsageTelemetry)};
  }
  afterEach(()=>http?.verify());
  it('records actual navigation once and only sends static feature metadata',()=>{
    const {usage,router,events}=setup();usage.configure('portal','test-token');
    const visit=http.expectOne('/api/v1/usage-events');expect(visit.request.body).toEqual({app:'portal',feature:'portal.nav.home',kind:'page',action:'view'});visit.flush(null);
    events.next(new NavigationEnd(1,'/home?child=42','/home?child=42'));http.expectNone('/api/v1/usage-events');
    router.routerState.snapshot.root=root('requests.title',{tab:'messages',name:'private'});
    events.next(new NavigationEnd(2,'/requests','/requests'));
    const next=http.expectOne('/api/v1/usage-events');expect(next.request.body.feature).toBe('portal.requests.title.messages');expect(JSON.stringify(next.request.body)).not.toContain('private');next.flush(null);
  });
  it('counts successful mutations, excludes polling and failures, and preserves the initiating feature',()=>{
    const {usage,router}=setup();usage.configure('portal','token');http.expectOne('/api/v1/usage-events').flush(null);
    const client=TestBed.inject(HttpClient);
    client.get('/api/v1/notifications').subscribe();http.expectOne('/api/v1/notifications').flush([]);http.expectNone('/api/v1/usage-events');
    client.post('/api/v1/requests',{}).subscribe();const action=http.expectOne('/api/v1/requests');
    router.routerState.snapshot.root=root('nav.profile');action.flush({});
    const logged=http.expectOne('/api/v1/usage-events');expect(logged.request.body.feature).toBe('portal.nav.home');logged.flush(null);
    client.post('/api/v1/requests',{}).subscribe({error:()=>{}});http.expectOne('/api/v1/requests').flush(null,{status:500,statusText:'Failed'});http.expectNone('/api/v1/usage-events');
  });
  it('never attributes an old in-flight action to the next signed-in user',()=>{
    const {usage}=setup();usage.configure('portal','old-token');http.expectOne('/api/v1/usage-events').flush(null);
    const callback=usage.action('POST');usage.configure('portal',null);callback?.();http.expectNone('/api/v1/usage-events');
    expect(usageFeature(root('login.title'),'portal')).toBe('');
  });
});
