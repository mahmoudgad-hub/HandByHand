import { TablePages } from '@hbh/shared/ui/table-pages';
import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { HttpErrorResponse } from '@angular/common/http';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { catchError, forkJoin, map, of } from 'rxjs';

import { FormatService } from '@hbh/shared/format/format.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { Balance, ChildApi } from '../../core/api/child-api';
import { OpsApi, Row } from '../../core/api/ops-api';
import { readAllPages } from '../../core/api/read-all-pages';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { ActionDialogService } from '../../core/ops/action-dialog.service';
import { DayApi } from '../../core/ops/day-api';
import { APPOINTMENTS_SPEC, ENROLMENTS_SPEC, INVOICES_SPEC, REQUESTS_SPEC } from '../../core/ops/day-spec';
import { RecordDrawerService } from '../../core/ops/record-drawer.service';
import { nextStepFor } from '../enrolment/enrolment-detail.model';
import {
  ChildAppointment, activityFor, applicationsOf, nextAppointment, num, openApplications, ref,
  requestsOf, text,
} from './guardian-detail.model';

type Tab = 'overview' | 'beneficiaries' | 'applications' | 'appointments' | 'finance' | 'communication' | 'activity';

/**
 * One guardian, on their own page: who they are, their children, their
 * applications, their appointments, what they owe, how to reach them.
 *
 * Every read here is one the console already makes: the guardian row from
 * the CRUD, the children by `guardian_id` (the same read the guardians tab
 * used), the applications and requests from the queues, the children's
 * appointments and balances from the child endpoints. The service has no
 * "applications of guardian" read, so the complete queue is filtered by
 * the two keys the schema keeps. A failed page fails that part explicitly.
 *
 * Editing goes through the CRUD editor the guardians list uses, drawn here
 * by ActionDialogService. Nothing is written from this file.
 */
@Component({
  selector: 'hbh-guardian-detail',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [TablePages, RouterLink, Icon, TranslatePipe, Skeleton, ErrorNote, EmptyState],
  templateUrl: './guardian-detail.html',
  styleUrl: './guardian-detail.css',
})
export class GuardianDetail {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly crud = inject(OpsApi);
  private readonly day = inject(DayApi);
  private readonly childApi = inject(ChildApi);
  private readonly dialogs = inject(ActionDialogService);
  private readonly drawer = inject(RecordDrawerService);
  private readonly destroyRef = inject(DestroyRef);
  private readonly i18n = inject(I18nService);
  protected readonly auth = inject(OpsAuthService);
  protected readonly format = inject(FormatService);

  protected readonly id = Number(this.route.snapshot.paramMap.get('guardianId'));

  protected readonly guardian = signal<Row | null>(null);
  protected readonly state = signal<'loading' | 'ready' | 'notFound' | 'denied' | 'failed'>('loading');
  protected readonly notice = signal('');

  protected readonly tabs: readonly Tab[] = [
    'overview', 'beneficiaries', 'applications', 'appointments', 'finance', 'communication', 'activity',
  ];
  protected readonly tab = signal<Tab>(this.tabFromUrl());

  protected readonly returnUrl: string | null = (() => {
    const wanted = this.route.snapshot.queryParamMap.get('returnUrl') ?? '';
    return wanted.startsWith('/') && !wanted.startsWith('//') ? wanted : null;
  })();

  // ---- the family's rows: read with the header, once ----
  protected readonly children = signal<readonly Row[] | null>(null);
  protected readonly applications = signal<readonly Row[] | null>(null);
  protected readonly requests = signal<readonly Row[] | null>(null);
  protected readonly partsFailed = signal<readonly string[]>([]);

  // ---- lazy parts ----
  protected readonly appointments = signal<readonly ChildAppointment[] | null>(null);
  protected readonly appointmentsState = signal<'idle' | 'loading' | 'ready' | 'failed'>('idle');
  protected readonly balances = signal<readonly { child: Row; balance: Balance | null }[] | null>(null);
  protected readonly balancesState = signal<'idle' | 'loading' | 'ready' | 'failed'>('idle');
  /** The family's invoices, one child list each, newest first. */
  protected readonly invoices = signal<readonly { child: Row; row: Row }[] | null>(null);
  protected readonly invoicesState = signal<'idle' | 'loading' | 'ready' | 'failed'>('idle');

  // ---- derived ----
  protected readonly name = computed(() => text(this.guardian() ?? {}, 'full_name_ar'));
  protected readonly mobile = computed(() => text(this.guardian() ?? {}, 'mobile'));
  protected readonly telHref = computed(() => (this.mobile() ? `tel:${this.mobile()}` : null));
  protected readonly hasAccount = computed(() => text(this.guardian() ?? {}, 'user_id') !== '');
  protected readonly childCount = computed(() => this.children()?.length ?? null);
  protected readonly openApplications = computed(() => openApplications(this.applications() ?? []));
  protected readonly latestApplication = computed(() => {
    const rows = [...(this.applications() ?? [])];
    return rows.sort((a, b) => text(b, 'submitted_at').localeCompare(text(a, 'submitted_at')))[0] ?? null;
  });
  protected readonly nextAppointment = computed(
    () => nextAppointment(this.appointments() ?? [], new Date().toISOString()));
  protected readonly activity = computed(() => (this.guardian()
    ? activityFor(this.guardian() as Row, this.children() ?? [], this.applications() ?? [], this.requests() ?? [])
    : []));
  protected readonly canEdit = computed(() => this.dialogs.canWriteResource('guardians'));
  protected readonly canFinance = computed(() => this.auth.can('BILLING.VIEW'));
  protected readonly canMessage = computed(() => this.auth.can('REQUEST.MANAGE') && this.hasAccount());
  protected readonly totalOutstanding = computed(() => {
    const rows = this.balances() ?? [];
    let sum = 0; let currency = '';
    for (const item of rows) {
      if (item.balance) {
        sum += Number(item.balance.outstanding_amt) || 0;
        currency = item.balance.currency_code;
      }
    }
    return currency ? this.format.money(sum, currency) : '';
  });

  constructor() {
    this.load();
    // A record changed from the drawer beside this page: the part that
    // shows it is read again, and nothing else.
    this.drawer.changed$
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe((target) => {
        if (target.entity === 'appointment') {
          this.appointmentsState.set('idle');
          this.loadAppointments();
        } else {
          this.invoicesState.set('idle');
          this.balancesState.set('idle');
          if (this.tab() === 'finance') {
            this.loadInvoices();
            this.loadBalances();
          }
        }
      });
  }

  // ---- the record drawer, on a row this page already holds ----

  protected openAppointment(item: ChildAppointment): void {
    void this.drawer.open({
      entity: 'appointment', id: num(item.row, 'appointment_id'), row: item.row, source: 'GUARDIAN_DETAIL',
      context: { childId: item.childId, childName: item.childName },
    });
  }

  protected openInvoice(item: { child: Row; row: Row }): void {
    void this.drawer.open({
      entity: 'invoice', id: num(item.row, 'invoice_id'), row: item.row, source: 'GUARDIAN_DETAIL',
      context: {
        childId: num(item.child, 'child_id'),
        childName: text(item.child, 'full_name_ar'),
        childNo: text(item.child, 'child_no'),
      },
    });
  }

  protected load(): void {
    this.state.set('loading');
    this.notice.set('');
    this.crud.get('guardians', this.id)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (row) => {
          this.guardian.set(row);
          this.state.set('ready');
          this.loadParts(row);
        },
        error: (error: unknown) => {
          const status = error instanceof HttpErrorResponse ? error.status : 0;
          this.state.set(status === 404 ? 'notFound' : status === 403 ? 'denied' : 'failed');
        },
      });
  }

  /** Children, applications and requests arrive together; each failure is named, none hides the others. */
  private loadParts(guardian: Row): void {
    const failed: string[] = [];
    forkJoin({
      children: readAllPages((page) => this.crud.list('children', { guardian_id: this.id, limit: 100, page }))
        .pipe(catchError(() => { failed.push('children'); return of(null); })),
      applications: this.auth.can('ENROLMENT.MANAGE')
        ? readAllPages((page) => this.day.list('enrolments', { limit: 100, page }))
          .pipe(map((rows) => applicationsOf(guardian, rows)), catchError(() => { failed.push('applications'); return of(null); }))
        : of([] as readonly Row[]),
      requests: this.auth.can('REQUEST.MANAGE')
        ? readAllPages((page) => this.day.list('requests', { limit: 100, page }))
          .pipe(map((rows) => requestsOf(this.id, rows)), catchError(() => { failed.push('requests'); return of(null); }))
        : of([] as readonly Row[]),
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe((parts) => {
        this.children.set(parts.children);
        this.applications.set(parts.applications);
        this.requests.set(parts.requests);
        this.partsFailed.set(failed);
        // The overview shows the next appointment; a small family's diary
        // is cheap to read now, a large one waits for its tab.
        if ((parts.children?.length ?? 0) > 0 && (parts.children?.length ?? 0) <= 6) {
          this.loadAppointments();
        }
        if (this.tab() === 'finance') {
          this.loadBalances();
          this.loadInvoices();
        }
      });
  }

  protected loadAppointments(): void {
    const children = this.children() ?? [];
    if (!children.length || this.appointmentsState() === 'loading' || this.appointmentsState() === 'ready') {
      if (!children.length) {
        this.appointments.set([]);
        this.appointmentsState.set('ready');
      }
      return;
    }
    this.appointmentsState.set('loading');
    forkJoin(children.map((child) => this.childApi.list(num(child, 'child_id'), 'appointments').pipe(
      map((rows) => rows.map((row): ChildAppointment => ({
        childId: num(child, 'child_id'), childName: text(child, 'full_name_ar'), row,
      }))),
    )))
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (lists) => {
          this.appointments.set(lists.flat().sort((a, b) => text(b.row, 'starts_at').localeCompare(text(a.row, 'starts_at'))));
          this.appointmentsState.set('ready');
        },
        error: () => this.appointmentsState.set('failed'),
      });
  }

  protected loadBalances(): void {
    const children = this.children() ?? [];
    if (!this.canFinance() || this.balancesState() === 'loading' || this.balancesState() === 'ready') {
      return;
    }
    if (!children.length) {
      this.balances.set([]);
      this.balancesState.set('ready');
      return;
    }
    this.balancesState.set('loading');
    forkJoin(children.map((child) => this.childApi.balance(num(child, 'child_id')).pipe(
      map((balance) => ({ child, balance: balance as Balance | null })),
      catchError(() => of({ child, balance: null })),
    )))
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (rows) => { this.balances.set(rows); this.balancesState.set('ready'); },
        error: () => this.balancesState.set('failed'),
      });
  }

  /** The family's invoices, from each child's own list - the same read the child's file makes. */
  protected loadInvoices(): void {
    const children = this.children() ?? [];
    if (!this.canFinance() || this.invoicesState() === 'loading' || this.invoicesState() === 'ready') {
      return;
    }
    if (!children.length) {
      this.invoices.set([]);
      this.invoicesState.set('ready');
      return;
    }
    this.invoicesState.set('loading');
    forkJoin(children.map((child) => this.childApi.list(num(child, 'child_id'), 'invoices').pipe(
      map((rows) => rows.map((row) => ({ child, row }))),
    )))
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (lists) => {
          this.invoices.set(lists.flat()
            .sort((a, b) => text(b.row, 'issue_date').localeCompare(text(a.row, 'issue_date'))));
          this.invoicesState.set('ready');
        },
        error: () => this.invoicesState.set('failed'),
      });
  }

  protected invoiceStatusKey(row: Row): string {
    return `${INVOICES_SPEC.statusPrefix}${text(row, 'status')}`;
  }

  protected invoiceTone(row: Row): string {
    return INVOICES_SPEC.tone(text(row, 'status'));
  }

  // ---- tabs ----

  private tabFromUrl(): Tab {
    const wanted = this.route.snapshot.queryParamMap.get('tab') as Tab | null;
    return wanted && this.tabs?.includes(wanted) ? wanted : 'overview';
  }

  protected selectTab(tab: Tab): void {
    this.tab.set(tab);
    if (tab === 'appointments') {
      this.loadAppointments();
    }
    if (tab === 'finance') {
      this.loadBalances();
      this.loadInvoices();
    }
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: { tab: tab === 'overview' ? null : tab },
      queryParamsHandling: 'merge',
      replaceUrl: true,
    });
  }

  // ---- actions ----

  /** The guardians list's own editor, on this row. */
  protected edit(): void {
    const row = this.guardian();
    if (!row) {
      return;
    }
    this.dialogs.openResource({ resource: 'guardians', mode: 'edit', row, source: 'GUARDIAN_DETAIL' })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe((outcome) => {
        if (outcome === 'DONE') {
          this.load();
        } else if (outcome === 'DENIED') {
          this.notice.set('enrolment.notice.DENIED');
        }
      });
  }

  protected back(): void {
    if (this.returnUrl) {
      void this.router.navigateByUrl(this.returnUrl);
      return;
    }
    void this.router.navigate(['/guardians']);
  }

  // ---- display helpers ----

  protected val(key: string): string {
    return text(this.guardian() ?? {}, key);
  }

  protected has(key: string): boolean {
    return this.val(key) !== '';
  }

  protected when(iso: string): string {
    return iso ? `${this.format.dayMonthYear(iso)} · ${this.format.time(iso)}` : '';
  }

  protected day$(iso: string): string {
    return iso ? this.format.dayMonthYear(iso) : '';
  }

  protected ageOf(child: Row): string {
    const born = text(child, 'birth_date');
    return born ? this.i18n.plural('child.age', this.format.ageYears(born)) : '';
  }

  protected childStatusKey(child: Row): string {
    const value = text(child, 'status');
    return value ? `status.child.${value}` : '';
  }

  protected appStatusKey(app: Row): string {
    return `${ENROLMENTS_SPEC.statusPrefix}${text(app, 'status')}`;
  }

  protected appTone(app: Row): string {
    return ENROLMENTS_SPEC.tone(text(app, 'status'));
  }

  protected appNextKey(app: Row): string {
    return nextStepFor(app)?.descriptionKey ?? 'enrolment.nextNone';
  }

  protected apptStatusKey(row: Row): string {
    return `${APPOINTMENTS_SPEC.statusPrefix}${text(row, 'status')}`;
  }

  protected apptTone(row: Row): string {
    return APPOINTMENTS_SPEC.tone(text(row, 'status'));
  }

  protected reqStatusKey(row: Row): string {
    return `${REQUESTS_SPEC.statusPrefix}${text(row, 'status')}`;
  }

  protected reqTone(row: Row): string {
    return REQUESTS_SPEC.tone(text(row, 'status'));
  }

  protected reqKindKey(row: Row): string {
    return `kind.request.${text(row, 'kind_code')}`;
  }

  protected nested(row: Row, object: string, key: string): string {
    return ref(row, object, key);
  }

  protected childId(row: Row): number {
    return num(row, 'child_id');
  }

  protected appId(row: Row): number {
    return num(row, 'application_id');
  }

  protected money(balance: Balance | null): string {
    return balance ? this.format.money(Number(balance.outstanding_amt), balance.currency_code) : '—';
  }
}
