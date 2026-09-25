import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting, HttpTestingController } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { FormatService } from '@hbh/shared/format/format.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { DayApi } from './day-api';
import { ENROLMENTS_SPEC } from './day-spec';
import { ActivatedRoute, convertToParamMap, provideRouter } from '@angular/router';
import { OpsAuthService } from '../auth/ops-auth.service';
import { DayScreen } from '../../features/day/day-screen';

describe('Enrolment assessment scheduling', () => {
  beforeEach(() => TestBed.configureTestingModule({ providers: [
    provideHttpClient(), provideHttpClientTesting(),
    { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, apiBaseUrl: '', timeZone: 'Africa/Cairo' } },
  ] }));
  afterEach(() => TestBed.inject(HttpTestingController).verify());

  it('sends the agreed centre time as an explicit UTC instant', () => {
    const action = ENROLMENTS_SPEC.actions.find(action => action.key === 'status')!;
    action.run(TestBed.inject(DayApi), { application_id: 116, status: 'CONTACTED' },
      { status: 'ASSESSMENT_BOOKED', assessment_at: '2026-01-15T11:30', note_ar: '' },
      { format: TestBed.inject(FormatService), i18n: TestBed.inject(I18nService) }).subscribe();
    const request = TestBed.inject(HttpTestingController).expectOne('/api/v1/enrolments/116');
    expect(request.request.body).toEqual({ status: 'ASSESSMENT_BOOKED', note_ar: '', assessment_at: '2026-01-15T09:30:00.000Z' });
    request.flush(null);
  });

  it('does not send a stale assessment field with a rejection', () => {
    const action = ENROLMENTS_SPEC.actions.find(action => action.key === 'status')!;
    action.run(TestBed.inject(DayApi), { application_id: 116, status: 'CONTACTED' },
      { status: 'REJECTED', assessment_at: '2026-01-15T11:30', note_ar: 'سبب' },
      { format: TestBed.inject(FormatService), i18n: TestBed.inject(I18nService) }).subscribe();
    const request = TestBed.inject(HttpTestingController).expectOne('/api/v1/enrolments/116');
    expect(request.request.body.assessment_at).toBeUndefined();
    request.flush(null);
  });
});

describe('Assessment date form', () => {
  it('requires a chosen date, then submits summer centre time in UTC', () => {
    const action = ENROLMENTS_SPEC.actions.find(a => a.key === 'status')!;
    TestBed.configureTestingModule({ providers: [
      provideRouter([]), provideHttpClient(), provideHttpClientTesting(),
      { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, apiBaseUrl: '', timeZone: 'Africa/Cairo' } },
      { provide: OpsAuthService, useValue: { can: () => true, me: () => ({}) } },
      { provide: ActivatedRoute, useValue: { snapshot: { queryParamMap: convertToParamMap({}), data: {
        spec: ENROLMENTS_SPEC, embedded: { spec: ENROLMENTS_SPEC, action,
          row: { application_id: 116, status: 'CONTACTED' },
          request: { prefill: { status: 'ASSESSMENT_BOOKED' } }, onClose: () => {},
        },
      } } } },
    ] });
    const fixture = TestBed.createComponent(DayScreen);
    fixture.detectChanges();
    const http = TestBed.inject(HttpTestingController);
    const form = fixture.nativeElement.querySelector('form') as HTMLFormElement;
    form.dispatchEvent(new Event('submit'));
    fixture.detectChanges();
    http.expectNone(r => r.method === 'PATCH');
    expect(fixture.nativeElement.textContent).toContain('error.field.REQUIRED');
    const date = fixture.nativeElement.querySelector('#d-assessment_at') as HTMLInputElement;
    date.value = '2026-09-15T10:00';
    date.dispatchEvent(new Event('input'));
    fixture.detectChanges();
    form.dispatchEvent(new Event('submit'));
    const request = http.expectOne('/api/v1/enrolments/116');
    expect(request.request.body.assessment_at).toBe('2026-09-15T07:00:00.000Z');
    request.flush(null);
    http.verify();
  });
});
