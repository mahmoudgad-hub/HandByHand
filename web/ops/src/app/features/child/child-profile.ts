import { TablePages } from '@hbh/shared/ui/table-pages';
import {
  ChangeDetectionStrategy, Component, DestroyRef, InjectionToken, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { NgTemplateOutlet } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { Observable, catchError, forkJoin, map, of } from 'rxjs';

import { FormatService } from '@hbh/shared/format/format.service';
import { HbhPluralPipe } from '@hbh/shared/format/format.pipes';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon, childAvatar } from '@hbh/shared/icon/icon';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { OpsApi, OpsResource, Row } from '../../core/api/ops-api';
import { readAllPages } from '../../core/api/read-all-pages';
import { Balance, ChildApi, ChildPart } from '../../core/api/child-api';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { ActionDialogService } from '../../core/ops/action-dialog.service';
import { ActionOutcome } from '../../core/ops/action-request';
import { APPOINTMENTS_SPEC, REPORTS_SPEC, SESSIONS_SPEC } from '../../core/ops/day-spec';
import { RecordDrawerService } from '../../core/ops/record-drawer.service';

type Tab = 'overview' | 'family' | 'appointments' | 'sessions' | 'assessments' | 'plans' | 'goals'
  | 'reports' | 'packages' | 'invoices' | 'notes' | 'home' | 'activity';

const TABS: readonly Tab[] = [
  'overview', 'family', 'appointments', 'sessions', 'assessments', 'plans', 'goals',
  'reports', 'packages', 'invoices', 'notes', 'home', 'activity',
];

/** Which child endpoint feeds a tab. Tabs without one are derived or static. */
const PART_OF: Partial<Readonly<Record<Tab, ChildPart>>> = {
  family: 'guardians', appointments: 'appointments', sessions: 'sessions', plans: 'plans',
  goals: 'plans', reports: 'reports', packages: 'packages', invoices: 'invoices', notes: 'notes',
  home: 'activity-log',
};

type PartState = 'idle' | 'loading' | 'ready' | 'failed';

export const EMBEDDED_CHILD_PROFILE = new InjectionToken<{ childId: number; close: () => void }>('Embedded child profile');

interface Specialist {
  readonly therapistId: number;
  readonly name: string;
  readonly serviceId: number;
  readonly serviceName: string;
  readonly primary: boolean;
}

export interface ActivityEvent {
  readonly at: string;
  readonly key: string;
  readonly detail?: string;
  readonly statusKey?: string;
}

/**
 * The child's file - the operational centre for one beneficiary.
 *
 * It used to read only, and said so: every verb lived on the screen that
 * owns it. That was right about WHERE the verb is defined and wrong about
 * where it is offered - a receptionist with a parent on the phone opened
 * four screens to book, assign and write for one child. The verbs are
 * still defined once, in day-spec.ts and resource-spec.ts, and they are
 * drawn here through ActionDialogService: the same dialog, the same
 * permission, the same state machine. This file adds no rule and copies
 * no form.
 *
 * READS ARE PAID FOR ONCE. The header needs the family, the caseload, the
 * plans and the diary; each is read once and kept, and a tab that needs
 * one of them finds it already here. The rest wait for their tab.
 *
 * THE SPECIALIST IS THE CASELOAD. Not the application, not the plan: the
 * row hbh.caseload holds is what "assigned" means in this schema, and it
 * is what starting a session checks.
 */
@Component({
  selector: 'hbh-child-profile',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [TablePages, RouterLink, NgTemplateOutlet, Icon, TranslatePipe, HbhPluralPipe, Skeleton, EmptyState, ErrorNote],
  templateUrl: './child-profile.html',
  styleUrl: './child-profile.css',
})
export class ChildProfile {
  private readonly api = inject(ChildApi);
  private readonly crud = inject(OpsApi);
  private readonly dialogs = inject(ActionDialogService);
  private readonly drawer = inject(RecordDrawerService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  private readonly i18n = inject(I18nService);
  protected readonly auth = inject(OpsAuthService);
  protected readonly format = inject(FormatService);

  private readonly embedded = inject(EMBEDDED_CHILD_PROFILE, { optional: true });
  protected readonly childId = this.embedded?.childId ?? Number(this.route.snapshot.paramMap.get('childId'));

  protected readonly child = signal<Row | null>(null);
  protected readonly balance = signal<Balance | null>(null);
  protected readonly state = signal<'loading' | 'ready' | 'notFound' | 'denied' | 'failed'>('loading');
  protected readonly notice = signal('');

  protected readonly tabs = TABS;
  protected readonly tab = signal<Tab>(this.tabFromUrl());

  /** Every child part, read once and kept. */
  protected readonly parts = signal<Partial<Record<ChildPart, readonly Row[]>>>({});
  protected readonly partStates = signal<Partial<Record<ChildPart, PartState>>>({});

  /** The caseload rows for this child, with names joined from the lists. */
  protected readonly specialists = signal<readonly Specialist[] | null>(null);
  protected readonly specialistsState = signal<PartState>('idle');

  /** Measurements for this child's goals: a page of the resource, filtered. */
  protected readonly measurements = signal<readonly Row[] | null>(null);
  protected readonly measurementsState = signal<PartState>('idle');

  /** The note or consent currently being sent, so its button cannot be pressed twice. */
  protected readonly publishing = signal<number | null>(null);

  // ---- header facts ----
  protected readonly name = computed(() => text(this.child() ?? {}, 'full_name_ar'));
  protected readonly childNo = computed(() => text(this.child() ?? {}, 'child_no'));
  protected readonly age = computed(() => {
    const born = text(this.child() ?? {}, 'birth_date');
    return born ? this.i18n.plural('child.age', this.format.ageYears(born)) : '';
  });
  protected readonly avatar = computed(() => childAvatar(text(this.child() ?? {}, 'gender')));
  protected readonly genderKey = computed(() => {
    const value = text(this.child() ?? {}, 'gender');
    return value ? `gender.${value}` : '';
  });
  protected readonly statusKey = computed(() => {
    const value = text(this.child() ?? {}, 'status');
    return value ? `status.child.${value}` : '';
  });
  protected readonly isArchived = computed(() => this.child()?.['active_flg'] === false);
  protected readonly outstanding = computed(() => {
    const balance = this.balance();
    return balance ? this.format.money(Number(balance.outstanding_amt), balance.currency_code) : '';
  });
  protected readonly guardians = computed(() => this.parts()['guardians'] ?? null);
  protected readonly primaryGuardian = computed(() => {
    const rows = this.guardians() ?? [];
    return rows.find((row) => row['is_primary'] === true) ?? rows[0] ?? null;
  });
  protected readonly primarySpecialist = computed(() => {
    const rows = this.specialists() ?? [];
    return rows.find((row) => row.primary) ?? rows[0] ?? null;
  });
  protected readonly plans = computed(() => this.parts()['plans'] ?? null);
  protected readonly currentPlan = computed(() => {
    const rows = this.plans() ?? [];
    return rows.find((row) => text(row, 'status') === 'ACTIVE')
      ?? rows.find((row) => text(row, 'status') === 'DRAFT') ?? null;
  });
  protected readonly appointments = computed(() => this.parts()['appointments'] ?? null);
  protected readonly nextAppointment = computed(() => {
    const now = new Date().toISOString();
    return [...(this.appointments() ?? [])]
      .filter((row) => text(row, 'starts_at') >= now && ['BOOKED', 'CONFIRMED', 'CHECKED_IN'].includes(text(row, 'status')))
      .sort((a, b) => text(a, 'starts_at').localeCompare(text(b, 'starts_at')))[0] ?? null;
  });
  protected readonly upcoming = computed(() => {
    const now = new Date().toISOString();
    return (this.appointments() ?? []).filter((r) => text(r, 'starts_at') >= now
      && !['CANCELLED', 'NO_SHOW', 'COMPLETED'].includes(text(r, 'status')));
  });
  protected readonly past = computed(() => {
    const now = new Date().toISOString();
    return (this.appointments() ?? []).filter((r) => text(r, 'starts_at') < now
      || ['CANCELLED', 'NO_SHOW', 'COMPLETED'].includes(text(r, 'status')));
  });
  /** Goals across every plan, each carrying its plan's title. */
  protected readonly goals = computed<readonly Row[]>(() => (this.plans() ?? []).flatMap((plan) => {
    const list = Array.isArray(plan['goals']) ? (plan['goals'] as Row[]) : [];
    return list.map((goal): Row => ({ ...goal, plan_id: plan['plan_id'], plan_title: plan['title_ar'] }));
  }));
  /** The origin application, when the child came from one. */
  protected readonly originApplication = computed(() => {
    const child = this.child() ?? {};
    return text(child, 'origin_source') === 'ENROLMENT_REQUEST' && num(child, 'origin_reference_id')
      ? num(child, 'origin_reference_id') : null;
  });

  /** Display flags: real states of real rows, thresholds for the eye only. */
  protected readonly flags = computed(() => {
    const out: { key: string; tone: 'warn' | 'info' }[] = [];
    if (!this.child()) {
      return out;
    }
    if (this.specialistsState() === 'ready' && !(this.specialists() ?? []).length) {
      out.push({ key: 'child.flag.noSpecialist', tone: 'warn' });
    }
    if (this.plans() && !this.currentPlan()) {
      out.push({ key: 'child.flag.noPlan', tone: 'info' });
    }
    if (this.appointments() && !this.nextAppointment()) {
      out.push({ key: 'child.flag.noUpcoming', tone: 'info' });
    }
    if (this.balance() && Number(this.balance()!.outstanding_amt) > 0) {
      out.push({ key: 'child.flag.outstanding', tone: 'warn' });
    }
    return out;
  });

  // ---- what may be offered (drawing; the server decides) ----
  protected readonly canBook = computed(() => this.dialogs.canCreate('appointments', 'book'));
  protected readonly canAssign = computed(() => this.dialogs.canWriteResource('caseload'));
  protected readonly canPlan = computed(() => this.dialogs.canWriteResource('plans'));
  protected readonly canGoal = computed(() => this.dialogs.canWriteResource('goals'));
  protected readonly canMeasure = computed(() => this.dialogs.canWriteResource('measurements'));
  protected readonly canReport = computed(() => this.auth.can('REPORT.WRITE'));
  protected readonly canMessage = computed(() => this.auth.can('REQUEST.MANAGE'));
  protected readonly canInvoices = computed(() => this.auth.can('BILLING.VIEW'));

  /** The activity timeline: the rows the file already holds, in time order. No event invented. */
  protected readonly activity = computed<readonly ActivityEvent[]>(() => {
    const out: ActivityEvent[] = [];
    for (const row of this.appointments() ?? []) {
      out.push({ at: text(row, 'starts_at'), key: 'child.event.appointment', detail: ref(row, 'service', 'name_ar'), statusKey: `status.appointment.${text(row, 'status')}` });
    }
    for (const row of this.parts()['sessions'] ?? []) {
      out.push({ at: text(row, 'started_at'), key: 'child.event.session', detail: ref(row, 'therapist', 'full_name_ar'), statusKey: `status.session.${text(row, 'status')}` });
    }
    for (const row of this.plans() ?? []) {
      if (text(row, 'start_date')) {
        out.push({ at: `${text(row, 'start_date')}T00:00:00Z`, key: 'child.event.plan', detail: text(row, 'title_ar'), statusKey: `status.plan.${text(row, 'status')}` });
      }
    }
    for (const row of this.parts()['reports'] ?? []) {
      const at = text(row, 'published_at') || (text(row, 'period_end') ? `${text(row, 'period_end')}T00:00:00Z` : '');
      if (at) {
        out.push({ at, key: 'child.event.report', detail: text(row, 'title_ar'), statusKey: `status.report.${text(row, 'status')}` });
      }
    }
    for (const row of this.parts()['invoices'] ?? []) {
      if (text(row, 'issue_date')) {
        out.push({ at: `${text(row, 'issue_date')}T00:00:00Z`, key: 'child.event.invoice', detail: text(row, 'invoice_no'), statusKey: `status.invoice.${text(row, 'status')}` });
      }
    }
    return out.filter((e) => e.at).sort((a, b) => b.at.localeCompare(a.at));
  });

  constructor() {
    this.load();
    // A record changed from the drawer beside this file: only the part it
    // belongs to is read again - the diary, or the invoices and the
    // balance that sums them. The rest of the file stays as it is.
    this.drawer.changed$
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe((target) => {
        if (target.entity === 'appointment') {
          this.loadPart('appointments', true);
        } else {
          if (this.partStates()['invoices']) {
            this.loadPart('invoices', true);
          }
          this.reloadBalance();
        }
      });
  }

  // ---- the record drawer: the row this file already holds, beside it ----

  protected openAppointment(row: Row): void {
    void this.drawer.open({
      entity: 'appointment', id: num(row, 'appointment_id'), row, source: 'CHILD_PROFILE',
      context: { childId: this.childId, childName: this.name(), childNo: this.childNo() },
    });
  }

  protected openInvoice(row: Row): void {
    void this.drawer.open({
      entity: 'invoice', id: num(row, 'invoice_id'), row, source: 'CHILD_PROFILE',
      context: { childId: this.childId, childName: this.name(), childNo: this.childNo() },
    });
  }

  private reloadBalance(): void {
    this.api.balance(this.childId)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({ next: (balance) => this.balance.set(balance), error: () => undefined });
  }

  // ---- reads ----

  protected load(): void {
    this.state.set('loading');
    this.notice.set('');
    forkJoin({
      child: this.api.child(this.childId),
      balance: this.api.balance(this.childId).pipe(catchError(() => of(null))),
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.child.set(result.child);
          this.balance.set(result.balance as Balance | null);
          this.state.set('ready');
          // The header's four sources, once. Each tab that needs one of
          // them finds it here; the tabs that need something else load it
          // when opened.
          for (const part of ['guardians', 'appointments', 'plans'] as const) {
            this.loadPart(part);
          }
          this.loadSpecialists();
          this.ensureTab(this.tab());
          void this.openRequestedAssignment();
        },
        error: (error: unknown) => {
          const status = error instanceof HttpErrorResponse ? error.status : 0;
          this.state.set(status === 404 ? 'notFound' : status === 403 ? 'denied' : 'failed');
        },
      });
  }

  protected loadPart(part: ChildPart, force = false): void {
    const current = this.partStates()[part];
    if (!force && (current === 'loading' || current === 'ready')) {
      return;
    }
    this.partStates.update((s) => ({ ...s, [part]: 'loading' }));
    this.api.list(this.childId, part)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (rows) => {
          this.parts.update((p) => ({ ...p, [part]: rows }));
          this.partStates.update((s) => ({ ...s, [part]: 'ready' }));
        },
        error: () => this.partStates.update((s) => ({ ...s, [part]: 'failed' })),
      });
  }

  protected partState(part: ChildPart): PartState {
    return this.partStates()[part] ?? 'idle';
  }

  protected rowsOf(part: ChildPart): readonly Row[] {
    return this.parts()[part] ?? [];
  }

  /**
   * The caseload for this child. The resource has no child filter, so a
   * complete list is read and filtered here; the names come from the lists
   * the booking dialog reads anyway.
   */
  protected loadSpecialists(force = false): void {
    if (!force && (this.specialistsState() === 'loading' || this.specialistsState() === 'ready')) {
      return;
    }
    if (!this.auth.can('STAFF.MANAGE')) {
      // The caseload list is the administrator's. Others are told the
      // specialist is unknown to this screen rather than shown "none".
      this.specialistsState.set('failed');
      return;
    }
    this.specialistsState.set('loading');
    forkJoin({
      caseload: readAllPages((page) => this.crud.list('caseload', { limit: 100, page })),
      therapists: readAllPages((page) => this.crud.list('therapists', { limit: 100, page })).pipe(catchError(() => of([] as readonly Row[]))),
      services: readAllPages((page) => this.crud.list('services', { limit: 100, page })).pipe(catchError(() => of([] as readonly Row[]))),
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: ({ caseload, therapists, services }) => {
          const nameOf = new Map(therapists.map((t) => [num(t, 'therapist_id'), text(t, 'full_name_ar')]));
          const serviceOf = new Map(services.map((s) => [num(s, 'service_id'), text(s, 'name_ar')]));
          this.specialists.set(caseload
            .filter((row) => num(row, 'child_id') === this.childId)
            .map((row): Specialist => ({
              therapistId: num(row, 'therapist_id'),
              name: nameOf.get(num(row, 'therapist_id')) ?? `#${num(row, 'therapist_id')}`,
              serviceId: num(row, 'service_id'),
              serviceName: serviceOf.get(num(row, 'service_id')) ?? '',
              primary: row['is_primary_flg'] === true,
            })));
          this.specialistsState.set('ready');
        },
        error: () => this.specialistsState.set('failed'),
      });
  }

  /** Measurements of this child's goals: a page of the resource, filtered by the goal ids the plans carry. */
  protected loadMeasurements(force = false): void {
    if (!force && (this.measurementsState() === 'loading' || this.measurementsState() === 'ready')) {
      return;
    }
    if (!this.auth.can('GOAL.MEASURE') && !this.auth.can('PLAN.MANAGE')) {
      this.measurementsState.set('failed');
      return;
    }
    this.measurementsState.set('loading');
    this.crud.list('measurements', { limit: 200 })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (page) => {
          const goalIds = new Set(this.goals().map((g) => num(g, 'goal_id')));
          this.measurements.set(page.rows.filter((row) => goalIds.has(num(row, 'goal_id'))));
          this.measurementsState.set('ready');
        },
        error: () => this.measurementsState.set('failed'),
      });
  }

  protected measurementsOf(goalId: number): readonly Row[] {
    return (this.measurements() ?? []).filter((row) => num(row, 'goal_id') === goalId);
  }

  // ---- tabs ----

  /**
   * The tab the file opens on when the address names none.
   *
   * A clinician - an account with a day of its own that does not book -
   * opens on the plan: it is where their work on this child is, and the
   * overview above it is written for the desk. Everybody else opens on
   * the overview. A default, drawn from what the account holds; it
   * grants nothing and the address still wins.
   */
  private tabFromUrl(): Tab {
    const wanted = this.embedded ? null : this.route.snapshot.queryParamMap.get('tab') as Tab | null;
    if (wanted && TABS.includes(wanted)) {
      return wanted;
    }
    const clinician = this.auth.me()?.therapistId !== undefined
      && !this.auth.can('APPOINTMENT.BOOK') && this.auth.can('PLAN.MANAGE');
    return clinician ? 'plans' : 'overview';
  }

  protected selectTab(tab: Tab): void {
    this.tab.set(tab);
    this.ensureTab(tab);
    if (this.embedded) return;
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: { tab: tab === 'overview' ? null : tab },
      queryParamsHandling: 'merge',
      replaceUrl: true,
    });
  }

  /** What a tab needs, read when it is opened and not before. */
  private ensureTab(tab: Tab): void {
    if (tab === 'invoices' && !this.canInvoices()) {
      return;
    }
    const part = PART_OF[tab];
    if (part) {
      this.loadPart(part);
    }
    if (tab === 'goals') {
      this.loadMeasurements();
    }
    if (tab === 'activity') {
      for (const p of ['sessions', 'reports'] as const) {
        this.loadPart(p);
      }
      if (this.canInvoices()) {
        this.loadPart('invoices');
      }
    }
  }

  protected tabVisible(tab: Tab): boolean {
    return tab !== 'invoices' || this.canInvoices();
  }

  // ---- actions: every one is the owning screen's dialog, drawn here ----

  protected book(): void {
    this.dialogs.open({
      actionType: 'book', entityType: 'appointments', source: 'CHILD_PROFILE',
      prefill: { child_id: String(this.childId) }, prefillLabels: { child_id: this.pickerLabel() },
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe((outcome) => this.settle(outcome, ['appointments']));
  }

  protected assignTherapist(): void {
    this.openResource('caseload', 'create', { child_id: String(this.childId) }, [], true);
  }

  private assignmentRequested = false;

  /** A task link opens the existing editor, never submits the assignment. */
  private async openRequestedAssignment(): Promise<void> {
    if (this.embedded || this.assignmentRequested || this.route.snapshot.queryParamMap.get('action') !== 'assign') {
      return;
    }
    this.assignmentRequested = true;
    const navigated = await this.router.navigate([], {
      relativeTo: this.route, queryParams: { action: null },
      queryParamsHandling: 'merge', replaceUrl: true,
    });
    if (!navigated || this.destroyRef.destroyed) {
      return;
    }
    if (!this.canAssign()) {
      this.notice.set('enrolment.notice.DENIED');
      return;
    }
    this.assignTherapist();
  }

  protected newPlan(): void {
    this.openResource('plans', 'create', { child_id: String(this.childId) }, ['plans']);
  }

  protected editPlan(row: Row): void {
    this.openResource('plans', 'edit', undefined, ['plans'], false, row);
  }

  protected addGoal(plan: Row): void {
    this.openResource('goals', 'create', { plan_id: text(plan, 'plan_id') }, ['plans']);
  }

  protected editGoal(goal: Row): void {
    this.openResource('goals', 'edit', undefined, ['plans'], false, goal);
  }

  protected addMeasurement(goal: Row): void {
    this.openResource('measurements', 'create', {
      goal_id: text(goal, 'goal_id'), measured_on: this.format.today(),
    }, ['plans'], false, undefined, true);
  }

  /** A row action from a day spec, on a row this file already holds. */
  protected rowAction(entityType: 'appointments' | 'sessions' | 'reports', actionType: string, row: Row): void {
    this.dialogs.open({ actionType, entityType, row, source: 'CHILD_PROFILE' })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe((outcome) => this.settle(outcome, entityType === 'reports' ? ['reports'] : ['appointments', 'sessions']));
  }

  protected canRow(entityType: 'appointments' | 'sessions' | 'reports', actionType: string, row: Row): boolean {
    return this.dialogs.canOffer(entityType, actionType, row);
  }

  private openResource(
    resource: OpsResource, mode: 'create' | 'edit', prefill: Record<string, string> | undefined,
    reload: readonly ChildPart[], reloadSpecialists = false, row?: Row, reloadMeasurements = false,
  ): void {
    this.dialogs.openResource({ resource, mode, prefill, row, source: 'CHILD_PROFILE' })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe((outcome) => {
        this.settle(outcome, reload);
        if (outcome === 'DONE' && reloadSpecialists) {
          this.loadSpecialists(true);
        }
        if (outcome === 'DONE' && reloadMeasurements) {
          this.loadMeasurements(true);
        }
      });
  }

  private settle(outcome: ActionOutcome, reload: readonly ChildPart[]): void {
    if (outcome === 'DONE') {
      for (const part of reload) {
        this.loadPart(part, true);
      }
      return;
    }
    if (outcome === 'DENIED' || outcome === 'NOT_APPLICABLE' || outcome === 'UNKNOWN_ACTION') {
      this.notice.set(`enrolment.notice.${outcome}`);
    }
  }

  /** Name and centre number, the way the booking dialog's picker prints a child. */
  private pickerLabel(): string {
    const no = this.childNo();
    return no ? `${this.name()} · ${no}` : this.name();
  }

  // ---- the two writes this file always had: a note to the family, a live-view consent ----

  protected publishNote(row: Row): void {
    const id = num(row, 'note_id');
    if (!id || this.publishing() !== null) {
      return;
    }
    this.publishing.set(id);
    this.api.publishNote(id)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => { this.publishing.set(null); this.loadPart('notes', true); },
        error: () => this.publishing.set(null),
      });
  }

  protected toggleLiveConsent(row: Row): void {
    const guardian = num(row, 'guardian_id');
    if (!guardian || this.publishing() !== null) {
      return;
    }
    this.publishing.set(guardian);
    const call: Observable<unknown> = row['can_view_live'] === true
      ? this.api.withdrawConsent(guardian, 'LIVE_VIEW', this.childId)
      : this.api.grantConsent(guardian, 'LIVE_VIEW', this.childId);
    call.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: () => { this.publishing.set(null); this.loadPart('guardians', true); },
      error: () => this.publishing.set(null),
    });
  }

  // ---- display helpers ----

  protected val(key: string): string {
    return text(this.child() ?? {}, key);
  }

  protected t(row: Row, key: string): string {
    return text(row, key);
  }

  protected n(row: Row, key: string): number {
    return num(row, key);
  }

  protected r(row: Row, object: string, key: string): string {
    return ref(row, object, key);
  }

  protected when(iso: string): string {
    return iso ? `${this.format.dayMonthYear(iso)} · ${this.format.time(iso)}` : '';
  }

  protected day(iso: string): string {
    return iso ? this.format.dayMonthYear(iso) : '';
  }

  protected period(from: string, to: string): string {
    if (from && to) {
      return `${this.format.dayMonthYear(from)} – ${this.format.dayMonthYear(to)}`;
    }
    if (from) {
      return this.i18n.translate('field.periodFrom', { d: this.format.dayMonthYear(from) });
    }
    if (to) {
      return this.i18n.translate('field.periodUntil', { d: this.format.dayMonthYear(to) });
    }
    return '';
  }

  protected money(row: Row, key: string): string {
    return this.format.money(Number(text(row, key)), text(row, 'currency_code') || undefined);
  }

  protected apptStatusKey(row: Row): string { return `${APPOINTMENTS_SPEC.statusPrefix}${text(row, 'status')}`; }
  protected apptTone(row: Row): string { return APPOINTMENTS_SPEC.tone(text(row, 'status')); }
  protected sessionStatusKey(row: Row): string { return `${SESSIONS_SPEC.statusPrefix}${text(row, 'status')}`; }
  protected sessionTone(row: Row): string { return SESSIONS_SPEC.tone(text(row, 'status')); }
  protected reportStatusKey(row: Row): string { return `${REPORTS_SPEC.statusPrefix}${text(row, 'status')}`; }
  protected reportTone(row: Row): string { return REPORTS_SPEC.tone(text(row, 'status')); }

  protected pct(value: unknown): string {
    return value === null || value === undefined || value === '' ? '—' : this.format.percent(Number(value));
  }

  protected relationshipKey(row: Row): string {
    const code = text(row, 'relationship_code');
    return code ? `relationship.${code}` : '';
  }

  protected back(): void {
    if (this.embedded) { this.embedded.close(); return; }
    void this.router.navigate(['/children']);
  }
}

function text(row: Row, key: string): string {
  const value = row[key];
  return value === null || value === undefined ? '' : String(value);
}

function num(row: Row, key: string): number {
  const value = Number(row[key]);
  return Number.isFinite(value) ? value : 0;
}

function ref(row: Row, object: string, key: string): string {
  const nested = row[object] as Record<string, unknown> | undefined | null;
  const value = nested?.[key];
  return value === null || value === undefined ? '' : String(value);
}
