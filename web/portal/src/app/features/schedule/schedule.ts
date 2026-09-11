import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  computed,
  inject,
  signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { RouterLink } from '@angular/router';

import { PortalApi } from '../../core/api/portal-api';
import { loadErrorKey, traceIdFor } from '../../core/api/portal-error';
import { ChildContextService } from '../../core/auth/child-context.service';
import { FormatService } from '@hbh/shared/format/format.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { AppointmentSummary } from '../../core/models/portal.models';
import { Icon } from '@hbh/shared/icon/icon';
import { AppointmentRow } from '../../shared/ui/appointment-row';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';

type Scope = 'upcoming' | 'past';

interface Group {
  readonly label: string;
  readonly items: readonly AppointmentSummary[];
}

/**
 * The child's appointments, upcoming and past.
 *
 * Read only. A parent cannot move a session from here, because moving one
 * depends on a therapist and a room being free, and that decision belongs to
 * reception. What this screen offers instead is a request, which reception
 * accepts or declines - the appointment's own state machine is what moves it.
 */
@Component({
  selector: 'hbh-schedule',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    RouterLink, Icon, TranslatePipe, AppointmentRow,
    Skeleton, EmptyState, ErrorNote,
  ],
  templateUrl: './schedule.html',
})
export class Schedule {
  private readonly api = inject(PortalApi);
  private readonly childContext = inject(ChildContextService);
  private readonly destroyRef = inject(DestroyRef);
  private readonly i18n = inject(I18nService);
  private readonly format = inject(FormatService);

  protected readonly scope = signal<Scope>('upcoming');
  protected readonly appointments = signal<readonly AppointmentSummary[]>([]);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);
  protected readonly failureKey = signal('error.load');
  /** Shown only where nobody can act on the failure. */
  protected readonly traceId = signal<string | null>(null);

  /**
   * Upcoming is grouped by how soon it is, which is how a parent thinks about
   * it. Past is grouped by month, which is how they look one up.
   */
  protected readonly groups = computed<readonly Group[]>(() => {
    const items = this.appointments();
    if (items.length === 0) {
      return [];
    }
    const buckets = new Map<string, AppointmentSummary[]>();
    for (const item of items) {
      const label = this.scope() === 'upcoming'
        ? this.upcomingBucket(item)
        : this.format.monthName(item.startsAt);
      const bucket = buckets.get(label);
      if (bucket) {
        bucket.push(item);
      } else {
        buckets.set(label, [item]);
      }
    }
    return [...buckets].map(([label, groupItems]) => ({ label, items: groupItems }));
  });

  constructor() {
    this.load();
  }

  protected select(scope: Scope): void {
    if (scope === this.scope()) {
      return;
    }
    this.scope.set(scope);
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    this.appointments.set([]);
    this.api.appointments(this.childContext.requireId(), this.scope())
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (items) => {
          this.appointments.set(items);
          this.loading.set(false);
        },
        // The refusal names itself. Showing "could not load" for a wrong
        // filter invites a retry that will be refused identically forever.
        error: (error: unknown) => {
          this.loading.set(false);
          this.failed.set(true);
          this.failureKey.set(loadErrorKey(error));
          this.traceId.set(traceIdFor(error));
        },
      });
  }

  private upcomingBucket(appointment: AppointmentSummary): string {
    if (this.format.isToday(appointment.startsAt)) {
      return this.i18n.translate('date.todayOn',
        { date: this.format.shortDate(appointment.startsAt) });
    }
    const days = (new Date(appointment.startsAt).getTime() - Date.now())
      / (24 * 60 * 60 * 1000);
    return this.i18n.translate(days <= 7 ? 'date.thisWeek' : 'date.later');
  }
}
