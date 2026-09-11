import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  inject,
  signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Router } from '@angular/router';

import { PortalApi } from '../../core/api/portal-api';
import { loadErrorKey, traceIdFor } from '../../core/api/portal-error';
import { FormatService } from '@hbh/shared/format/format.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { NotificationFeed, PortalNotification } from '../../core/models/portal.models';
import { Icon, IconName } from '@hbh/shared/icon/icon';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';

/**
 * What the centre has told this family.
 *
 * The table behind this screen has existed since migration 0015 and seven
 * triggers have been filling it ever since - a report published, an
 * appointment booked or cancelled, an invoice issued, a request decided.
 * Until now NO ROUTE READ IT. The shell's own markup still carries the note
 * that the bell was removed because "there is no notifications feature to
 * open". This is that feature, and the first thing it does is surface
 * messages this family was sent months ago.
 *
 * WHAT THIS SCREEN IS NOT. It is not a second home screen. The attention list
 * on the welcome screen answers "what should I DO" - money owing, activities
 * unfinished - and is computed from live data. This answers "what HAPPENED",
 * from a log. The two look similar and are opposites: one is a to-do list
 * that shrinks when a family acts, the other is a history that never does.
 */
@Component({
  selector: 'hbh-notifications',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon, TranslatePipe, Skeleton, ErrorNote, EmptyState],
  templateUrl: './notifications.html',
  styleUrl: './notifications.css',
})
export class Notifications {
  private readonly api = inject(PortalApi);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  protected readonly format = inject(FormatService);

  protected readonly data = signal<NotificationFeed | null>(null);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);
  protected readonly failureKey = signal('error.load');
  protected readonly traceId = signal<string | null>(null);

  constructor() {
    this.load();
  }

  /**
   * ONE CALL, so there is no partial state to preserve and no Result
   * wrapping - which is C4's rule applied rather than ignored. The feed is
   * addressed to a person, not assembled per child, so a failure here means
   * the screen genuinely knows nothing.
   *
   * AND A FAILURE IS NOT AN EMPTY FEED. "We could not load these" and "you
   * have none" are different sentences, and the template says whichever is
   * true - C4's principle, which this screen would be the easiest place in
   * the app to break.
   */
  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    this.api.notifications(50)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (feed) => {
          this.data.set(feed);
          this.loading.set(false);
        },
        error: (error: unknown) => {
          this.loading.set(false);
          this.failed.set(true);
          this.failureKey.set(loadErrorKey(error));
          this.traceId.set(traceIdFor(error));
        },
      });
  }

  /**
   * Open one.
   *
   * THE NAVIGATION DOES NOT WAIT FOR THE MARK-READ. A parent tapping a report
   * wants the report; making them wait on a write that changes nothing they
   * can see would be latency spent on bookkeeping. The unread state is
   * updated locally at once so the badge is right, and the request is sent
   * behind it.
   *
   * IF THAT REQUEST FAILS, NOTHING IS SAID. The item stays read on this
   * screen and comes back unread on the next load, which is a cosmetic
   * inconsistency; an error toast about a read receipt, on top of a screen
   * the parent has already navigated away from, would be worse.
   */
  protected open(item: PortalNotification): void {
    this.markRead(item);
    if (item.target) {
      void this.router.navigate(item.target as string[]);
    }
  }

  protected markRead(item: PortalNotification): void {
    if (item.read) {
      return;
    }
    const feed = this.data();
    if (feed) {
      this.data.set({
        ...feed,
        rows: feed.rows.map((row) => row.id === item.id ? { ...row, read: true } : row),
        unread: Math.max(0, feed.unread - 1),
      });
    }
    this.api.markNotificationRead(item.id)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({ error: () => undefined });
  }

  /**
   * The icon says what KIND of thing happened, at a glance, down a list of
   * twenty. Every kind the schema can produce is named here - including the
   * staff ones, which a guardian never receives but which would otherwise
   * fall to a default and look like a defect if this screen were ever reused.
   */
  protected icon(item: PortalNotification): IconName {
    switch (item.kind) {
      case 'REPORT_PUBLISHED':
      case 'ASSESSMENT_PUBLISHED':
      case 'NOTE_PUBLISHED':
        return 'ic-file';
      case 'APPOINTMENT_BOOKED':
      case 'APPOINTMENT_RESCHEDULED':
      case 'APPOINTMENT_REMINDER':
        return 'ic-calendar';
      case 'APPOINTMENT_CANCELLED':
        return 'ic-warn';
      case 'INVOICE_ISSUED':
        return 'ic-receipt';
      case 'REQUEST_DECIDED':
        return 'ic-chat';
      case 'SESSION_STARTED':
        return 'ic-cast';
      default:
        return 'ic-info';
    }
  }

  /** Tint follows the icon: news, money, and the one that is bad news. */
  protected tint(item: PortalNotification): string {
    switch (item.kind) {
      case 'APPOINTMENT_CANCELLED':
        return 'hbh-t--amber';
      case 'INVOICE_ISSUED':
        return 'hbh-t--amber';
      case 'REPORT_PUBLISHED':
      case 'ASSESSMENT_PUBLISHED':
      case 'NOTE_PUBLISHED':
        return 'hbh-t--blue';
      default:
        return 'hbh-t--green';
    }
  }
}
