import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { HttpClient } from '@angular/common/http';
import { map } from 'rxjs';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { FormatService } from '@hbh/shared/format/format.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { Row } from '../../core/api/ops-api';

/** One view of the request log, and the columns it needs. */
interface View {
  readonly key: 'health' | 'errors' | 'activity';
  readonly labelKey: string;
  readonly columns: readonly {
    readonly key: string;
    readonly labelKey: string;
    readonly read: (row: Row, format: FormatService) => string;
    readonly ltr?: boolean;
  }[];
}

const text = (row: Row, key: string): string => {
  const value = row[key];
  return value === null || value === undefined ? '' : String(value);
};

const instant = (row: Row, key: string, format: FormatService): string => {
  const at = text(row, key);
  return at ? `${format.shortDate(at)} · ${format.time(at)}` : '';
};

/**
 * What the service has actually been doing.
 *
 * One row is written per finished request and three views read it back. It is
 * the only screen here that is about the SYSTEM rather than about a child,
 * and it needs OPS.VIEW, which the seed gives to the centre administrator.
 *
 * FOUR PROPERTIES OF THE LOG WORTH KNOWING WHILE READING IT:
 *
 *   `route` is a TEMPLATE, not a path - /children/{child_id}, never
 *   /children/42 - and it comes from the router's own constant. A request
 *   that matched nothing is filed under "(unrouted)", because the path of a
 *   404 is chosen by whoever sent it, and logging those verbatim would let a
 *   stranger write a thousand distinct rows onto this screen.
 *
 *   The error MESSAGE is always empty. This service answers with codes, and
 *   the only text available to put there would be a database error that can
 *   quote a row value - a child's name in an error string is clinical data on
 *   an operations screen.
 *
 *   `detail` names a FIELD and never a value.
 *
 *   An anonymous caller is logged with no user, deliberately. A blank name in
 *   the activity list is a fact, not a gap.
 */
@Component({
  selector: 'hbh-ops-log',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon, TranslatePipe, Skeleton, EmptyState, ErrorNote],
  templateUrl: './ops-log.html',
})
export class OpsLog {
  private readonly http = inject(HttpClient);
  private readonly base = `${inject(HBH_CONFIG).apiBaseUrl}/api/v1/ops`;
  private readonly destroyRef = inject(DestroyRef);
  protected readonly format = inject(FormatService);

  protected readonly views: readonly View[] = [
    {
      key: 'health', labelKey: 'opslog.health',
      columns: [
        { key: 'method', labelKey: 'opslog.method', read: (row) => text(row, 'method'), ltr: true },
        { key: 'route', labelKey: 'opslog.route', read: (row) => text(row, 'route'), ltr: true },
        { key: 'calls', labelKey: 'opslog.calls', read: (row, f) => f.count(Number(text(row, 'calls'))), ltr: true },
        { key: 'p50', labelKey: 'opslog.p50', read: (row) => `${text(row, 'p50_ms')} ms`, ltr: true },
        // p95 rather than an average: the mean hides the slow tail, and the
        // slow tail is the part somebody is waiting through.
        { key: 'p95', labelKey: 'opslog.p95', read: (row) => `${text(row, 'p95_ms')} ms`, ltr: true },
        { key: 'max', labelKey: 'opslog.max', read: (row) => `${text(row, 'max_ms')} ms`, ltr: true },
        { key: 'err', labelKey: 'opslog.errorPct', read: (row) => `${text(row, 'error_pct')}%`, ltr: true },
        { key: 'last', labelKey: 'opslog.lastCall', read: (row, f) => instant(row, 'last_call_at', f) },
      ],
    },
    {
      key: 'errors', labelKey: 'opslog.errors',
      columns: [
        { key: 'when', labelKey: 'opslog.when', read: (row, f) => instant(row, 'occurred_at', f) },
        { key: 'status', labelKey: 'opslog.status', read: (row) => text(row, 'status_code'), ltr: true },
        { key: 'code', labelKey: 'opslog.code', read: (row) => text(row, 'error_code'), ltr: true },
        { key: 'method', labelKey: 'opslog.method', read: (row) => text(row, 'method'), ltr: true },
        { key: 'route', labelKey: 'opslog.route', read: (row) => text(row, 'route'), ltr: true },
        { key: 'user', labelKey: 'opslog.user', read: (row) => text(row, 'username'), ltr: true },
        // The request id, so a complaint can be matched to a log line. It
        // identifies the request and says nothing about the account.
        { key: 'req', labelKey: 'opslog.requestId', read: (row) => text(row, 'request_id'), ltr: true },
      ],
    },
    {
      key: 'activity', labelKey: 'opslog.activity',
      columns: [
        { key: 'user', labelKey: 'opslog.user', read: (row) => text(row, 'username'), ltr: true },
        { key: 'type', labelKey: 'opslog.userType', read: (row) => text(row, 'user_type'), ltr: true },
        { key: 'requests', labelKey: 'opslog.requests', read: (row, f) => f.count(Number(text(row, 'requests'))), ltr: true },
        { key: 'failed', labelKey: 'opslog.failed', read: (row, f) => f.count(Number(text(row, 'failed_requests'))), ltr: true },
        { key: 'days', labelKey: 'opslog.activeDays', read: (row, f) => f.count(Number(text(row, 'active_days'))), ltr: true },
        { key: 'last', labelKey: 'opslog.lastSeen', read: (row, f) => instant(row, 'last_seen_at', f) },
      ],
    },
  ];

  protected readonly index = signal(0);
  protected readonly view = computed(() => this.views[this.index()]);

  protected readonly rows = signal<readonly Row[]>([]);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);

  constructor() {
    this.load();
  }

  protected select(index: number): void {
    if (index === this.index()) {
      return;
    }
    this.index.set(index);
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    this.http.get<Record<string, unknown>>(`${this.base}/${this.view().key}`)
      .pipe(
        map((body) => {
          for (const value of Object.values(body ?? {})) {
            if (Array.isArray(value)) {
              return value as readonly Row[];
            }
          }
          return [] as readonly Row[];
        }),
        takeUntilDestroyed(this.destroyRef),
      )
      .subscribe({
        next: (rows) => {
          this.rows.set(rows);
          this.loading.set(false);
        },
        error: () => {
          this.loading.set(false);
          this.failed.set(true);
        },
      });
  }

  protected cell(row: Row, column: View['columns'][number]): string {
    return column.read(row, this.format);
  }

  protected rowKey(row: Row, index: number): string {
    return String(row['log_id'] ?? row['user_id']
      ?? `${text(row, 'method')}:${text(row, 'route')}` ?? index);
  }

  /** A route worth looking at: something there is failing. */
  protected isHot(row: Row): boolean {
    return this.view().key === 'health' && Number(text(row, 'error_pct')) > 0;
  }
}
