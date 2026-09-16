import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, convertToParamMap, provideRouter } from '@angular/router';
import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { GOALS_SPEC } from '../../core/resource/resource-spec';
import { ResourceScreen } from './resource-screen';

describe('Named resource references', () => {
  let http: HttpTestingController;
  function mount(prefill?: Record<string, string>) {
    TestBed.configureTestingModule({ providers: [
      provideHttpClient(), provideHttpClientTesting(), provideRouter([]),
      { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, apiBaseUrl: '' } },
      { provide: OpsAuthService, useValue: { can: () => true } },
      { provide: ActivatedRoute, useValue: { snapshot: {
        queryParamMap: convertToParamMap({}), data: { specs: [GOALS_SPEC], embeddedResource: {
          spec: GOALS_SPEC, row: null, request: { source: 'CHILD_PROFILE', prefill }, onClose: () => {},
        } },
      } } },
    ] });
    http = TestBed.inject(HttpTestingController);
    const fixture = TestBed.createComponent(ResourceScreen);
    fixture.detectChanges();
    return fixture;
  }
  afterEach(() => http.verify());

  it('includes later-page names and sends the selected identifier unchanged', () => {
    const fixture = mount();
    http.expectOne(r => r.url === '/api/v1/plans').flush({
      plans: [{ plan_id: 1, title_ar: 'First' }], total: 2, limit: 1, offset: 0,
    });
    http.expectOne(r => r.url === '/api/v1/plans' && r.params.get('page') === '2').flush({
      plans: [{ plan_id: 3, title_ar: 'Speech plan' }], total: 2, limit: 1, offset: 1,
    });
    fixture.detectChanges();
    const select = fixture.nativeElement.querySelector('#f-plan_id') as HTMLSelectElement;
    expect(select.tagName).toBe('SELECT');
    expect(select.textContent).toContain('Speech plan');
    select.value = '3'; select.dispatchEvent(new Event('change'));
    const title = fixture.nativeElement.querySelector('#f-title_ar') as HTMLInputElement;
    title.value = 'New goal'; title.dispatchEvent(new Event('input'));
    fixture.nativeElement.querySelector('form').dispatchEvent(new Event('submit'));
    const write = http.expectOne(r => r.method === 'POST' && r.url === '/api/v1/goals');
    expect(write.request.body.plan_id).toBe('3');
    expect(write.request.body.title_ar).toBe('New goal');
    write.flush({ goal_id: 9 });
  });

  it('preserves and locks the originating plan when the names fail to load', () => {
    const fixture = mount({ plan_id: '3' });
    http.expectOne(r => r.url === '/api/v1/plans').flush({}, { status: 500, statusText: 'Unavailable' });
    fixture.detectChanges();
    const select = fixture.nativeElement.querySelector('#f-plan_id') as HTMLSelectElement;
    expect(select.disabled).toBeTrue();
    expect(select.value).toBe('3');
    expect(fixture.nativeElement.textContent).toContain('resource.referenceFailed');
    http.expectNone(r => r.method !== 'GET');
  });
});
