import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { forkJoin, catchError, of } from 'rxjs';

import { FormatService } from '@hbh/shared/format/format.service';
import { HbhPluralPipe } from '@hbh/shared/format/format.pipes';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { Row } from '../../core/api/ops-api';
import { Balance, ChildApi, ChildPart } from '../../core/api/child-api';
import { OpsAuthService } from '../../core/auth/ops-auth.service';

/** One tab: a list of the child's rows, with the columns that list needs. */
interface Tab {
  readonly part: ChildPart;
  readonly labelKey: string;
  readonly columns: readonly {
    readonly key: string;
    readonly labelKey: string;
    readonly read: (row: Row) => string;
    readonly ltr?: boolean;
  }[];
  readonly statusPrefix?: string;
}

/**
 * One child's file.
 *
 * The console had no such screen at all until now: the children list showed
 * rows and clicking one led nowhere, so a receptionist with a parent on the
 * phone had to open five screens and filter each by hand.
 *
 * It reads only, and that is on purpose rather than unfinished. Every verb
 * this file's contents accept - booking, closing, publishing, taking a
 * payment - already lives on the screen that owns it, with the state machine
 * and the permission drawn around it. A second copy of those buttons here
 * would be a second place for them to drift out of step, and the one that
 * checked less would be the one people used.
 */
@Component({
  selector: 'hbh-child-profile',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Icon, TranslatePipe, HbhPluralPipe, Skeleton, EmptyState, ErrorNote],
  templateUrl: './child-profile.html',
  styleUrl: './child-profile.css',
})
export class ChildProfile {
  private readonly api = inject(ChildApi);
  private readonly route = inject(ActivatedRoute);
  /** Only decides whether the "create report" button is drawn. */
  protected readonly auth = inject(OpsAuthService);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  private readonly i18n = inject(I18nService);
  protected readonly format = inject(FormatService);

  protected readonly childId = Number(this.route.snapshot.paramMap.get('childId'));

  protected readonly child = signal<Row | null>(null);
  protected readonly balance = signal<Balance | null>(null);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);

  protected readonly rows = signal<readonly Row[]>([]);
  protected readonly rowsLoading = signal(true);
  protected readonly rowsFailed = signal(false);

  protected readonly tabIndex = signal(0);
  protected readonly overview = signal(true);
  protected readonly summary = signal<Record<string, readonly Row[] | null>>({});
  protected textValue(row: Row, key: string): string { return ChildProfile.text(row, key); }
  protected openOverview(): void { this.overview.set(true); }
  private loadOverview(): void {
    for (const part of ['guardians', 'sessions', 'plans', 'reports'] as const) {
      this.api.list(this.childId, part).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
        next: rows => this.summary.update(value => ({...value, [part]: rows})),
        error: () => this.summary.update(value => ({...value, [part]: null})),
      });
    }
  }

  /** The note currently being sent, so its button cannot be pressed twice. */
  protected readonly publishing = signal<number | null>(null);

  protected noteId(row: Row): number {
    return Number(ChildProfile.text(row, 'note_id'));
  }

  protected isInternal(row: Row): boolean {
    return ChildProfile.text(row, 'visibility') === 'INTERNAL';
  }

  /**
   * Send one note to the family.
   *
   * This file says elsewhere that a row's action belongs on the screen that
   * owns it, and that a second copy here would be a second place to drift.
   * A note has no such screen: it is written from the session and listed
   * nowhere but this tab, so this is the only copy, not the second one - and
   * without it the whole ladder had no top and a clinician could write a note
   * for a family and never send it.
   *
   * Whether the caller may is decided by hbh.publish_session_note. The button
   * is shown for an internal note and the service refuses anyone lacking
   * NOTE.PUBLISH; hiding it would be a courtesy, never the control.
   */
  protected guardianId(row: Row): number {
    return Number(ChildProfile.text(row, 'guardian_id'));
  }

  protected canViewLive(row: Row): boolean {
    return ChildProfile.text(row, 'can_view_live') === 'true';
  }

  /**
   * Record or withdraw this guardian's consent to watch their child live.
   *
   * The flag is not set here and never should be: hbh.grant_consent raises it
   * and hbh.withdraw_consent drops it, so the consent and the permission can
   * never disagree. A screen that wrote the flag directly would be refused by
   * trg_live_flag_needs_consent anyway - which is the rule working.
   */
  protected toggleLiveConsent(row: Row): void {
    const guardian = this.guardianId(row);
    if (!guardian || this.publishing() !== null) {
      return;
    }
    this.publishing.set(guardian);
    const call = this.canViewLive(row)
      ? this.api.withdrawConsent(guardian, 'LIVE_VIEW', this.childId)
      : this.api.grantConsent(guardian, 'LIVE_VIEW', this.childId);
    call.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: () => {
        this.publishing.set(null);
        this.loadTab();
      },
      error: () => this.publishing.set(null),
    });
  }

  protected publish(row: Row): void {
    const id = this.noteId(row);
    if (!id || this.publishing() !== null) {
      return;
    }
    this.publishing.set(id);
    this.api.publishNote(id)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.publishing.set(null);
          this.loadTab();
        },
        error: () => this.publishing.set(null),
      });
  }

  /**
   * Read straight from the row, as text. The child endpoints are the ones
   * the portal already runs on, so the shapes here are settled.
   */
  /**
   * A period, including the open-ended one.
   *
   * It used to read `from && to ? … : ''`, so a plan with no end date - which
   * is what a plan that is still running looks like - showed an EMPTY cell.
   * The most ordinary state of the most important row rendered as nothing,
   * and read as missing data rather than as "still running".
   *
   * Four shapes, and each says what it means: both ends, a start with no end,
   * an end with no start (a data fault worth seeing rather than hiding), and
   * genuinely nothing.
   */
  private period(from: string, to: string): string {
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

  private static text(row: Row, key: string): string {
    const value = row[key];
    return value === null || value === undefined ? '' : String(value);
  }

  private static ref(row: Row, group: string, key: string): string {
    const nested = row[group] as Record<string, unknown> | undefined | null;
    const value = nested?.[key];
    return value === null || value === undefined ? '' : String(value);
  }

  protected readonly tabs: readonly Tab[] = [
    {
      part: 'appointments', labelKey: 'child.tab.appointments',
      statusPrefix: 'status.appointment.',
      columns: [
        // EVERY DATE ON THIS SCREEN CARRIES ITS YEAR, and that is the whole
        // point of the screen: it is a child's history, and a history spans
        // years. A plan from 2025 and a plan from 2026 read identically
        // without one; so did two measurements twelve months apart, and an
        // invoice issued last spring.
        //
        // They all called shortDate - day and month - which is right for a
        // row inside today's list, where the year is today's and repeating it
        // is noise. It is wrong the moment the list is a record rather than a
        // day. The formatter for this case already existed and says so in its
        // own comment: "for a date whose year matters and whose weekday does
        // not".
        {
          key: 'when', labelKey: 'field.time', ltr: true,
          read: (row) => {
            const from = ChildProfile.text(row, 'starts_at');
            return from ? `${this.format.dayMonthYear(from)} · ${this.format.time(from)}` : '';
          },
        },
        { key: 'service', labelKey: 'field.service', read: (row) => ChildProfile.ref(row, 'service', 'name_ar') },
        { key: 'therapist', labelKey: 'field.therapist', read: (row) => ChildProfile.ref(row, 'therapist', 'full_name_ar') },
        { key: 'room', labelKey: 'field.room', read: (row) => ChildProfile.ref(row, 'room', 'name_ar') },
      ],
    },
    {
      part: 'sessions', labelKey: 'child.tab.sessions',
      statusPrefix: 'status.session.',
      columns: [
        {
          key: 'when', labelKey: 'field.startedAt', ltr: true,
          read: (row) => {
            const at = ChildProfile.text(row, 'started_at');
            return at ? `${this.format.dayMonthYear(at)} · ${this.format.time(at)}` : '';
          },
        },
        { key: 'service', labelKey: 'field.service', read: (row) => ChildProfile.ref(row, 'service', 'name_ar') },
        { key: 'therapist', labelKey: 'field.therapist', read: (row) => ChildProfile.ref(row, 'therapist', 'full_name_ar') },
      ],
    },
    {
      part: 'plans', labelKey: 'child.tab.plans',
      statusPrefix: 'status.plan.',
      columns: [
        { key: 'title', labelKey: 'field.title', read: (row) => ChildProfile.text(row, 'title_ar') },
        {
          key: 'period', labelKey: 'field.period',
          read: (row) => this.period(
            ChildProfile.text(row, 'start_date'), ChildProfile.text(row, 'end_date')),
        },
        { key: 'therapist', labelKey: 'field.therapist', read: (row) => ChildProfile.ref(row, 'therapist', 'full_name_ar') },
        {
          key: 'goals', labelKey: 'field.goals', ltr: true,
          read: (row) => {
            const goals = row['goals'];
            return Array.isArray(goals) ? this.format.count(goals.length) : '';
          },
        },
      ],
    },
    {
      part: 'reports', labelKey: 'child.tab.reports',
      statusPrefix: 'status.report.',
      columns: [
        { key: 'no', labelKey: 'field.reportNo', read: (row) => ChildProfile.text(row, 'report_no'), ltr: true },
        { key: 'title', labelKey: 'field.title', read: (row) => ChildProfile.text(row, 'title_ar') },
        {
          key: 'period', labelKey: 'field.period',
          read: (row) => this.period(
            ChildProfile.text(row, 'period_start'), ChildProfile.text(row, 'period_end')),
        },
      ],
    },
    {
      part: 'packages', labelKey: 'child.tab.packages',
      statusPrefix: 'status.package.',
      columns: [
        { key: 'name', labelKey: 'field.name', read: (row) => ChildProfile.text(row, 'name_ar') },
        {
          key: 'left', labelKey: 'field.sessionsLeft', ltr: true,
          // Used of total, together. "3" alone does not say whether that is
          // most of the package or the end of it.
          read: (row) => `${ChildProfile.text(row, 'sessions_left')} / ${ChildProfile.text(row, 'sessions_total')}`,
        },
        {
          key: 'expires', labelKey: 'field.expiresOn',
          read: (row) => {
            const day = ChildProfile.text(row, 'expires_on');
            return day ? this.format.dayMonthYear(day) : '';
          },
        },
      ],
    },
    {
      part: 'invoices', labelKey: 'child.tab.invoices',
      statusPrefix: 'status.invoice.',
      columns: [
        { key: 'no', labelKey: 'field.invoiceNo', read: (row) => ChildProfile.text(row, 'invoice_no'), ltr: true },
        {
          key: 'issue', labelKey: 'field.issueDate',
          read: (row) => {
            const day = ChildProfile.text(row, 'issue_date');
            return day ? this.format.dayMonthYear(day) : '';
          },
        },
        {
          key: 'total', labelKey: 'field.total', ltr: true,
          read: (row) => this.format.money(
            Number(ChildProfile.text(row, 'total_amt')),
            ChildProfile.text(row, 'currency_code') || undefined),
        },
        {
          key: 'paid', labelKey: 'field.paid', ltr: true,
          read: (row) => this.format.money(
            Number(ChildProfile.text(row, 'paid_amt')),
            ChildProfile.text(row, 'currency_code') || undefined),
        },
      ],
    },
    {
      part: 'notes', labelKey: 'child.tab.notes',
      columns: [
        {
          key: 'when', labelKey: 'field.createdAt',
          read: (row) => {
            const at = ChildProfile.text(row, 'created_at');
            return at ? this.format.dayMonthYear(at) : '';
          },
        },
        // Who can read this. Without it the internal note and the published
        // one arrive on screen looking identical, and the person deciding
        // whether to send a note cannot tell which ones the family already
        // has. The service now returns visibility for exactly this reason.
        {
          key: 'visibility', labelKey: 'field.visibility',
          read: (row) => {
            const value = ChildProfile.text(row, 'visibility');
            return value ? this.i18n.translate(`note.visibility.${value}`) : '';
          },
        },
        { key: 'body', labelKey: 'field.note', read: (row) => ChildProfile.text(row, 'body_ar') },
      ],
    },
    {
      // The household, and what each of them has consented to. Live viewing
      // is the flag here because it is the one the schema refuses to raise
      // without a consent on file - and the only place that consent can now
      // be recorded through the product rather than at the database.
      part: 'guardians', labelKey: 'child.tab.guardians',
      columns: [
        { key: 'name', labelKey: 'field.name', read: (row) => ChildProfile.text(row, 'full_name_ar') },
        {
          key: 'relationship', labelKey: 'field.relationship',
          read: (row) => {
            const code = ChildProfile.text(row, 'relationship_code');
            return code ? this.i18n.translate(`relationship.${code}`) : '';
          },
        },
        { key: 'mobile', labelKey: 'field.mobile', ltr: true, read: (row) => ChildProfile.text(row, 'mobile') },
        {
          key: 'live', labelKey: 'consent.liveView',
          read: (row) => this.i18n.translate(
            ChildProfile.text(row, 'can_view_live') === 'true' ? 'answer.yes' : 'answer.no'),
        },
      ],
    },
    {
      // What the family actually did at home. The service has answered this
      // all along and no screen asked: a therapist set homework, the parent
      // ticked it off, and nobody at the centre could see that they had.
      part: 'activity-log', labelKey: 'child.tab.activityLog',
      columns: [
        {
          key: 'when', labelKey: 'field.date',
          read: (row) => {
            const at = ChildProfile.text(row, 'log_date') || ChildProfile.text(row, 'created_at');
            return at ? this.format.dayMonthYear(at) : '';
          },
        },
        { key: 'activity', labelKey: 'field.activity', read: (row) => ChildProfile.text(row, 'title_ar') },
        {
          key: 'done', labelKey: 'field.done',
          read: (row) => this.i18n.translate(
            ChildProfile.text(row, 'done_flg') === 'false' ? 'answer.no' : 'answer.yes'),
        },
        { key: 'note', labelKey: 'field.note', read: (row) => ChildProfile.text(row, 'note_ar') },
      ],
    },
  ];

  protected readonly tab = computed(() => this.tabs[this.tabIndex()]);

  protected readonly name = computed(() => ChildProfile.text(this.child() ?? {}, 'full_name_ar'));
  protected readonly childNo = computed(() => ChildProfile.text(this.child() ?? {}, 'child_no'));

  /** The age in years, worded. A birth date makes the reader do the sum. */
  protected readonly age = computed(() => {
    const born = ChildProfile.text(this.child() ?? {}, 'birth_date');
    return born ? this.i18n.plural('child.age', this.format.ageYears(born)) : '';
  });

  protected readonly genderKey = computed(() => {
    const value = ChildProfile.text(this.child() ?? {}, 'gender');
    return value ? `gender.${value}` : '';
  });

  protected readonly statusKey = computed(() => {
    const value = ChildProfile.text(this.child() ?? {}, 'status');
    return value ? `status.child.${value}` : '';
  });

  /**
   * Archived means the service set active_flg false. Checked for `false`
   * rather than for falsiness: the flag is absent from some projections, and
   * an absent flag is "not known" - which must not strike out a live child.
   */
  protected readonly isArchived = computed(() => this.child()?.['active_flg'] === false);

  protected readonly outstanding = computed(() => {
    const balance = this.balance();
    return balance ? this.format.money(Number(balance.outstanding_amt), balance.currency_code) : '';
  });

  constructor() {
    this.load();
    this.loadTab();
  }

  protected load(): void {
    this.loadOverview();
    this.loading.set(true);
    this.failed.set(false);
    // Both, together. Two separate spinners on one header make the page
    // reflow twice while somebody is reading it.
    forkJoin({
      child: this.api.child(this.childId),
      balance: this.api.balance(this.childId).pipe(catchError(() => of(null))),
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.child.set(result.child);
          this.balance.set(result.balance);
          this.loading.set(false);
        },
        error: () => {
          this.loading.set(false);
          this.failed.set(true);
        },
      });
  }

  protected selectTab(index: number): void {
    this.overview.set(false);
    if (index === this.tabIndex()) {
      return;
    }
    this.tabIndex.set(index);
    this.loadTab();
  }

  protected loadTab(): void {
    this.rowsLoading.set(true);
    this.rowsFailed.set(false);
    this.api.list(this.childId, this.tab().part)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (rows) => {
          this.rows.set(rows);
          this.rowsLoading.set(false);
        },
        error: () => {
          this.rowsLoading.set(false);
          this.rowsFailed.set(true);
        },
      });
  }

  protected cell(row: Row, column: Tab['columns'][number]): string {
    return column.read(row);
  }

  protected rowStatusKey(row: Row): string {
    const prefix = this.tab().statusPrefix;
    const value = ChildProfile.text(row, 'status');
    return prefix && value ? `${prefix}${value}` : '';
  }

  protected rowKey(row: Row, index: number): string {
    for (const key of [
      'appointment_id', 'session_id', 'plan_id', 'report_id',
      'child_package_id', 'invoice_id', 'note_id',
    ]) {
      if (row[key] !== undefined) {
        return String(row[key]);
      }
    }
    return String(index);
  }

  protected back(): void {
    void this.router.navigate(['/children']);
  }
}
