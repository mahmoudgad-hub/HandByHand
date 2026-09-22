import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  inject,
  signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Router, RouterLink } from '@angular/router';

import { PortalApi } from '../../core/api/portal-api';
import { loadErrorKey, traceIdFor } from '../../core/api/portal-error';
import { ChildContextService } from '../../core/auth/child-context.service';
import { FormatService } from '@hbh/shared/format/format.service';
import { HbhMoneyPipe, HbhNumberPipe } from '@hbh/shared/format/format.pipes';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { AppointmentSummary, AttentionItem, Child, HomeSummary } from '../../core/models/portal.models';
import { attentionIcon, attentionTarget, attentionTint } from '../welcome/attention';
import { Icon } from '@hbh/shared/icon/icon';
import { AppointmentRow } from '../../shared/ui/appointment-row';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';

/**
 * The child's dashboard. Everything on it answers one of three questions a
 * parent actually arrives with: when is the next session, can I watch now,
 * and is anything waiting for me.
 *
 * The live button is paint. Whether the stream opens is decided when the
 * ticket is requested on the next screen, against the guardian's link to the
 * child, the live consent, and the session actually being in progress.
 */
@Component({
  selector: 'hbh-home',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    RouterLink, Icon, TranslatePipe, HbhNumberPipe, HbhMoneyPipe,
    AppointmentRow, Skeleton, ErrorNote,
  ],
  templateUrl: './home.html',
})
export class Home {
  private readonly api = inject(PortalApi);
  private readonly childContext = inject(ChildContextService);
  private readonly destroyRef = inject(DestroyRef);
  private readonly router = inject(Router);
  private readonly i18n = inject(I18nService);
  protected readonly format = inject(FormatService);

  protected readonly child = this.childContext.selected;

  /**
   * What is waiting for the FAMILY - every child at once - from the same
   * read the welcome screen makes. It lives here because this is the page
   * a parent opens every day; the welcome screen is the door, seen once.
   * A failure here draws nothing: the list is a convenience over screens
   * that each say what they hold.
   */
  protected readonly attention = signal<readonly AttentionItem[]>([]);
  private readonly family = signal<readonly Child[]>([]);
  protected readonly data = signal<HomeSummary | null>(null);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);
  protected readonly failureKey = signal('error.load');
  /** Shown only where nobody can act on the failure. */
  protected readonly traceId = signal<string | null>(null);

  constructor() {
    this.load();
  }

  /**
   * Which child this screen is currently loading for.
   *
   * A family with three children taps through them faster than the requests
   * come back, and `home()` is six calls deep - so child A's answer can land
   * after child B has been chosen and paint A's appointments, A's balance and
   * A's therapist under B's name. Nothing about the screen would look wrong.
   *
   * The id is the version, so a late answer is discarded by identity rather
   * than by a counter that happens to agree. takeUntilDestroyed covers the
   * component being torn down; this covers it being REUSED, which is what
   * switching child does.
   */
  private loadingFor: string | null = null;

  protected load(): void {
    this.loadAttention();
    const wanted = this.childContext.requireId();
    this.loadingFor = wanted;
    this.loading.set(true);
    this.failed.set(false);
    this.api.home(wanted)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (summary) => {
          if (this.loadingFor !== wanted) { return; }
          this.data.set(summary);
          this.loading.set(false);
        },
        // The refusal names itself. Showing "could not load" for a wrong
        // filter invites a retry that will be refused identically forever.
        error: (error: unknown) => {
          if (this.loadingFor !== wanted) { return; }
          this.loading.set(false);
          this.failed.set(true);
          this.failureKey.set(loadErrorKey(error));
          this.traceId.set(traceIdFor(error));
        },
      });
  }

  private loadAttention(): void {
    this.api.welcome()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (summary) => {
          this.attention.set(summary.attention);
          this.family.set(summary.children);
        },
        error: () => this.attention.set([]),
      });
  }

  protected attentionIcon = attentionIcon;
  protected attentionTint = attentionTint;

  /** The second line: money through the formatter with its currency, a count through the plural rules. */
  protected attentionDetail(item: AttentionItem): string {
    if (item.amount !== null) {
      return this.format.money(item.amount, item.currency ?? undefined);
    }
    if (item.count !== null) {
      return this.i18n.plural('attention.openActivities', item.count);
    }
    return '';
  }

  /**
   * Opens the item where it is dealt with. A report or an activity belongs
   * to one child, so that child is chosen first - the same switch the
   * header offers - and the family-wide screens need no child at all.
   */
  protected openAttention(item: AttentionItem): void {
    const target = attentionTarget(item);
    if (item.childId && item.childId !== this.child()?.id) {
      const next = this.family().find((candidate) => candidate.id === item.childId);
      if (next) {
        this.childContext.select(next);
      } else if (target.needsChild) {
        return;
      }
    }
    void this.router.navigate([target.path], { queryParams: target.query ?? {} });
  }

  /**
   * "today" reads better than the date when it is today, and the full date
   * reads better when it is not. Both forms live in the bundle, so neither
   * the word nor the separator is written in a template.
   */
  protected whenLabel(appointment: AppointmentSummary): string {
    return this.format.isToday(appointment.startsAt)
      ? this.i18n.translate('date.todayOn',
          { date: this.format.shortDate(appointment.startsAt) })
      : this.format.fullDate(appointment.startsAt);
  }
}
