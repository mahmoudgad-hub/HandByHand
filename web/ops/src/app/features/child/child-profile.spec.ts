import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { ActivatedRoute, Router, convertToParamMap, provideRouter } from '@angular/router';
import { of } from 'rxjs';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { ActionDialogService } from '../../core/ops/action-dialog.service';
import { ActionOutcome, ActionRequest, ResourceRequest } from '../../core/ops/action-request';
import { DrawerRequest } from '../../core/ops/record-drawer';
import { RecordDrawerService } from '../../core/ops/record-drawer.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { ChildProfile, EMBEDDED_CHILD_PROFILE } from './child-profile';

/**
 * The child's file as an operational centre: the specialist from the
 * caseload, tabs that read when opened, and actions that are the owning
 * screens' dialogs - drawn only for accounts that hold them.
 */
describe('ChildProfile', () => {
  let http: HttpTestingController;
  let held: Set<string>;
  let query: Record<string, string>;
  let opened: ActionRequest[];
  let openedResource: ResourceRequest[];
  let outcome: ActionOutcome;
  let openedDrawer: DrawerRequest[];
  let me: { therapistId?: number };

  const CHILD = { child_id: 5, child_no: 'C-0005', full_name_ar: 'عمر خالد', birth_date: '2021-05-20', gender: 'M', status: 'ACTIVE', active_flg: true };
  const BALANCE = { currency_code: 'EGP', outstanding_amt: '0', invoiced_amt: '0', paid_amt: '0', open_invoice_count: 0 };
  const GUARDIANS = { guardians: [{ guardian_id: 9, full_name_ar: 'منى سعيد', relationship_code: 'MOTHER', mobile: '+201155667788', is_primary: true, can_view_live: false }] };
  const PLANS = { plans: [{ plan_id: 3, title_ar: 'خطّة النطق', status: 'ACTIVE', start_date: '2026-09-01', service: { name_ar: 'تخاطب' }, therapist: { full_name_ar: 'سارة' }, goals: [{ goal_id: 31, title_ar: 'كلمات', status: 'OPEN', target_pct: 80, latest_pct: 40, measurement_count: 2 }] }] };
  const APPOINTMENTS = { appointments: [{ appointment_id: 70, starts_at: '2099-01-01T10:00:00Z', ends_at: '2099-01-01T11:00:00Z', status: 'CHECKED_IN', session_id: null, service: { name_ar: 'تخاطب' }, therapist: { therapist_id: 236, full_name_ar: 'سارة' } }] };

  function mount(embedded?: { childId: number; close: () => void }): ComponentFixture<ChildProfile> {
    TestBed.configureTestingModule({
      imports: [ChildProfile],
      providers: [
        { provide: EMBEDDED_CHILD_PROFILE, useValue: embedded ?? null },
        provideRouter([]), provideHttpClient(), provideHttpClientTesting(),
        { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, apiBaseUrl: '' } },
        { provide: OpsAuthService, useValue: { can: (p: string) => held.has(p), me: () => me } },
        { provide: RecordDrawerService, useValue: { open: (request: DrawerRequest) => openedDrawer.push(request), changed$: of() } },
        {
          provide: ActionDialogService, useValue: {
            open: (request: ActionRequest) => { opened.push(request); return of(outcome); },
            openResource: (request: ResourceRequest) => { openedResource.push(request); return of(outcome); },
            canCreate: (_e: string, a: string) => a === 'book' && held.has('APPOINTMENT.BOOK'),
            canWriteResource: (r: string) => (r === 'caseload' ? held.has('STAFF.MANAGE') : held.has('PLAN.MANAGE')),
            canOffer: (_e: string, a: string, row: Record<string, unknown>) =>
              a === 'start' ? held.has('SESSION.START') && row['status'] === 'CHECKED_IN' && row['session_id'] == null
              : a === 'status' ? held.has('APPOINTMENT.BOOK') : false,
          },
        },
        { provide: ActivatedRoute, useValue: { snapshot: { paramMap: convertToParamMap({ childId: '5' }), queryParamMap: convertToParamMap(query) } } },
      ],
    });
    spyOn(TestBed.inject(Router), 'navigate').and.resolveTo(true);
    http = TestBed.inject(HttpTestingController);
    const fixture = TestBed.createComponent(ChildProfile);
    fixture.detectChanges();
    return fixture;
  }

  /** The header's reads: the child, the balance, then the family, the diary, the plans, and the caseload lists when allowed. */
  function flushHeader(fixture: ComponentFixture<ChildProfile>): void {
    http.expectOne('/api/v1/children/5').flush(CHILD);
    http.expectOne('/api/v1/children/5/balance').flush(BALANCE);
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIANS);
    http.expectOne('/api/v1/children/5/appointments').flush(APPOINTMENTS);
    http.expectOne('/api/v1/children/5/plans').flush(PLANS);
    if (held.has('STAFF.MANAGE')) {
      http.expectOne((r) => r.url === '/api/v1/caseload').flush({ caseload: [{ caseload_id: 1, child_id: 5, therapist_id: 236, service_id: 2, is_primary_flg: true }, { caseload_id: 2, child_id: 6, therapist_id: 1, service_id: 2 }], total: 2, limit: 200, offset: 0 });
      http.expectOne((r) => r.url === '/api/v1/therapists').flush({ therapists: [{ therapist_id: 236, full_name_ar: 'سارة عبد الرحمن' }], total: 1, limit: 200, offset: 0 });
      http.expectOne((r) => r.url === '/api/v1/services').flush({ services: [{ service_id: 2, name_ar: 'تخاطب' }], total: 1, limit: 200, offset: 0 });
    }
    fixture.detectChanges();
  }

  beforeEach(() => {
    held = new Set(['CHILD.VIEW_ALL', 'STAFF.MANAGE', 'APPOINTMENT.BOOK', 'PLAN.MANAGE', 'SESSION.START', 'REPORT.WRITE', 'BILLING.VIEW']);
    query = {};
    opened = [];
    openedResource = [];
    openedDrawer = [];
    me = {};
    outcome = 'CANCELLED';
  });

  afterEach(() => http.verify());

  it('keeps embedded tabs and back inside the popup without consuming the parent route', async () => {
    query = { tab: 'invoices', action: 'assign' };
    const close = jasmine.createSpy('close');
    const fixture = mount({ childId: 5, close });
    flushHeader(fixture);
    await fixture.whenStable();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('[role=tab].is-active')?.textContent).toContain('child.tab.overview');
    const family = Array.from(el.querySelectorAll<HTMLButtonElement>('[role=tab]'))
      .find(button => button.textContent?.includes('child.tab.family'))!;
    family.click();
    fixture.detectChanges();
    expect(el.querySelector('[role=tab].is-active')?.textContent).toContain('child.tab.family');
    el.querySelector<HTMLButtonElement>('.cp__head .hbh-iconbtn')!.click();
    expect(close).toHaveBeenCalledTimes(1);
    expect(TestBed.inject(Router).navigate).not.toHaveBeenCalled();
    expect(openedResource).toEqual([]);
  });

  it('consumes the assignment deep link and opens the editor for this child', async () => {
    query = { action: 'assign' };
    const fixture = mount();
    flushHeader(fixture);
    await fixture.whenStable();
    expect(TestBed.inject(Router).navigate).toHaveBeenCalledWith([], jasmine.objectContaining({
      queryParams: { action: null }, replaceUrl: true,
    }));
    expect(openedResource.length).toBe(1);
    expect(openedResource[0]).toEqual(jasmine.objectContaining({
      resource: 'caseload', mode: 'create', prefill: { child_id: '5' },
    }));
    fixture.detectChanges();
    expect(openedResource.length).toBe(1);
  });

  it('does not open the assignment deep link without permission', async () => {
    held.delete('STAFF.MANAGE');
    query = { action: 'assign' };
    const fixture = mount();
    flushHeader(fixture);
    await fixture.whenStable();
    expect(openedResource).toEqual([]);
  });

  it('names the assigned specialist from the caseload, for this child only, with the guardian linked', () => {
    const fixture = mount();
    flushHeader(fixture);
    const el = fixture.nativeElement as HTMLElement;
    expect(el.textContent).toContain('سارة عبد الرحمن');
    expect(el.querySelector('a[href="/guardians/9"]')).not.toBeNull();
    expect(el.textContent).toContain('خطّة النطق');
  });

  it('reads a tab only when it is opened, and not twice', () => {
    const fixture = mount();
    flushHeader(fixture);
    http.expectNone('/api/v1/children/5/sessions');
    const tab = Array.from((fixture.nativeElement as HTMLElement).querySelectorAll('[role=tab]'))
      .find((b) => b.textContent?.includes('child.tab.sessions')) as HTMLButtonElement;
    tab.click();
    http.expectOne('/api/v1/children/5/sessions').flush({ sessions: [] });
    fixture.detectChanges();
    tab.click();
    http.expectNone('/api/v1/children/5/sessions');
  });

  it('opens the booking dialog pre-filled with this child, and re-reads the diary after DONE', () => {
    outcome = 'DONE';
    const fixture = mount();
    flushHeader(fixture);
    const button = Array.from((fixture.nativeElement as HTMLElement).querySelectorAll('button'))
      .find((b) => b.textContent?.includes('appointments.book')) as HTMLButtonElement;
    button.click();
    expect(opened.length).toBe(1);
    expect(opened[0].actionType).toBe('book');
    expect(opened[0].prefill).toEqual({ child_id: '5' });
    expect(opened[0].prefillLabels?.['child_id']).toContain('عمر خالد');
    http.expectOne('/api/v1/children/5/appointments').flush(APPOINTMENTS);
  });

  it('assigns a therapist through the caseload editor pre-filled with the child', () => {
    const fixture = mount();
    flushHeader(fixture);
    const button = Array.from((fixture.nativeElement as HTMLElement).querySelectorAll('button'))
      .find((b) => b.textContent?.includes('child.assignTherapist')) as HTMLButtonElement;
    button.click();
    expect(openedResource[0]).toEqual(jasmine.objectContaining({ resource: 'caseload', mode: 'create', prefill: { child_id: '5' } }));
  });

  it('offers "start session" on a checked-in appointment with no session, through the diary\'s own action', () => {
    query = { tab: 'appointments' };
    const fixture = mount();
    flushHeader(fixture);
    const button = Array.from((fixture.nativeElement as HTMLElement).querySelectorAll('button'))
      .find((b) => b.textContent?.includes('sessions.start')) as HTMLButtonElement;
    expect(button).withContext('start button drawn').toBeDefined();
    button.click();
    expect(opened[0]).toEqual(jasmine.objectContaining({ actionType: 'start', entityType: 'appointments' }));
    expect(opened[0].row?.['appointment_id']).toBe(70);
  });

  it('hides every action from an account that holds none of the permissions, and says the specialist is unknown', () => {
    held = new Set(['CHILD.VIEW_ALL']);
    const fixture = mount();
    flushHeader(fixture);
    const el = fixture.nativeElement as HTMLElement;
    expect(el.textContent).not.toContain('appointments.book');
    expect(el.textContent).not.toContain('child.assignTherapist');
    expect(el.textContent).not.toContain('child.newPlan');
    expect(el.textContent).toContain('child.specialistUnknown');
    expect(Array.from(el.querySelectorAll('[role=tab]')).some((b) => b.textContent?.includes('child.tab.invoices'))).toBeFalse();
  });

  it('shows the goals with their latest measurement and lets a measurement be added to the goal', () => {
    held.add('GOAL.MEASURE');
    query = { tab: 'goals' };
    const fixture = mount();
    flushHeader(fixture);
    http.expectOne((r) => r.url === '/api/v1/measurements').flush({ measurements: [{ measurement_id: 1, goal_id: 31, measured_on: '2026-09-10', value_pct: 40 }, { measurement_id: 2, goal_id: 99, measured_on: '2026-09-10', value_pct: 10 }], total: 2, limit: 200, offset: 0 });
    fixture.detectChanges();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.textContent).toContain('كلمات');
    expect(el.textContent).toContain('child.measurements (1)');
    const button = Array.from(el.querySelectorAll('button')).find((b) => b.textContent?.includes('child.addMeasurement')) as HTMLButtonElement;
    button.click();
    expect(openedResource[0]).toEqual(jasmine.objectContaining({ resource: 'measurements', mode: 'create' }));
    expect(openedResource[0].prefill?.['goal_id']).toBe('31');
  });

  it('opens an appointment in the record drawer on the row it holds, naming the child', () => {
    query = { tab: 'appointments' };
    const fixture = mount();
    flushHeader(fixture);
    const button = Array.from((fixture.nativeElement as HTMLElement).querySelectorAll('.cp__cell-actions button'))
      .find((b) => b.textContent?.includes('action.open')) as HTMLButtonElement;
    button.click();
    expect(openedDrawer.length).toBe(1);
    expect(openedDrawer[0]).toEqual(jasmine.objectContaining({ entity: 'appointment', id: 70, source: 'CHILD_PROFILE' }));
    expect(openedDrawer[0].row?.['appointment_id']).toBe(70);
    expect(openedDrawer[0].context).toEqual({ childId: 5, childName: 'عمر خالد', childNo: 'C-0005' });
  });

  it('opens on the plan for a clinician, and on the overview for everybody else', () => {
    held = new Set(['CHILD.VIEW_ALL', 'PLAN.MANAGE', 'SESSION.START']);
    me = { therapistId: 236 };
    let fixture = mount();
    flushHeader(fixture);
    let active = (fixture.nativeElement as HTMLElement).querySelector('[role=tab].is-active');
    expect(active?.textContent).toContain('child.tab.plans');
    TestBed.resetTestingModule();
    held.add('APPOINTMENT.BOOK');
    me = {};
    fixture = mount();
    flushHeader(fixture);
    active = (fixture.nativeElement as HTMLElement).querySelector('[role=tab].is-active');
    expect(active?.textContent).toContain('child.tab.overview');
  });

  it('shows "not found" on a 404', () => {
    const fixture = mount();
    const balance = http.expectOne('/api/v1/children/5/balance');
    http.expectOne('/api/v1/children/5').flush({}, { status: 404, statusText: 'Not Found' });
    fixture.detectChanges();
    // The two are read together; when the child is not there the balance
    // read is abandoned, not answered.
    expect(balance.cancelled).toBeTrue();
    expect((fixture.nativeElement as HTMLElement).textContent).toContain('child.notFound');
  });
});

/**
 * Giving the family a way in (HBH-012).
 *
 * The properties held down here are the two that would hurt a real family if
 * they broke: the confirmation NAMES THE MOBILE the account will belong to -
 * a wrong number does not fail, it succeeds for a stranger who then receives
 * this child's reports - and a call that created nothing is not reported as
 * a new account.
 */
describe('ChildProfile portal access', () => {
  let http: HttpTestingController;
  let shown: string[];

  const CHILD_NO_ACCOUNT = {
    child_id: 5, child_no: 'C-0005', full_name_ar: 'عمر خالد', birth_date: '2021-05-20',
    gender: 'M', status: 'ACTIVE', active_flg: true, family_has_portal_account: false,
  };
  const GUARDIAN = {
    guardians: [{
      guardian_id: 9, full_name_ar: 'منى سعيد', relationship_code: 'MOTHER',
      mobile: '+201155667788', is_primary: true, can_view_live: false,
    }],
  };

  const mount = (child: Record<string, unknown>) => {
    shown = [];
    TestBed.configureTestingModule({
      imports: [ChildProfile],
      providers: [
        { provide: EMBEDDED_CHILD_PROFILE, useValue: null },
        provideRouter([]), provideHttpClient(), provideHttpClientTesting(),
        { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, apiBaseUrl: '' } },
        { provide: OpsAuthService, useValue: { can: () => true, me: () => ({}) } },
        { provide: RecordDrawerService, useValue: { open: () => {}, changed$: of() } },
        { provide: ToastService, useValue: { show: (t: string) => shown.push(t), error: (t: string) => shown.push(t) } },
        { provide: I18nService, useValue: { translate: (key: string) => key, plural: (key: string) => key } },
        {
          provide: ActionDialogService, useValue: {
            open: () => of('CANCELLED'), openResource: () => of('CANCELLED'),
            canCreate: () => false, canWriteResource: () => false, canOffer: () => false,
          },
        },
        { provide: ActivatedRoute, useValue: { snapshot: { paramMap: convertToParamMap({ childId: '5' }), queryParamMap: convertToParamMap({ tab: 'family' }) } } },
      ],
    });
    spyOn(TestBed.inject(Router), 'navigate').and.resolveTo(true);
    http = TestBed.inject(HttpTestingController);
    const fixture = TestBed.createComponent(ChildProfile);
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5').flush(child);
    http.expectOne('/api/v1/children/5/balance').flush(null, { status: 404, statusText: 'none' });
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIAN);
    http.expectOne('/api/v1/children/5/appointments').flush({ appointments: [] });
    http.expectOne('/api/v1/children/5/plans').flush({ plans: [] });
    // The caseload lookup the header does for anybody who may see it. Not
    // what these tests are about, but an unanswered request is an open
    // request, and http.verify() is right to say so.
    http.expectOne((r) => r.url === '/api/v1/caseload').flush({ caseload: [], total: 0, limit: 200, offset: 0 });
    http.expectOne((r) => r.url === '/api/v1/therapists').flush({ therapists: [], total: 0, limit: 200, offset: 0 });
    http.expectOne((r) => r.url === '/api/v1/services').flush({ services: [], total: 0, limit: 200, offset: 0 });
    fixture.detectChanges();
    return fixture;
  };

  const grantButton = (fixture: ComponentFixture<ChildProfile>) =>
    Array.from((fixture.nativeElement as HTMLElement).querySelectorAll<HTMLButtonElement>('td button'))
      .find((b) => b.textContent?.includes('portalAccess.grant'));

  afterEach(() => http.verify());

  it('shows the mobile the account will belong to before anything is sent', () => {
    const fixture = mount(CHILD_NO_ACCOUNT);
    grantButton(fixture)!.click();
    fixture.detectChanges();

    const dialog = (fixture.nativeElement as HTMLElement).querySelector('dialog');
    expect(dialog).withContext('the confirmation').not.toBeNull();
    expect(dialog!.textContent).toContain('+201155667788');
    // Nothing has been sent by opening it - http.verify() in afterEach says so.
  });

  it('tells the centre when the family already had one, rather than claiming a new account', () => {
    const fixture = mount(CHILD_NO_ACCOUNT);
    grantButton(fixture)!.click();
    fixture.detectChanges();
    (Array.from((fixture.nativeElement as HTMLElement).querySelectorAll<HTMLButtonElement>('dialog button'))
      .find((b) => b.textContent?.includes('portalAccess.grant')))!.click();
    fixture.detectChanges();

    const sent = http.expectOne('/api/v1/guardians/9/portal-access');
    expect(sent.request.method).toBe('POST');
    sent.flush({ user_id: 77, username: '+201155667788', created: false });
    fixture.detectChanges();

    expect(shown).toEqual(['portalAccess.existed']);
    // The flag is re-read rather than assumed: the screen asked the service
    // what is true now instead of flipping its own copy.
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIAN);
    http.expectOne('/api/v1/children/5').flush({ ...CHILD_NO_ACCOUNT, family_has_portal_account: true });
    fixture.detectChanges();
    expect(grantButton(fixture)).withContext('offered again after the family has one').toBeUndefined();
  });

  it('offers nothing to press when the family can already sign in', () => {
    const fixture = mount({ ...CHILD_NO_ACCOUNT, family_has_portal_account: true });
    expect(grantButton(fixture)).toBeUndefined();
  });

  it('offers nothing when the service did not say - unknown is not "no account"', () => {
    const { family_has_portal_account: _omitted, ...withoutFlag } = CHILD_NO_ACCOUNT;
    const fixture = mount(withoutFlag);
    expect(grantButton(fixture)).toBeUndefined();
  });
});
