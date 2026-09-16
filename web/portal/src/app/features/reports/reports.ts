import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  inject,
  input,
  OnInit,
  signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Router } from '@angular/router';

import { PortalApi } from '../../core/api/portal-api';
import { loadErrorKey, traceIdFor } from '../../core/api/portal-error';
import { ChildContextService } from '../../core/auth/child-context.service';
import { FormatService } from '@hbh/shared/format/format.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { ReportSummary } from '../../core/models/portal.models';
import { Icon, IconName } from '@hbh/shared/icon/icon';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';

type Scope = 'reports' | 'notes';

/**
 * Published reports and session notes.
 *
 * Only what a therapist deliberately published reaches this list. Internal
 * notes between the care team are not filtered out here - they never leave
 * the server, because a filter in a screen is not a boundary.
 */
@Component({
  selector: 'hbh-reports',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon, TranslatePipe, Skeleton, EmptyState, ErrorNote],
  templateUrl: './reports.html',
})
export class Reports implements OnInit {
  private readonly api = inject(PortalApi);
  private readonly childContext = inject(ChildContextService);
  private readonly destroyRef = inject(DestroyRef);
  private readonly router = inject(Router);
  protected readonly format = inject(FormatService);

  readonly scope = input<Scope>('reports');
  protected readonly items = signal<readonly ReportSummary[]>([]);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);
  protected readonly failureKey = signal('error.load');
  /** Shown only where nobody can act on the failure. */
  protected readonly traceId = signal<string | null>(null);

  ngOnInit(): void {
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    this.items.set([]);
    this.api.reports(this.childContext.requireId(), this.scope())
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (items) => {
          this.items.set(items);
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

  protected icon(report: ReportSummary): IconName {
    return report.kind === 'ASSESSMENT' ? 'ic-clipboard' : 'ic-file';
  }

  protected tint(report: ReportSummary): string {
    if (report.unread) {
      return 'hbh-t--blue';
    }
    return report.kind === 'ASSESSMENT' ? 'hbh-t--purple' : 'hbh-t--navy';
  }

  /**
   * Open the report.
   *
   * This used to answer with "opening a report file is not switched on yet",
   * and the premise under it was wrong twice over. A report in this system is
   * not a file: GET /reports/{id} returns the summary and the goals, and it
   * has done since the service was written. And the message went out through
   * `toast.show`, so an absence was announced behind a green tick.
   *
   * A session NOTE is a different thing - it has no detail endpoint, and its
   * whole text is already the line in the list - so notes stay unopenable and
   * the list draws them as text rather than as buttons.
   */
  protected open(report: ReportSummary): void {
    void this.router.navigate(['/reports', report.id]);
  }

  /** Whether tapping this row leads anywhere. */
  protected openable(report: ReportSummary): boolean {
    return report.kind !== 'SESSION_NOTE';
  }
}

