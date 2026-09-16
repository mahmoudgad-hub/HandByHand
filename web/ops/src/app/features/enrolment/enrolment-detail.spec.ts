import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ActivatedRoute, Router, convertToParamMap, provideRouter } from '@angular/router';
import { of } from 'rxjs';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { ActionDialogService } from '../../core/ops/action-dialog.service';
import { ActionOutcome, ActionRequest } from '../../core/ops/action-request';
import { EnrolmentDetail } from './enrolment-detail';

/**
 * The application page: reads one row, says where it stands, offers the
 * next step, and opens the list's dialog on request - and never runs one.
 */
describe('EnrolmentDetail', () => {
  let http: HttpTestingController;
  let opened: ActionRequest[];
  let outcome: ActionOutcome;
  let held: Set<string>;
  let query: Record<string, string>;
  let navigate: jasmine.Spy;

  const ROW = {
    application_id: 116, application_no: 'ENR-2026-00116', status: 'NEW',
    parent_name_ar: 'منى سعيد', parent_mobile: '+201155667788', relationship_code: 'MOTHER',
    child_name_ar: 'عمر خالد', child_birth_date: '2021-03-01', child_gender: 'M',
    submitted_at: '2026-09-03T08:26:00Z', source_code: 'WEB', sibling_applications: 0,
  };

  function mount(): ComponentFixture<EnrolmentDetail> {
    TestBed.configureTestingModule({
      imports: [EnrolmentDetail],
      providers: [
        provideRouter([]), provideHttpClient(), provideHttpClientTesting(),
        { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, apiBaseUrl: '' } },
        { provide: OpsAuthService, useValue: { can: (p: string) => held.has(p), me: () => ({}) } },
        {
          provide: ActionDialogService, useValue: {
            open: (request: ActionRequest) => { opened.push(request); return of(outcome); },
            canOffer: (_e: string, actionType: string, row: Record<string, unknown>) =>
              held.has('ENROLMENT.MANAGE') && (actionType === 'status' ? row['status'] !== 'ENROLLED' : row['status'] !== 'NEW'),
          },
        },
        {
          provide: ActivatedRoute, useValue: {
            snapshot: { paramMap: convertToParamMap({ applicationId: '116' }), queryParamMap: convertToParamMap(query) },
          },
        },
      ],
    });
    const router = TestBed.inject(Router);
    navigate = spyOn(router, 'navigate').and.resolveTo(true);
    spyOn(router, 'navigateByUrl').and.resolveTo(true);
    http = TestBed.inject(HttpTestingController);
    const fixture = TestBed.createComponent(EnrolmentDetail);
    fixture.detectChanges();
    return fixture;
  }

  beforeEach(() => {
    opened = [];
    outcome = 'CANCELLED';
    held = new Set(['ENROLMENT.MANAGE']);
    query = {};
  });

  afterEach(() => http.verify());

  it('opens assessment scheduling after contact and leaves cancellation without writes or reloads', () => {
    const fixture = mount();
    http.expectOne('/api/v1/enrolments/116').flush({ ...ROW, status: 'CONTACTED' });
    fixture.detectChanges();
    fixture.nativeElement.querySelector('.enr__next button.hbh-btn--primary').click();
    expect(opened.length).toBe(1);
    expect(opened[0].actionType).toBe('status');
    expect(opened[0].prefill).toEqual({ status: 'ASSESSMENT_BOOKED' });
    http.expectNone(() => true);
  });

  it('links to the returned beneficiary after successful conversion', () => {
    held.add('CHILD.VIEW_ALL');
    outcome = 'DONE';
    const fixture = mount();
    http.expectOne('/api/v1/enrolments/116').flush({ ...ROW, status: 'ASSESSMENT_BOOKED' });
    fixture.detectChanges();
    fixture.nativeElement.querySelector('.enr__next button.hbh-btn--primary').click();
    http.expectOne('/api/v1/enrolments/116').flush({
      ...ROW, status: 'ENROLLED', converted_child_id: 651, converted_guardian_id: 9,
    });
    http.expectOne('/api/v1/children/651/appointments').flush({ appointments: [] });
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('.enr__next a[href="/children/651"]')).not.toBeNull();
    expect(fixture.nativeElement.querySelector('a[href="/guardians/9"]')).not.toBeNull();
  });

  it('does not present an enrolled request as proof of a booked assessment', () => {
    query = { tab: 'assessment' };
    const fixture = mount();
    http.expectOne('/api/v1/enrolments/116').flush({ ...ROW, status: 'ENROLLED' });
    fixture.detectChanges();
    expect(fixture.nativeElement.textContent).toContain('enrolment.assessmentNote');
    expect(fixture.nativeElement.textContent).not.toContain('enrolment.assessmentNoteBooked');
  });

  it('reads the application by the id in the path and shows its number and status', () => {
    const fixture = mount();
    http.expectOne('/api/v1/enrolments/116').flush(ROW);
    fixture.detectChanges();
    const text = (fixture.nativeElement as HTMLElement).textContent ?? '';
    expect(text).toContain('ENR-2026-00116');
    expect(text).toContain('عمر خالد');
    expect(text).toContain('status.enrolment.NEW');
  });

  it('says the next step for NEW is to record the contact, and its button opens the status dialog pre-selected', () => {
    const fixture = mount();
    http.expectOne('/api/v1/enrolments/116').flush(ROW);
    fixture.detectChanges();
    const button = (fixture.nativeElement as HTMLElement)
      .querySelector('.enr__next button.hbh-btn--primary') as HTMLButtonElement;
    expect(button).not.toBeNull();
    expect(button.textContent).toContain('enrolment.next.NEW.cta');
    button.click();
    expect(opened.length).toBe(1);
    expect(opened[0].actionType).toBe('status');
    expect(opened[0].prefill).toEqual({ status: 'CONTACTED' });
    expect(opened[0].source).toBe('ENROLMENT_DETAIL');
  });

  it('offers no primary button to an account without the permission, and says why', () => {
    held.clear();
    const fixture = mount();
    http.expectOne('/api/v1/enrolments/116').flush(ROW);
    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.enr__next button.hbh-btn--primary')).toBeNull();
    expect(el.textContent).toContain('enrolment.nextNoPermission');
  });

  it('shows "not found" on a 404 and a retry on a failure', () => {
    const fixture = mount();
    http.expectOne('/api/v1/enrolments/116').flush({}, { status: 404, statusText: 'Not Found' });
    fixture.detectChanges();
    expect((fixture.nativeElement as HTMLElement).textContent).toContain('enrolment.notFound');
  });

  it('shows the refusal page on a 403 rather than an empty form', () => {
    const fixture = mount();
    http.expectOne('/api/v1/enrolments/116').flush({}, { status: 403, statusText: 'Forbidden' });
    fixture.detectChanges();
    expect((fixture.nativeElement as HTMLElement).textContent).toContain('denied.title');
  });

  it('opens the dialog named by ?action= when it is legal, and clears the parameter first', () => {
    query = { action: 'contact' };
    const fixture = mount();
    http.expectOne('/api/v1/enrolments/116').flush(ROW);
    fixture.detectChanges();
    expect(opened.length).toBe(1);
    expect(opened[0].source).toBe('DEEP_LINK');
    expect(opened[0].prefill).toEqual({ status: 'CONTACTED' });
    const cleared = navigate.calls.allArgs().some(([, extras]) =>
      (extras as { queryParams?: Record<string, unknown> })?.queryParams?.['action'] === null);
    expect(cleared).withContext('?action= cleared from the address').toBeTrue();
  });

  it('does not open a deep-linked dialog the status does not allow, and says so', () => {
    query = { action: 'convert' };
    const fixture = mount();
    http.expectOne('/api/v1/enrolments/116').flush(ROW);
    fixture.detectChanges();
    expect(opened.length).toBe(0);
    expect((fixture.nativeElement as HTMLElement).textContent).toContain('enrolment.notice.NOT_APPLICABLE');
  });

  it('re-reads the row after a dialog reports DONE, and not after a cancel', () => {
    outcome = 'DONE';
    const fixture = mount();
    http.expectOne('/api/v1/enrolments/116').flush(ROW);
    fixture.detectChanges();
    (fixture.nativeElement as HTMLElement).querySelector<HTMLButtonElement>('.enr__next button.hbh-btn--primary')!.click();
    http.expectOne('/api/v1/enrolments/116').flush({ ...ROW, status: 'CONTACTED' });
    fixture.detectChanges();
    expect((fixture.nativeElement as HTMLElement).textContent).toContain('status.enrolment.CONTACTED');
  });

  it('goes back to the filtered list it came from', () => {
    query = { returnUrl: '/enrolments?status=NEW' };
    const fixture = mount();
    http.expectOne('/api/v1/enrolments/116').flush(ROW);
    fixture.detectChanges();
    (fixture.nativeElement as HTMLElement).querySelector<HTMLButtonElement>('.enr__crumbs button')!.click();
    expect(TestBed.inject(Router).navigateByUrl).toHaveBeenCalledWith('/enrolments?status=NEW');
  });

  it('ignores a return address outside the app', () => {
    query = { returnUrl: 'https://evil.example/' };
    const fixture = mount();
    http.expectOne('/api/v1/enrolments/116').flush(ROW);
    fixture.detectChanges();
    (fixture.nativeElement as HTMLElement).querySelector<HTMLButtonElement>('.enr__crumbs button')!.click();
    expect(TestBed.inject(Router).navigateByUrl).not.toHaveBeenCalled();
    expect(navigate).toHaveBeenCalledWith(['/enrolments'], jasmine.objectContaining({ queryParams: { focus: 116 } }));
  });
});
