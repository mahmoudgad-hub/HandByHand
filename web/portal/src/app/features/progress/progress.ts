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
import { HbhCountPipe, HbhNumberPipe, HbhPluralPipe } from '@hbh/shared/format/format.pipes';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Goal, ProgressOverview } from '../../core/models/portal.models';
import { Icon } from '@hbh/shared/icon/icon';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';

/**
 * The treatment plan's goals and how far each has come.
 *
 * Every number here was measured by a therapist and published deliberately.
 * The portal computes no clinical value of its own - the only arithmetic it
 * does is turning a percentage into a bar width.
 */
@Component({
  selector: 'hbh-progress',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    RouterLink, Icon, TranslatePipe, HbhCountPipe, HbhNumberPipe, HbhPluralPipe,
    Skeleton, EmptyState, ErrorNote,
  ],
  templateUrl: './progress.html',
})
export class Progress {
  private readonly api = inject(PortalApi);
  private readonly childContext = inject(ChildContextService);
  private readonly destroyRef = inject(DestroyRef);
  protected readonly format = inject(FormatService);

  protected readonly data = signal<ProgressOverview | null>(null);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);
  protected readonly failureKey = signal('error.load');
  /** Shown only where nobody can act on the failure. */
  protected readonly traceId = signal<string | null>(null);

  /** The chart shows the one goal that has a series behind it. */
  protected readonly charted = computed<Goal | null>(() =>
    this.data()?.goals.find((goal) => goal.series.length > 1) ?? null);

  constructor() {
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    this.api.progress(this.childContext.requireId())
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (overview) => {
          this.data.set(overview);
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

  /**
   * The bar tint tracks distance from the target, not the raw number: a goal
   * at 35 per cent against a target of 40 is close, and colouring it as if it
   * were failing would misread the plan to the parent.
   *
   * An unmeasured goal has no tint at all, because it has nothing to be near
   * or far from.
   */
  protected barTone(goal: Goal): string {
    const current = goal.currentPercent;
    if (current === null || goal.targetPercent <= 0) {
      return '';
    }
    const share = current / goal.targetPercent;
    if (share >= 0.9) {
      return 'goal__fill--g';
    }
    return share >= 0.6 ? '' : 'goal__fill--a';
  }

  /**
   * How far along the bar to fill, as a share of the TARGET rather than of a
   * hundred.
   *
   * A goal whose target is 60 and whose latest measurement is 54 is nearly
   * done; drawn against 100 the bar looks half empty and reads as failure.
   * The target is what the plan set, so the target is what the bar measures.
   */
  protected barWidth(goal: Goal): number {
    const current = goal.currentPercent;
    if (current === null || goal.targetPercent <= 0) {
      return 0;
    }
    return Math.min(100, Math.round((current / goal.targetPercent) * 100));
  }

  /**
   * Whether this goal has been assessed at all.
   *
   * Both halves are checked. A count with no percentage, or a percentage with
   * no count, is a row that disagrees with itself - and it was exactly such a
   * row that put "20%" beside "0 measurements" on this screen. Showing
   * nothing is right in both cases: the honest answer is that there is no
   * measurement to show.
   */
  protected measured(goal: Goal): boolean {
    return goal.measurementCount > 0 && goal.currentPercent !== null;
  }
}
