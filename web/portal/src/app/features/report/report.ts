import {
  ChangeDetectionStrategy, Component, DestroyRef, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute } from '@angular/router';

import { FormatService } from '@hbh/shared/format/format.service';
import { HbhCountPipe, HbhNumberPipe } from '@hbh/shared/format/format.pipes';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { PortalApi } from '../../core/api/portal-api';
import { loadErrorKey, traceIdFor } from '../../core/api/portal-error';
import { ChildContextService } from '../../core/auth/child-context.service';
import { ReportDetail, ReportGoal } from '../../core/models/portal.models';

/**
 * A report, open.
 *
 * IT DID NOT EXIST, and tapping a report answered "opening a report file is
 * not switched on yet" - behind a green tick, so an absence was announced as
 * a success. GET /reports/{id} had been returning the whole report since the
 * service was written: the summary the therapist wrote and the state of each
 * goal at the time. Nothing here needed building on the service side.
 *
 * There is no file to download and no attachment. A report in this system IS
 * this content, so the screen renders it rather than offering to fetch
 * something that does not exist.
 *
 * The goals repeat the progress screen's rule and must keep repeating it: a
 * goal with no measurement shows no percentage. The baseline is where the
 * therapist started counting, and printing it as an achievement in a document
 * a parent may keep would be worse here than anywhere else.
 */
@Component({
  selector: 'hbh-report',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon, Skeleton, ErrorNote, TranslatePipe, HbhNumberPipe, HbhCountPipe],
  templateUrl: './report.html',
})
export class Report {
  private readonly api = inject(PortalApi);
  private readonly route = inject(ActivatedRoute);
  private readonly destroyRef = inject(DestroyRef);
  protected readonly format = inject(FormatService);
  private readonly childContext = inject(ChildContextService);

  /** On the printed page only: the screen already names the child above. */
  protected childName(): string {
    return this.childContext.selected()?.fullName ?? '';
  }

  /**
   * Print, or save as PDF - the browser's dialog offers both (#23). There is
   * no file on the service to fetch: a report IS this content, so the page
   * itself is the document, and the print stylesheet strips the app around it.
   */
  protected print(): void {
    window.print();
  }

  protected readonly data = signal<ReportDetail | null>(null);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);
  protected readonly failureKey = signal('error.load');
  protected readonly traceId = signal<string | null>(null);

  constructor() {
    this.load();
  }

  protected load(): void {
    const id = this.route.snapshot.paramMap.get('reportId');
    if (!id) {
      this.loading.set(false);
      this.failed.set(true);
      return;
    }
    this.loading.set(true);
    this.failed.set(false);
    this.api.report(id)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (report) => {
          this.data.set(report);
          this.loading.set(false);
        },
        // A 404 here is the ordinary answer for a report this family may not
        // see - a draft, or another child's. It is named as "not available"
        // rather than as a failure, because nothing went wrong.
        error: (error: unknown) => {
          this.loading.set(false);
          this.failed.set(true);
          this.failureKey.set(loadErrorKey(error));
          this.traceId.set(traceIdFor(error));
        },
      });
  }

  /** Measured, or never assessed. The same test the progress screen uses. */
  protected measured(goal: ReportGoal): boolean {
    return goal.latestPercent !== null;
  }

  /** The bar is a share of the target, not of a hundred. */
  protected barWidth(goal: ReportGoal): number {
    const current = goal.latestPercent;
    const target = goal.targetPercent ?? 0;
    if (current === null || target <= 0) {
      return 0;
    }
    return Math.min(100, Math.round((current / target) * 100));
  }
}

