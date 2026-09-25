import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { AnalyticsSummary, OpsAnalytics, analyticsToday, validAnalyticsDates } from './ops-analytics';

describe('Operations analytics', () => {
  let http: HttpTestingController;
  const summary: AnalyticsSummary = {
    time_zone:'Africa/Cairo',tracking_since:null,requests:4,successes:3,errors:1,p50_ms:20,p95_ms:120,
    registrations:2,applications:3,first_logins:1,staff_logins:2,staff_active:2,staff_pages:1,portal_users:1,
    portal_features:[{feature:'portal.nav.home',users:1,visits:3,actions:2}],
    pages:[{feature:'ops.nav.dashboard',users:2,visits:8}],performance:[{method:'GET',route:'/api/v1/me',calls:4,p95_ms:120}],
  };
  function mount() {
    TestBed.configureTestingModule({providers:[provideHttpClient(),provideHttpClientTesting(),{provide:HBH_CONFIG,useValue:DEFAULT_HBH_CONFIG}]});
    http=TestBed.inject(HttpTestingController);
    const fixture=TestBed.createComponent(OpsAnalytics);fixture.detectChanges();
    http.expectOne(r=>r.url.endsWith('/ops/analytics')&&!r.params.has('kind')).flush(summary);
    fixture.detectChanges();return fixture;
  }
  afterEach(()=>http?.verify());
  it('uses centre calendar day across midnight, validates range, and handles empty ratios',()=>{
    expect(analyticsToday('Africa/Cairo',new Date('2026-09-14T22:30:00Z'))).toBe('2026-09-15');
    expect(validAnalyticsDates('2026-09-15','2026-09-14')).toBeFalse();
    expect(validAnalyticsDates('2025-01-01','2026-01-02')).toBeFalse();
    expect(validAnalyticsDates('2026-02-30','2026-03-01')).toBeFalse();
    const f=mount();expect((f.componentInstance as any).percentage(0,0)).toBe('—');
  });
  it('opens chart details with the applied period, paginates on the server, and closes on dismissal',()=>{
    const f=mount(),vm=f.componentInstance as any;
    const original={...vm.applied()};vm.from='2026-01-01';
    (f.nativeElement.querySelector('.analytics-card') as HTMLButtonElement).click();f.detectChanges();
    const request=http.expectOne(r=>r.params.get('kind')==='successes');
    expect(request.request.params.get('from')).toBe(original.from);
    request.flush({total:51,rows:[{id:'1',at:'2026-09-14T10:00:00Z',name:'Test staff',username:'staff',feature:'/api/v1/me',action:'GET',visits:1,status:200,duration_ms:20}]});
    f.detectChanges();
    expect(f.nativeElement.querySelector('dialog').textContent).toContain('Test staff');
    vm.changePage(1);
    http.expectOne(r=>r.params.get('kind')==='successes'&&r.params.get('offset')==='50').flush({total:51,rows:[]});
    f.detectChanges();f.nativeElement.querySelector('dialog').dispatchEvent(new Event('cancel',{cancelable:true}));f.detectChanges();
    expect(f.nativeElement.querySelector('dialog')).toBeNull();
  });
  it('cancels stale summary and detail requests when changing period or closing',()=>{
    const f=mount(),vm=f.componentInstance as any;
    vm.from=vm.to='2026-09-01';vm.load();const old=http.expectOne(r=>r.params.get('from')==='2026-09-01');
    vm.from=vm.to='2026-09-02';vm.load();expect(old.cancelled).toBeTrue();
    http.expectOne(r=>r.params.get('from')==='2026-09-02').flush(summary);
    vm.open('portal_features','Feature','portal.nav.home');
    const detail=http.expectOne(r=>r.params.get('feature')==='portal.nav.home');vm.close();expect(detail.cancelled).toBeTrue();
  });
});
