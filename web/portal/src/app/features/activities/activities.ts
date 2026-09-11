import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  computed,
  inject,
  signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';

import { PortalApi } from '../../core/api/portal-api';
import { loadErrorKey, traceIdFor } from '../../core/api/portal-error';
import { ChildContextService } from '../../core/auth/child-context.service';
import { FormatService } from '@hbh/shared/format/format.service';
import { HbhCountPipe, HbhNumberPipe, HbhPluralPipe } from '@hbh/shared/format/format.pipes';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { HomeActivity, HomeProgramme } from '../../core/models/portal.models';
import { Icon } from '@hbh/shared/icon/icon';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';

/** Radius of the completion ring in the design, and the circle it draws. */
const RING_RADIUS = 26;
const RING_LENGTH = 2 * Math.PI * RING_RADIUS;

/**
 * The week's home programme. The activities are set by the child's therapist
 * inside the treatment plan; the parent's part is to say what was done.
 *
 * The tick is optimistic and reverses itself when the server refuses, so a
 * failed write never leaves a parent believing they recorded something they
 * did not.
 */
@Component({
  selector: 'hbh-activities',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    Icon, TranslatePipe, HbhCountPipe, HbhNumberPipe, HbhPluralPipe,
    Skeleton, EmptyState, ErrorNote,
  ],
  templateUrl: './activities.html',
})
export class Activities {
  private readonly api = inject(PortalApi);
  private readonly childContext = inject(ChildContextService);
  private readonly destroyRef = inject(DestroyRef);
  private readonly toast = inject(ToastService);
  private readonly i18n = inject(I18nService);
  protected readonly format = inject(FormatService);

  protected readonly ringLength = RING_LENGTH;
  protected readonly data = signal<HomeProgramme | null>(null);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);
  protected readonly failureKey = signal('error.load');
  /** Shown only where nobody can act on the failure. */
  protected readonly traceId = signal<string | null>(null);
  /** Activities with a write in flight, so they cannot be double-tapped. */
  protected readonly saving = signal<ReadonlySet<string>>(new Set());

  protected readonly sharePercent = computed(() => {
    const programme = this.data();
    if (!programme || programme.total === 0) {
      return 0;
    }
    return Math.round((programme.completed / programme.total) * 100);
  });

  /** SVG stroke offset for the completion ring. */
  protected readonly ringOffset = computed(
    () => RING_LENGTH * (1 - this.sharePercent() / 100));

  constructor() {
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    this.api.homeProgramme(this.childContext.requireId())
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (programme) => {
          this.data.set(programme);
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

  protected isSaving(activity: HomeActivity): boolean {
    return this.saving().has(activity.id);
  }

  protected toggle(activity: HomeActivity): void {
    if (this.isSaving(activity)) {
      return;
    }
    const done = activity.completedAt === null;
    this.markSaving(activity.id, true);
    this.applyLocally(activity.id, done);

    this.api.setActivityDone(this.childContext.requireId(), activity.id, done)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.markSaving(activity.id, false);
          this.toast.show(this.i18n.translate(
            done ? 'activities.recorded' : 'activities.unrecorded'));
        },
        error: () => {
          // Put the tick back where it was. A parent must never be left
          // believing they recorded something the server refused.
          this.markSaving(activity.id, false);
          this.applyLocally(activity.id, !done);
          this.toast.error(this.i18n.translate('error.saveFailed'));
        },
      });
  }

  private applyLocally(activityId: string, done: boolean): void {
    this.data.update((programme) => {
      if (!programme) {
        return programme;
      }
      const activities = programme.activities.map((activity) =>
        activity.id === activityId
          ? { ...activity, completedAt: done ? new Date().toISOString() : null }
          : activity);
      const delta = done ? 1 : -1;
      return {
        ...programme,
        activities,
        completed: Math.max(0, Math.min(programme.total, programme.completed + delta)),
      };
    });
  }

  private markSaving(activityId: string, saving: boolean): void {
    this.saving.update((current) => {
      const next = new Set(current);
      if (saving) {
        next.add(activityId);
      } else {
        next.delete(activityId);
      }
      return next;
    });
  }
}
