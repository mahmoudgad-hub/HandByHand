import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { OpsAuthService } from '../auth/ops-auth.service';
import { ActionDialogService } from './action-dialog.service';
import { ActionOutcome } from './action-request';
import { REQUESTS_SPEC } from './day-spec';

/**
 * The orchestrator asks the list screen's two questions and nothing more.
 *
 * The permission and the `when(row)` it consults are the ones in
 * day-spec.ts; a wrong answer here would mean a dialog opening where the
 * list would not draw the button. And nothing runs: DONE is only ever
 * reported by the dialog's own close, which these tests drive by hand.
 */
describe('ActionDialogService', () => {
  let held: Set<string>;
  let svc: ActionDialogService;
  let http: HttpTestingController;

  const ROW = { application_id: 116, status: 'CONTACTED' };

  beforeEach(() => {
    held = new Set(['ENROLMENT.MANAGE']);
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(), provideHttpClientTesting(),
        { provide: HBH_CONFIG, useValue: { apiBaseUrl: '' } },
        { provide: OpsAuthService, useValue: { can: (p: string) => held.has(p), me: () => ({}) } },
      ],
    });
    svc = TestBed.inject(ActionDialogService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  function outcomeOf(actionType: string, row = ROW as Record<string, unknown>): ActionOutcome | undefined {
    let out: ActionOutcome | undefined;
    svc.open({ actionType, entityType: 'enrolments', entityId: 116, row, source: 'TASK_INBOX' })
      .subscribe((value) => { out = value; });
    return out;
  }

  it('refuses an action the account may not use, before drawing anything', () => {
    held.clear();
    expect(outcomeOf('convert')).toBe('DENIED');
    expect(svc.active()).toBeNull();
  });

  it('refuses an action the row is not in a state for', () => {
    expect(outcomeOf('convert', { application_id: 116, status: 'NEW' })).toBe('NOT_APPLICABLE');
    expect(svc.active()).toBeNull();
  });

  it('refuses a name the resource has no action for, and a link action', () => {
    expect(outcomeOf('nope')).toBe('UNKNOWN_ACTION');
    expect(outcomeOf('open')).toBe('UNKNOWN_ACTION');
  });

  it('draws the dialog and reports DONE only when the dialog says it confirmed', () => {
    let out: ActionOutcome | undefined;
    svc.open({ actionType: 'convert', entityType: 'enrolments', entityId: 116, row: ROW, source: 'ENROLMENT_DETAIL' })
      .subscribe((value) => { out = value; });
    const active = svc.active();
    expect(active).not.toBeNull();
    expect(active!.action.key).toBe('convert');
    expect(out).toBeUndefined();
    active!.onClose(true);
    expect(out).toBe('DONE');
    expect(svc.active()).toBeNull();
  });

  it('reports CANCELLED on a plain close, and closes only once', () => {
    let count = 0;
    svc.open({ actionType: 'status', entityType: 'enrolments', entityId: 116, row: ROW, source: 'ENROLMENT_DETAIL' })
      .subscribe(() => { count++; });
    const active = svc.active()!;
    active.onClose(false);
    active.onClose(true);
    expect(count).toBe(1);
  });

  it('reads the row itself when the caller has none', () => {
    let out: ActionOutcome | undefined;
    svc.open({ actionType: 'status', entityType: 'enrolments', entityId: 116, source: 'DEEP_LINK' })
      .subscribe((value) => { out = value; });
    http.expectOne('/api/v1/enrolments/116').flush({ application_id: 116, status: 'NEW' });
    expect(svc.active()?.row?.['status']).toBe('NEW');
    expect(out).toBeUndefined();
    svc.active()!.onClose(false);
    expect(out).toBe('CANCELLED');
  });

  it('reports NOT_FOUND when the row cannot be read', () => {
    let out: ActionOutcome | undefined;
    svc.open({ actionType: 'status', entityType: 'enrolments', entityId: 999, source: 'DEEP_LINK' })
      .subscribe((value) => { out = value; });
    http.expectOne('/api/v1/enrolments/999').flush({}, { status: 404, statusText: 'Not Found' });
    expect(out).toBe('NOT_FOUND');
  });

  it('canOffer agrees with open', () => {
    expect(svc.canOffer('enrolments', 'convert', ROW)).toBeTrue();
    expect(svc.canOffer('enrolments', 'convert', { status: 'NEW' })).toBeFalse();
    held.clear();
    expect(svc.canOffer('enrolments', 'convert', ROW)).toBeFalse();
  });

  it('keeps appointment follow-up a permission-gated link, never a mutation dialog', () => {
    const row = { status: 'ACCEPTED', kind_code: 'RESCHEDULE', child: { child_id: 5 } };
    const action = REQUESTS_SPEC.actions.find(a => a.key === 'followAppointment')!;
    expect(action.permission).toBe('APPOINTMENT.BOOK');
    expect(action.when(row)).toBeTrue();
    expect(action.link!(row)).toEqual(['/children', 5]);
    expect(action.query).toEqual({ tab: 'appointments' });
    expect(action.when({ ...row, status: 'NEW' })).toBeFalse();
    expect(action.when({ ...row, kind_code: 'CALLBACK' })).toBeFalse();
    expect(svc.canOffer('requests', 'followAppointment', row)).toBeFalse();
    held.add('APPOINTMENT.BOOK');
    expect(svc.canOffer('requests', 'followAppointment', row)).toBeFalse();
  });
});
