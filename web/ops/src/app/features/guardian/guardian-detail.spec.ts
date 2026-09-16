import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ActivatedRoute, Router, convertToParamMap, provideRouter } from '@angular/router';
import { of } from 'rxjs';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { ActionDialogService } from '../../core/ops/action-dialog.service';
import { ActionOutcome, ResourceRequest } from '../../core/ops/action-request';
import { DrawerRequest } from '../../core/ops/record-drawer';
import { RecordDrawerService } from '../../core/ops/record-drawer.service';
import { GuardianDetail } from './guardian-detail';

/**
 * The guardian page: one guardian row, the family behind it, and links to
 * every child and application - from reads the console already makes.
 */
describe('GuardianDetail', () => {
  let http: HttpTestingController;
  let held: Set<string>;
  let query: Record<string, string>;
  let openedResource: ResourceRequest[];
  let outcome: ActionOutcome;
  let openedDrawer: DrawerRequest[];

  const GUARDIAN = { guardian_id: 9, full_name_ar: 'منى سعيد', mobile: '+201155667788', email: 'mona@example.com', city: 'القاهرة', user_id: 44, created_at: '2026-09-01T09:00:00Z' };
  const CHILDREN = { children: [{ child_id: 5, full_name_ar: 'عمر خالد', child_no: 'C-0005', birth_date: '2021-05-20', status: 'ACTIVE' }], total: 1, limit: 100, offset: 0 };
  const ENROLMENTS = { enrolments: [
    { application_id: 116, application_no: 'ENR-2026-00116', status: 'NEW', child_name_ar: 'عمر خالد', parent_mobile: '+201155667788', submitted_at: '2026-09-03T08:26:00Z' },
    { application_id: 200, application_no: 'ENR-2026-00200', status: 'NEW', child_name_ar: 'غريب', parent_mobile: '+20100000000', submitted_at: '2026-09-04T08:26:00Z' },
  ], total: 2, limit: 100, offset: 0 };
  const REQUESTS = { requests: [], total: 0, limit: 100, offset: 0 };

  function mount(): ComponentFixture<GuardianDetail> {
    TestBed.configureTestingModule({
      imports: [GuardianDetail],
      providers: [
        provideRouter([]), provideHttpClient(), provideHttpClientTesting(),
        { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, apiBaseUrl: '' } },
        { provide: OpsAuthService, useValue: { can: (p: string) => held.has(p), me: () => ({}) } },
        { provide: RecordDrawerService, useValue: { open: (request: DrawerRequest) => openedDrawer.push(request), changed$: of() } },
        {
          provide: ActionDialogService, useValue: {
            openResource: (request: ResourceRequest) => { openedResource.push(request); return of(outcome); },
            canWriteResource: () => held.has('GUARDIAN.MANAGE'),
          },
        },
        { provide: ActivatedRoute, useValue: { snapshot: { paramMap: convertToParamMap({ guardianId: '9' }), queryParamMap: convertToParamMap(query) } } },
      ],
    });
    const router = TestBed.inject(Router);
    spyOn(router, 'navigate').and.resolveTo(true);
    spyOn(router, 'navigateByUrl').and.resolveTo(true);
    http = TestBed.inject(HttpTestingController);
    const fixture = TestBed.createComponent(GuardianDetail);
    fixture.detectChanges();
    return fixture;
  }

  /** Answers the header read and the three family reads. */
  function flushAll(fixture: ComponentFixture<GuardianDetail>): void {
    http.expectOne('/api/v1/guardians/9').flush(GUARDIAN);
    fixture.detectChanges();
    http.expectOne((r) => r.url === '/api/v1/children').flush(CHILDREN);
    http.expectOne((r) => r.url === '/api/v1/enrolments').flush(ENROLMENTS);
    http.expectOne((r) => r.url === '/api/v1/requests').flush(REQUESTS);
    fixture.detectChanges();
    // A one-child family: the overview reads the diary at once.
    http.match('/api/v1/children/5/appointments').forEach((r) => r.flush({ appointments: [] }));
    fixture.detectChanges();
  }

  beforeEach(() => {
    held = new Set(['GUARDIAN.MANAGE', 'ENROLMENT.MANAGE', 'REQUEST.MANAGE', 'CHILD.VIEW_ALL']);
    query = {};
    openedResource = [];
    openedDrawer = [];
    outcome = 'CANCELLED';
  });

  afterEach(() => http.verify());

  it('finds a family application on a later page', () => {
    const fixture = mount();
    http.expectOne('/api/v1/guardians/9').flush(GUARDIAN);
    http.expectOne(r => r.url === '/api/v1/children').flush(CHILDREN);
    http.expectOne(r => r.url === '/api/v1/enrolments').flush({
      enrolments: Array.from({ length: 100 }, (_, i) => ({ ...ENROLMENTS.enrolments[1], application_id: 1000 + i })),
      total: 101, limit: 100, offset: 0,
    });
    http.expectOne(r => r.url === '/api/v1/enrolments' && r.params.get('page') === '2').flush({
      enrolments: [ENROLMENTS.enrolments[0]], total: 101, limit: 100, offset: 100,
    });
    http.expectOne(r => r.url === '/api/v1/requests').flush(REQUESTS);
    http.match('/api/v1/children/5/appointments').forEach(r => r.flush({ appointments: [] }));
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('a[href="/enrolments/116"]')).not.toBeNull();
    expect(fixture.nativeElement.querySelector('a[href="/enrolments/1000"]')).toBeNull();
  });

  it('reads the guardian and shows the name, the children and the family\'s applications only', () => {
    const fixture = mount();
    flushAll(fixture);
    const el = fixture.nativeElement as HTMLElement;
    expect(el.textContent).toContain('منى سعيد');
    expect(el.querySelector('a[href="/children/5"]')).withContext('link to the child').not.toBeNull();
    expect(el.querySelector('a[href="/enrolments/116"]')).withContext('link to the family\'s application').not.toBeNull();
    expect(el.querySelector('a[href="/enrolments/200"]')).withContext('a stranger\'s application is not shown').toBeNull();
  });

  it('shows "not found" on a 404 and the refusal page on a 403', () => {
    let fixture = mount();
    http.expectOne('/api/v1/guardians/9').flush({}, { status: 404, statusText: 'Not Found' });
    fixture.detectChanges();
    expect((fixture.nativeElement as HTMLElement).textContent).toContain('guardian.notFound');
    TestBed.resetTestingModule();
    fixture = mount();
    http.expectOne('/api/v1/guardians/9').flush({}, { status: 403, statusText: 'Forbidden' });
    fixture.detectChanges();
    expect((fixture.nativeElement as HTMLElement).textContent).toContain('denied.title');
  });

  it('does not ask for applications or requests without the permissions, and hides the edit button', () => {
    held = new Set(['CHILD.VIEW_ALL']);
    const fixture = mount();
    http.expectOne('/api/v1/guardians/9').flush(GUARDIAN);
    fixture.detectChanges();
    http.expectOne((r) => r.url === '/api/v1/children').flush(CHILDREN);
    http.expectNone((r) => r.url === '/api/v1/enrolments');
    http.expectNone((r) => r.url === '/api/v1/requests');
    fixture.detectChanges();
    http.match('/api/v1/children/5/appointments').forEach((r) => r.flush({ appointments: [] }));
    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.textContent).not.toContain('guardian.edit');
  });

  it('opens the guardians list\'s own editor on this row, and re-reads after DONE', () => {
    outcome = 'DONE';
    const fixture = mount();
    flushAll(fixture);
    const button = Array.from((fixture.nativeElement as HTMLElement).querySelectorAll('button'))
      .find((b) => b.textContent?.includes('guardian.edit')) as HTMLButtonElement;
    button.click();
    expect(openedResource.length).toBe(1);
    expect(openedResource[0].resource).toBe('guardians');
    expect(openedResource[0].mode).toBe('edit');
    expect(openedResource[0].row?.['guardian_id']).toBe(9);
    flushAll(fixture);
  });

  it('reads the finance tab only when opened, and only with BILLING.VIEW', () => {
    held.add('BILLING.VIEW');
    query = { tab: 'finance' };
    const fixture = mount();
    flushAll(fixture);
    http.expectOne('/api/v1/children/5/balance').flush({ currency_code: 'EGP', outstanding_amt: '150', invoiced_amt: '400', paid_amt: '250', open_invoice_count: 1 });
    // The family's invoices come with the tab, from each child's own list.
    http.expectOne('/api/v1/children/5/invoices').flush({ invoices: [{ invoice_id: 12, invoice_no: 'INV-2026-00012', status: 'ISSUED', issue_date: '2026-08-01', total_amt: '400', paid_amt: '150', currency_code: 'EGP' }] });
    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.textContent).toContain('guardian.outstanding');
    expect(el.textContent).toContain('INV-2026-00012');
    // And an invoice opens in the record drawer, on the row, naming the child.
    const button = Array.from(el.querySelectorAll('button')).find((b) => b.textContent?.includes('action.open')) as HTMLButtonElement;
    button.click();
    expect(openedDrawer[0]).toEqual(jasmine.objectContaining({ entity: 'invoice', id: 12, source: 'GUARDIAN_DETAIL' }));
    expect(openedDrawer[0].context?.childId).toBe(5);
    expect(openedDrawer[0].context?.childName).toBe('عمر خالد');
  });

  it('goes back to the return address inside the app', () => {
    query = { returnUrl: '/enrolments/116' };
    const fixture = mount();
    flushAll(fixture);
    (fixture.nativeElement as HTMLElement).querySelector<HTMLButtonElement>('.gd__head button')!.click();
    expect(TestBed.inject(Router).navigateByUrl).toHaveBeenCalledWith('/enrolments/116');
  });
});
