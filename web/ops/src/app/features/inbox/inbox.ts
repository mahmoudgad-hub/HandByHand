import {
  ChangeDetectionStrategy, Component, DestroyRef, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Router } from '@angular/router';

import { FormatService } from '@hbh/shared/format/format.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon, IconName } from '@hbh/shared/icon/icon';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { Inbox as Feed, InboxApi, InboxItem } from '../../core/api/inbox-api';

/**
 * What the centre has told THIS member of staff, and what it needs from them.
 *
 * The table has been filling since migration 0015 and the staff triggers
 * since 0089 - a child assigned to a caseload, an appointment booked into
 * somebody's day, a parent request waiting on reception. NO SCREEN IN THIS
 * CONSOLE EVER READ THEM. The rows were written correctly, addressed to the
 * right person, and seen by nobody: the parent portal had a feed and this
 * side did not.
 *
 * IT IS ADDRESSED, NOT BROADCAST. The policy on hbh.notifications is
 * `user_id = hbh.current_user_id()`, so every row here was sent to the
 * person reading it. There is no parameter for whose inbox to open, and
 * adding one would turn a private list into a directory.
 *
 * WHAT IT IS NOT: a dashboard. A dashboard answers "how is the centre",
 * computed live from data that changes under it. This is a LOG of things
 * that happened, addressed to one person, and it never recomputes. The two
 * look alike on screen and behave as opposites - one shrinks when the work
 * is done, the other only grows. Mixing them is how a to-do list starts
 * lying about what is still outstanding.
 *
 * AND EVERY ITEM THAT CAN LEAD SOMEWHERE, DOES. A message that names a
 * child and cannot open them is a task with the doing removed. The rows
 * already carry link_kind and link_id; inbox-api turns them into routes.
 */
@Component({
  selector: 'hbh-inbox',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon, TranslatePipe, Skeleton, ErrorNote, EmptyState],
  templateUrl: './inbox.html',
  styleUrl: './inbox.css',
})
export class Inbox {
  private readonly api = inject(InboxApi);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  protected readonly format = inject(FormatService);

  protected readonly data = signal<Feed | null>(null);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);

  /** Unread only, off by default: the whole list is the honest default. */
  protected readonly unreadOnly = signal(false);

  constructor() {
    this.load();
  }

  /**
   * One call, so there is no half-loaded state to reason about.
   *
   * AND A FAILURE IS NOT AN EMPTY INBOX. "We could not load these" and "you
   * have nothing" are different sentences, and a screen that prints the
   * second when it means the first tells somebody their work is done.
   */
  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    this.api.list(50)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (feed) => {
          this.data.set(feed);
          this.loading.set(false);
        },
        error: () => {
          this.loading.set(false);
          this.failed.set(true);
        },
      });
  }

  protected rows(): readonly InboxItem[] {
    const feed = this.data();
    if (!feed) {
      return [];
    }
    return this.unreadOnly() ? feed.rows.filter((row) => !row.read) : feed.rows;
  }

  protected toggleUnread(): void {
    this.unreadOnly.update((value) => !value);
  }

  /**
   * Open one.
   *
   * THE NAVIGATION DOES NOT WAIT FOR THE MARK-READ. Somebody clicking a
   * child wants the child; waiting on a write that changes nothing they can
   * see is latency spent on bookkeeping. The unread count is corrected here
   * at once, and the request follows.
   *
   * IF THAT WRITE FAILS, NOTHING IS SAID. The item reads as read now and
   * comes back unread on the next load - a cosmetic inconsistency. An error
   * about a read receipt, shown over a screen the person has already left,
   * would be worse than the inconsistency.
   */
  protected open(item: InboxItem): void {
    this.markRead(item);
    if (item.target) {
      void this.router.navigate(item.target as string[]);
    }
  }

  protected markRead(item: InboxItem): void {
    if (item.read) {
      return;
    }
    const feed = this.data();
    if (feed) {
      this.data.set({
        ...feed,
        unread: Math.max(0, feed.unread - 1),
        rows: feed.rows.map((row) => row.id === item.id ? { ...row, read: true } : row),
      });
    }
    this.api.markRead(item.id)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({ next: () => undefined, error: () => undefined });
  }

  /**
   * An icon per kind, and a plain one for a kind this build has not met.
   *
   * Falling back rather than failing: a notification the console does not
   * recognise is still a message somebody was sent, and hiding it because
   * its picture is unknown would lose the only copy they get.
   */
  protected icon(item: InboxItem): IconName {
    const byKind: Record<string, IconName> = {
      STAFF_CHILD_ASSIGNED: 'ic-user',
      STAFF_APPOINTMENT_BOOKED: 'ic-calendar',
      STAFF_REQUEST_NEW: 'ic-chat',
      REPORT_PUBLISHED: 'ic-file',
      INVOICE_ISSUED: 'ic-receipt',
      NOTE_PUBLISHED: 'ic-file',
      APPOINTMENT_BOOKED: 'ic-calendar',
    };
    return byKind[item.kind] ?? 'ic-bell';
  }
}
