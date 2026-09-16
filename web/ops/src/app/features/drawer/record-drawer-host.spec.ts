import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { provideLocationMocks } from '@angular/common/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { Router, provideRouter } from '@angular/router';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { ActionDialogService } from '../../core/ops/action-dialog.service';
import { DrawerTarget } from '../../core/ops/record-drawer';
import { RecordDrawerService } from '../../core/ops/record-drawer.service';
import { RecordDrawerHost } from './record-drawer-host';

/**
 * The drawer beside the page: one record, read once where it can be, the
 * list's own verbs drawn by permission and state, and a step from the
 * address offered - never run.
 *
 * ActionDialogService is the REAL one: what a button here opens is what
 * the list would open, checked the same way. The dialog itself is not
 * drawn (no host in this test); the test closes it by hand.
 */
describe('RecordDrawerHost', () => {
  let http: HttpTestingController;
  let held: Set<string>;
  let router: Router;
  let svc: RecordDrawerService;
  let dialogs: ActionDialogService;

  const APPT = {
    appointment_id: 70, appointment_no: 'APT-2026-00070', starts_at: '2099-01-01T10:00:00Z',
    ends_at: '2099-01-01T11:00:00Z', status: 'BOOKED', delivery_mode: 'IN_PERSON',
    child: { child_id: 5, full_name_ar: 'عمر خالد', child_no: 'C-0005' },
    service: { service_id: 2, name_ar: 'تخاطب' }, therapist: { therapist_id: 236, full_name_ar: 'سارة' },
    room: { room_id: 1, name_ar: 'غرفة ١' },
  };
  const GUARDIANS = { guardians: [{ guardian_id: 9, full_name_ar: 'منى سعيد', mobile: '+201155667788', is_primary: true }] };
  const INVOICE = {
    invoice_id: 12, invoice_no: 'INV-2026-00012', status: 'ISSUED', issue_date: '2026-08-01',
    due_date: '2026-08-15', currency_code: 'EGP', total_amt: '400.00', paid_amt: '150.00', tax_amt: '0',
    lines: [{ line_id: 1, description_ar: 'جلسة تخاطب', qty: '4', unit_amt: '100.00', line_amt: '400.00' }],
    payments: [{ payment_id: 1, amount: '150.00', method_code: 'CASH', paid_at: '2026-08-02T09:00:00Z' }],
  };

  async function mount(url: string): Promise<ComponentFixture<RecordDrawerHost>> {
    TestBed.configureTestingModule({
      imports: [RecordDrawerHost],
      providers: [
        provideRouter([{ path: '**', children: [] }]), provideLocationMocks(),
        provideHttpClient(), provideHttpClientTesting(),
        { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, apiBaseUrl: '' } },
        { provide: OpsAuthService, useValue: { can: (p: string) => held.has(p), me: () => ({}) } },
      ],
    });
    router = TestBed.inject(Router);
    await router.navigateByUrl(url);
    http = TestBed.inject(HttpTestingController);
    svc = TestBed.inject(RecordDrawerService);
    dialogs = TestBed.inject(ActionDialogService);
    const fixture = TestBed.createComponent(RecordDrawerHost);
    fixture.detectChanges();
    return fixture;
  }

  function el(fixture: ComponentFixture<RecordDrawerHost>): HTMLElement {
    return fixture.nativeElement as HTMLElement;
  }

  function buttons(fixture: ComponentFixture<RecordDrawerHost>): string[] {
    return Array.from(el(fixture).querySelectorAll('.rd__actions button')).map((b) => b.textContent?.trim() ?? '');
  }

  beforeEach(() => {
    held = new Set(['CHILD.VIEW_ALL', 'APPOINTMENT.BOOK', 'SESSION.START', 'GUARDIAN.MANAGE', 'BILLING.VIEW', 'BILLING.MANAGE']);
  });

  afterEach(() => http.verify());

  it('finds a copied appointment link outside today and beyond the first page', async () => {
    const fixture = await mount('/tasks?open=appointment:70&recordAt=2099-01-01T10:00:00Z');
    http.expectOne(r => r.url === '/api/v1/appointments' && r.params.get('from') === '2099-01-01T00:00:00.000Z')
      .flush({ appointments: Array.from({ length: 100 }, (_, i) => ({ ...APPT, appointment_id: 1000 + i })), total: 101, limit: 100, offset: 0 });
    http.expectOne(r => r.url === '/api/v1/appointments' && r.params.get('page') === '2')
      .flush({ appointments: [APPT], total: 101, limit: 100, offset: 100 });
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIANS);
    fixture.detectChanges();
    expect(el(fixture).textContent).toContain('APT-2026-00070');
  });

  it('shows a retry rather than not-found when the second appointment page fails', async () => {
    const fixture = await mount('/appointments?date=2099-01-01&open=appointment:70');
    http.expectOne(r => r.url === '/api/v1/appointments' && r.params.get('date') === '2099-01-01')
      .flush({ appointments: Array.from({ length: 100 }, (_, i) => ({ ...APPT, appointment_id: 1000 + i })), total: 101, limit: 100, offset: 0 });
    http.expectOne(r => r.url === '/api/v1/appointments' && r.params.get('page') === '2')
      .flush({}, { status: 500, statusText: 'Unavailable' });
    fixture.detectChanges();
    expect(el(fixture).querySelector('hbh-error-note')).not.toBeNull();
    expect(el(fixture).textContent).not.toContain('drawer.notFound');
  });

  it('draws nothing until asked', async () => {
    const fixture = await mount('/appointments');
    expect(el(fixture).querySelector('dialog')).toBeNull();
  });

  it('opens on a handed appointment row without reading it, and closes on X', async () => {
    const fixture = await mount('/appointments');
    svc.open({ entity: 'appointment', id: 70, row: APPT, source: 'LIST' });
    fixture.detectChanges();
    http.expectNone((r) => r.url === '/api/v1/appointments');
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIANS);
    fixture.detectChanges();
    const text = el(fixture).textContent ?? '';
    expect(text).toContain('APT-2026-00070');
    expect(text).toContain('عمر خالد');
    expect(text).toContain('منى سعيد');
    expect(text).toContain('تخاطب');
    expect(text).toContain('status.appointment.BOOKED');
    expect(el(fixture).querySelector('a[href="/children/5"]')).not.toBeNull();
    expect(el(fixture).querySelector('a[href="/guardians/9"]')).not.toBeNull();
    el(fixture).querySelector<HTMLButtonElement>('.hbh-drawer__head .hbh-iconbtn')!.click();
    await fixture.whenStable();
    await router.navigateByUrl('/appointments');
    fixture.detectChanges();
    expect(el(fixture).querySelector('dialog')).toBeNull();
  });

  it('offers one button per legal next state, and start only when checked in with no session', async () => {
    const fixture = await mount('/appointments');
    svc.open({ entity: 'appointment', id: 70, row: APPT, source: 'LIST' });
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIANS);
    fixture.detectChanges();
    expect(buttons(fixture)).toEqual([
      'drawer.appointment.to.CONFIRMED', 'drawer.appointment.to.CANCELLED', 'drawer.appointment.to.NO_SHOW',
    ]);
    svc.open({ entity: 'appointment', id: 71, row: { ...APPT, appointment_id: 71, status: 'CHECKED_IN', session_id: null }, source: 'LIST' });
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIANS);
    fixture.detectChanges();
    expect(buttons(fixture)[0]).toBe('sessions.start');
    expect(buttons(fixture)).toContain('drawer.appointment.to.COMPLETED');
  });

  it('draws no verb for an account without the permission - display, not a control', async () => {
    held = new Set(['CHILD.VIEW_ALL']);
    const fixture = await mount('/children/5');
    svc.open({ entity: 'appointment', id: 70, row: APPT, source: 'CHILD_PROFILE' });
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIANS);
    fixture.detectChanges();
    expect(buttons(fixture)).toEqual([]);
    // And the guardian is named, not linked: no GUARDIAN.MANAGE.
    expect(el(fixture).textContent).toContain('منى سعيد');
    expect(el(fixture).querySelector('a[href="/guardians/9"]')).toBeNull();
  });

  it('locates an appointment from the child\'s diary on a child address, and says not found when it is absent', async () => {
    const fixture = await mount('/children/5?tab=appointments&open=appointment:70');
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/appointments').flush({ appointments: [{ ...APPT, child: undefined }] });
    fixture.detectChanges();
    // The child-scoped row carries no child; the address does, and the name is read once.
    http.expectOne('/api/v1/children/5').flush({ child_id: 5, full_name_ar: 'عمر خالد', child_no: 'C-0005' });
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIANS);
    fixture.detectChanges();
    expect(el(fixture).textContent).toContain('APT-2026-00070');
    expect(el(fixture).textContent).toContain('عمر خالد');

    await router.navigateByUrl('/children/5?tab=appointments&open=appointment:999');
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/appointments').flush({ appointments: [APPT] });
    fixture.detectChanges();
    expect(el(fixture).textContent).toContain('drawer.appointmentNotFound');
  });

  it('locates an appointment in today\'s diary elsewhere, narrowed to "mine" when the address says so', async () => {
    const fixture = await mount('/appointments?view=mine&open=appointment:70');
    fixture.detectChanges();
    const read = http.expectOne((r) => r.url === '/api/v1/appointments');
    expect(read.request.params.get('mine')).toBe('true');
    expect(read.request.params.get('date')).toBeTruthy();
    read.flush({ appointments: [APPT], total: 1 });
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIANS);
    fixture.detectChanges();
    expect(el(fixture).textContent).toContain('APT-2026-00070');
  });

  it('opens the list\'s status dialog with the step pre-selected, consumes ?action=, and re-reads after DONE', async () => {
    const fixture = await mount('/tasks');
    const changed: DrawerTarget[] = [];
    svc.changed$.subscribe((target) => changed.push(target));
    svc.open({ entity: 'appointment', id: 70, row: APPT, action: 'confirm', source: 'TASK_INBOX' });
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIANS);
    fixture.detectChanges();
    const active = dialogs.active();
    expect(active).withContext('the diary\'s own dialog is open').not.toBeNull();
    expect(active!.action.key).toBe('status');
    expect(active!.request.prefill).toEqual({ status: 'CONFIRMED' });
    expect(active!.request.source).toBe('RECORD_DRAWER');
    expect(svc.active()?.action).withContext('the step is consumed').toBeUndefined();
    await fixture.whenStable();
    expect(router.url).not.toContain('action=');
    expect(router.url).toContain('open=appointment:70');

    active!.onClose(true);
    fixture.detectChanges();
    expect(changed).toEqual([{ entity: 'appointment', id: 70 }]);
    // The row is forgotten and located again - on /tasks, from today's diary.
    http.expectOne((r) => r.url === '/api/v1/appointments').flush({ appointments: [{ ...APPT, status: 'CONFIRMED' }] });
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIANS);
    fixture.detectChanges();
    expect(el(fixture).textContent).toContain('status.appointment.CONFIRMED');
  });

  it('says so, and opens nothing, when the step does not apply to the row or the account', async () => {
    const fixture = await mount('/tasks');
    svc.open({ entity: 'appointment', id: 70, row: { ...APPT, status: 'COMPLETED' }, action: 'confirm', source: 'TASK_INBOX' });
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIANS);
    fixture.detectChanges();
    expect(dialogs.active()).toBeNull();
    expect(el(fixture).textContent).toContain('drawer.notice.NOT_APPLICABLE');
  });

  it('reads one invoice, shows lines, payments, the remainder and "overdue", and offers payment to BILLING.MANAGE', async () => {
    const fixture = await mount('/billing');
    svc.open({ entity: 'invoice', id: 12, row: { invoice_id: 12, status: 'ISSUED', child: APPT.child }, source: 'LIST' });
    fixture.detectChanges();
    http.expectOne('/api/v1/invoices/12').flush(INVOICE);
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIANS);
    fixture.detectChanges();
    const text = el(fixture).textContent ?? '';
    expect(text).toContain('INV-2026-00012');
    expect(text).toContain('جلسة تخاطب');
    expect(text).toContain('pay.CASH');
    expect(text).toContain('drawer.overdue');
    expect(el(fixture).querySelector('.rd__figures .is-due')).withContext('remainder drawn as due').not.toBeNull();
    expect(buttons(fixture)).toEqual(['billing.addPayment']);
  });

  it('OQ-13: BILLING.VIEW without BILLING.MANAGE sees the invoice in full and no payment button', async () => {
    held = new Set(['CHILD.VIEW_ALL', 'BILLING.VIEW']);
    const fixture = await mount('/billing');
    svc.open({ entity: 'invoice', id: 12, row: { invoice_id: 12, status: 'ISSUED', child: APPT.child }, source: 'LIST' });
    fixture.detectChanges();
    http.expectOne('/api/v1/invoices/12').flush(INVOICE);
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIANS);
    fixture.detectChanges();
    expect(el(fixture).textContent).toContain('جلسة تخاطب');
    expect(buttons(fixture)).toEqual([]);
    expect(el(fixture).querySelector('a[href^="/billing"]')).withContext('the billing screen is still a link').not.toBeNull();
  });

  it('a draft invoice offers issue and add-line; a paid one offers nothing', async () => {
    const fixture = await mount('/billing');
    svc.open({ entity: 'invoice', id: 13, row: { invoice_id: 13, status: 'DRAFT', child: APPT.child }, source: 'LIST' });
    fixture.detectChanges();
    http.expectOne('/api/v1/invoices/13').flush({ ...INVOICE, invoice_id: 13, status: 'DRAFT', paid_amt: '0', payments: [] });
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIANS);
    fixture.detectChanges();
    expect(buttons(fixture)).toEqual(['billing.issue', 'billing.addLine']);
    expect(el(fixture).textContent).not.toContain('drawer.overdue');

    svc.open({ entity: 'invoice', id: 14, row: { invoice_id: 14, status: 'PAID', child: APPT.child }, source: 'LIST' });
    fixture.detectChanges();
    http.expectOne('/api/v1/invoices/14').flush({ ...INVOICE, invoice_id: 14, status: 'PAID', paid_amt: '400.00' });
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIANS);
    fixture.detectChanges();
    expect(buttons(fixture)).toEqual([]);
  });

  it('reopens an invoice from the address on a refresh, finding its child from the ledger page', async () => {
    const fixture = await mount('/tasks?open=invoice:12');
    fixture.detectChanges();
    http.expectOne('/api/v1/invoices/12').flush(INVOICE);
    fixture.detectChanges();
    const ledger = http.expectOne((r) => r.url === '/api/v1/invoices');
    expect(ledger.request.params.get('status')).toBe('ISSUED');
    ledger.flush({ invoices: [{ invoice_id: 12, status: 'ISSUED', child: APPT.child }], total: 1 });
    fixture.detectChanges();
    http.expectOne('/api/v1/children/5/guardians').flush(GUARDIANS);
    fixture.detectChanges();
    expect(el(fixture).textContent).toContain('عمر خالد');
    expect(el(fixture).textContent).toContain('INV-2026-00012');
  });

  it('shows not found on a 404, without guessing', async () => {
    const fixture = await mount('/tasks?open=invoice:999');
    fixture.detectChanges();
    http.expectOne('/api/v1/invoices/999').flush({}, { status: 404, statusText: 'Not Found' });
    fixture.detectChanges();
    expect(el(fixture).textContent).toContain('drawer.invoiceNotFound');
    expect(el(fixture).querySelector('.rd__actions')).toBeNull();
  });

  it('closes when the address moves on - the back button', async () => {
    const fixture = await mount('/tasks?open=invoice:12');
    fixture.detectChanges();
    http.expectOne('/api/v1/invoices/12').flush(INVOICE);
    fixture.detectChanges();
    http.expectOne((r) => r.url === '/api/v1/invoices').flush({ invoices: [], total: 0 });
    fixture.detectChanges();
    expect(el(fixture).querySelector('dialog')).not.toBeNull();
    await router.navigateByUrl('/tasks');
    fixture.detectChanges();
    expect(el(fixture).querySelector('dialog')).toBeNull();
  });
});
