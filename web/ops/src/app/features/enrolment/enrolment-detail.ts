import { TablePages } from '@hbh/shared/ui/table-pages';
import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { NgTemplateOutlet } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import { FormatService } from '@hbh/shared/format/format.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { ChildApi } from '../../core/api/child-api';
import { Row } from '../../core/api/ops-api';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { ActionDialogService } from '../../core/ops/action-dialog.service';
import { ActionOutcome, ActionRequest } from '../../core/ops/action-request';
import { DayApi } from '../../core/ops/day-api';
import { APPOINTMENTS_SPEC, ENROLMENTS_SPEC, ENROLMENT_NEXT } from '../../core/ops/day-spec';
import {
  activityFor, deepLinkRequest, flagsFor, nextStepFor, num, ref, text,
} from './enrolment-detail.model';
import { ENROLMENT_TABS, EnrolmentTab } from './enrolment-tabs';

type Tab = EnrolmentTab;
const TABS = ENROLMENT_TABS;

/**
 * One application, on its own page: who the family is, where the request
 * stands, what happened, what is required now, and the buttons that do it.
 *
 * EVERY BUTTON HERE IS ONE THE LIST ALREADY HAS. Change status, convert -
 * the same actions from ENROLMENTS_SPEC, drawn through ActionDialogService
 * so the dialog is the list's dialog and the rule is the schema's rule. The
 * "next step" is read off ENROLMENT_NEXT, the copy of the state machine the
 * list uses; this page decides nothing the list does not.
 *
 * A DEEP LINK MAY OPEN A DIALOG, NEVER RUN ONE. `?action=convert` opens
 * the convert dialog on a row where convert is legal and the account may;
 * the person still presses confirm. The parameter is cleared from the
 * address as soon as it has been read, so a refresh does not reopen it.
 */
@Component({
  selector: 'hbh-enrolment-detail',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [TablePages, RouterLink, NgTemplateOutlet, Icon, TranslatePipe, Skeleton, ErrorNote, EmptyState],
  templateUrl: './enrolment-detail.html',
  styleUrl: './enrolment-detail.css',
})
export class EnrolmentDetail {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly day = inject(DayApi);
  private readonly childApi = inject(ChildApi);
  private readonly dialogs = inject(ActionDialogService);
  private readonly destroyRef = inject(DestroyRef);
  private readonly i18n = inject(I18nService);
  protected readonly auth = inject(OpsAuthService);
  protected readonly format = inject(FormatService);

  protected readonly id = Number(this.route.snapshot.paramMap.get('applicationId'));

  protected readonly row = signal<Row | null>(null);
  protected readonly state = signal<'loading' | 'ready' | 'notFound' | 'denied' | 'failed'>('loading');
  /** A one-line answer when an action could not be opened (denied, not applicable). */
  protected readonly notice = signal<string>('');

  protected readonly tabs = TABS;
  protected readonly tab = signal<Tab>(this.tabFromUrl());

  /**
   * Where "back" goes. Only a path inside this app is honoured: a return
   * address that names another origin would make this page an open redirect.
   */
  protected readonly returnUrl: string | null = (() => {
    const wanted = this.route.snapshot.queryParamMap.get('returnUrl') ?? '';
    return wanted.startsWith('/') && !wanted.startsWith('//') ? wanted : null;
  })();

  // ---- derived from the row ----
  protected readonly status = computed(() => text(this.row() ?? {}, 'status'));
  protected readonly statusKey = computed(() => `${ENROLMENTS_SPEC.statusPrefix}${this.status()}`);
  protected readonly statusTone = computed(() => ENROLMENTS_SPEC.tone(this.status()));
  protected readonly next = computed(() => (this.row() ? nextStepFor(this.row() as Row) : null));
  protected readonly canNext = computed(() => {
    const step = this.next();
    const row = this.row();
    if (!step || !row) {
      return false;
    }
    if (step.actionType === null) {
      return !!step.link && this.auth.can(step.permission);
    }
    return this.dialogs.canOffer('enrolments', step.actionType, row);
  });
  protected readonly flags = computed(() => (this.row() ? flagsFor(this.row() as Row, new Date()) : []));
  protected readonly legalNext = computed(() => ENROLMENT_NEXT[this.status()] ?? []);
  protected readonly canChangeStatus = computed(
    () => !!this.row() && this.dialogs.canOffer('enrolments', 'status', this.row() as Row));
  protected readonly canConvert = computed(
    () => !!this.row() && this.dialogs.canOffer('enrolments', 'convert', this.row() as Row));
  protected readonly childId = computed(() => num(this.row() ?? {}, 'converted_child_id') || null);
  protected readonly guardianId = computed(() => num(this.row() ?? {}, 'converted_guardian_id') || null);
  protected readonly mobile = computed(() => text(this.row() ?? {}, 'parent_mobile'));
  protected readonly telHref = computed(() => (this.mobile() ? `tel:${this.mobile()}` : null));

  // ---- the child's parts, read once the family has a file and the tab is opened ----
  protected readonly appointments = signal<readonly Row[] | null>(null);
  protected readonly appointmentsState = signal<'idle' | 'loading' | 'ready' | 'failed'>('idle');
  protected readonly plans = signal<readonly Row[] | null>(null);
  protected readonly plansState = signal<'idle' | 'loading' | 'ready' | 'failed'>('idle');

  protected readonly latestAppointment = computed(() => {
    const rows = this.appointments() ?? [];
    return rows.length ? [...rows].sort((a, b) => text(b, 'starts_at').localeCompare(text(a, 'starts_at')))[0] : null;
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
  protected readonly activity = computed(
    () => (this.row() ? activityFor(this.row() as Row, this.appointments() ?? []) : []));

  protected readonly appointmentStatusKey = (row: Row) => `${APPOINTMENTS_SPEC.statusPrefix}${text(row, 'status')}`;
  protected readonly appointmentTone = (row: Row) => APPOINTMENTS_SPEC.tone(text(row, 'status'));

  constructor() {
    this.load();
  }

  protected load(): void {
    this.state.set('loading');
    this.notice.set('');
    this.day.get('enrolments', this.id)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (row) => {
          this.row.set(row);
          this.state.set('ready');
          this.loadChildParts();
          this.openDeepLink(row);
        },
        error: (error: unknown) => {
          const status = error instanceof HttpErrorResponse ? error.status : 0;
          this.state.set(status === 404 ? 'notFound' : status === 403 ? 'denied' : 'failed');
        },
      });
  }

  /** The child's appointments feed the overview and the timeline; the rest waits for its tab. */
  private loadChildParts(): void {
    if (this.childId() && this.appointmentsState() === 'idle') {
      this.loadAppointments();
    }
    if (this.tab() === 'recommendations') {
      this.loadPlans();
    }
  }

  protected loadAppointments(): void {
    const childId = this.childId();
    if (!childId) {
      return;
    }
    this.appointmentsState.set('loading');
    this.childApi.list(childId, 'appointments')
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (rows) => { this.appointments.set(rows); this.appointmentsState.set('ready'); },
        error: () => this.appointmentsState.set('failed'),
      });
  }

  protected loadPlans(): void {
    const childId = this.childId();
    if (!childId || this.plansState() === 'loading' || this.plansState() === 'ready') {
      return;
    }
    this.plansState.set('loading');
    this.childApi.list(childId, 'plans')
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (rows) => { this.plans.set(rows); this.plansState.set('ready'); },
        error: () => this.plansState.set('failed'),
      });
  }

  // ---- tabs ----

  private tabFromUrl(): Tab {
    const wanted = this.route.snapshot.queryParamMap.get('tab') as Tab | null;
    return wanted && TABS.includes(wanted) ? wanted : 'overview';
  }

  protected selectTab(tab: Tab): void {
    this.tab.set(tab);
    if (tab === 'recommendations') {
      this.loadPlans();
    }
    if (tab === 'appointments' && this.appointmentsState() === 'idle') {
      this.loadAppointments();
    }
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: { tab: tab === 'overview' ? null : tab },
      queryParamsHandling: 'merge',
      replaceUrl: true,
    });
  }

  // ---- actions: all through the service, all the list's own dialogs ----

  protected act(): void {
    const step = this.next();
    if (!step) {
      return;
    }
    if (step.actionType === null) {
      if (step.link) {
        void this.router.navigate(step.link as string[]);
      }
      return;
    }
    this.run(step.actionType, step.prefill, 'ENROLMENT_DETAIL');
  }

  protected changeStatus(): void {
    this.run('status', undefined, 'ENROLMENT_DETAIL');
  }

  protected convert(): void {
    this.run('convert', undefined, 'ENROLMENT_DETAIL');
  }

  private run(
    actionType: string, prefill: Readonly<Record<string, string>> | undefined,
    source: ActionRequest['source'],
  ): void {
    const row = this.row();
    if (!row) {
      return;
    }
    this.notice.set('');
    this.dialogs.open({
      actionType, entityType: 'enrolments', entityId: this.id, row, source, prefill,
      returnUrl: this.router.url,
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe((outcome) => this.settle(outcome));
  }

  private settle(outcome: ActionOutcome): void {
    if (outcome === 'DONE') {
      // The row moved; read it again rather than guess what it became.
      this.appointmentsState.set('idle');
      this.load();
      return;
    }
    if (outcome === 'DENIED' || outcome === 'NOT_APPLICABLE' || outcome === 'UNKNOWN_ACTION') {
      this.notice.set(`enrolment.notice.${outcome}`);
    }
  }

  /**
   * `?action=` from a task card or a message. Checked against the row's
   * status by the same table the dialog uses, and against the permission
   * by the service; then cleared from the address before anything opens,
   * so a reload lands on the page and not on the dialog again.
   */
  private openDeepLink(row: Row): void {
    const param = this.route.snapshot.queryParamMap.get('action');
    if (!param) {
      return;
    }
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: { action: null },
      queryParamsHandling: 'merge',
      replaceUrl: true,
    });
    const wanted = deepLinkRequest(param, row);
    if (!wanted) {
      this.notice.set('enrolment.notice.NOT_APPLICABLE');
      return;
    }
    this.run(wanted.actionType, wanted.prefill, 'DEEP_LINK');
  }

  // ---- navigation ----

  protected back(): void {
    if (this.returnUrl) {
      void this.router.navigateByUrl(this.returnUrl);
      return;
    }
    void this.router.navigate(['/enrolments'], { queryParams: { focus: this.id } });
  }

  // ---- display helpers (labels, never rules) ----

  protected val(key: string): string {
    return text(this.row() ?? {}, key);
  }

  protected has(key: string): boolean {
    return this.val(key) !== '';
  }

  protected age(): string {
    const born = this.val('child_birth_date');
    return born ? this.i18n.plural('child.age', this.format.ageYears(born)) : '';
  }

  protected labelled(prefix: string, key: string): string {
    const value = this.val(key);
    return value ? this.i18n.translate(`${prefix}${value}`) : '';
  }

  protected preferredService(): string {
    return ref(this.row() ?? {}, 'preferred_service', 'name_ar');
  }

  protected when(iso: string): string {
    return iso ? `${this.format.dayMonthYear(iso)} · ${this.format.time(iso)}` : '';
  }

  protected nested(row: Row, object: string, key: string): string {
    return ref(row, object, key);
  }

  protected planStatusKey(row: Row): string {
    return `status.plan.${text(row, 'status')}`;
  }
}
