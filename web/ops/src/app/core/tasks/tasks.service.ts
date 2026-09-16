import { Injectable, computed, inject, signal } from '@angular/core';
import { Observable, defer, catchError, finalize, forkJoin, map, of, shareReplay } from 'rxjs';

import { FormatService } from '@hbh/shared/format/format.service';
import { OpsApi } from '../api/ops-api';
import { OpsAuthService } from '../auth/ops-auth.service';
import { DayApi } from '../ops/day-api';
import { TASK_CATALOG, TaskContext, TaskSource } from './task-catalog';
import { Task, TaskType } from './task-model';

/**
 * Reads every task source this account may see and keeps the result.
 *
 * ONE READ FEEDS THREE PLACES: the tasks screen, the sidebar badge and the
 * dashboard's preview. They must never disagree, and the way to guarantee
 * that is for all three to look at one signal rather than each asking the
 * service on its own schedule.
 *
 * A source that fails is recorded by name and the rest are shown. A
 * failure is not an empty list: "we could not read the invoices" and "no
 * invoice is overdue" are different sentences, and the screen prints the
 * names of what it could not read.
 */
@Injectable({ providedIn: 'root' })
export class TasksService {
  private readonly day = inject(DayApi);
  private readonly crud = inject(OpsApi);
  private readonly auth = inject(OpsAuthService);
  private readonly format = inject(FormatService);
  private inFlight: Observable<readonly Task[]> | null = null;

  readonly tasks = signal<readonly Task[]>([]);
  readonly loading = signal(false);
  /** Task types whose read failed on the last load. */
  readonly failed = signal<readonly TaskType[]>([]);
  /** When the last load finished, for "as of" and for throttling the badge. */
  readonly loadedAt = signal<number>(0);

  readonly count = computed(() => this.tasks().length);
  readonly urgentCount = computed(() => this.tasks().filter((t) => t.priority === 'urgent').length);

  /** The sources this account's permissions let it draw. */
  readonly sources = computed<readonly TaskSource[]>(
    () => TASK_CATALOG.filter((source) => this.auth.can(source.permission)));

  /** Reads everything once. Returns the tasks so a caller can wait on them. */
  load(background = false): Observable<readonly Task[]> {
    if (this.inFlight) {
      return this.inFlight;
    }
    const sources = this.sources();
    if (!sources.length) {
      this.tasks.set([]);
      this.failed.set([]);
      this.loadedAt.set(Date.now());
      return of([]);
    }
    this.loading.set(!background || !this.loadedAt());
    const ctx: TaskContext = {
      format: this.format,
      day: this.day,
      crud: this.crud,
      therapistId: this.auth.me()?.therapistId,
      today: this.format.today(),
      now: new Date(),
    };
    const reads = sources.map((source) => defer(()=>source.fetch(ctx)).pipe(
      map((tasks) => ({ source, tasks, ok: true as const })),
      catchError(() => of({ source, tasks: [] as readonly Task[], ok: false as const })),
    ));
    const run = forkJoin(reads).pipe(map((results) => {
      const failed = results.filter((r) => !r.ok).map((r) => r.source.type);
      const tasks = results.flatMap((r) => r.tasks);
      const sorted=sortTasks(tasks);if(JSON.stringify(sorted)!==JSON.stringify(this.tasks()))this.tasks.set(sorted);
      this.failed.set(failed);
      this.loading.set(false);
      this.loadedAt.set(Date.now());
      return this.tasks();
    }), finalize(() => {
      this.loading.set(false);
      this.inFlight = null;
    }), shareReplay({ bufferSize: 1, refCount: false }));
    this.inFlight = run;
    // Fire once here so the badge and the preview update even when nobody
    // subscribes to the returned observable.
    run.subscribe({ error: () => this.loading.set(false) });
    return run;
  }

  /** Reload only when the last read is older than `maxAgeMs`. The badge uses this on navigation. */
  refreshIfStale(maxAgeMs = 60_000): void {
    if (this.inFlight) {
      return;
    }
    if (Date.now() - this.loadedAt() > maxAgeMs) {
      this.load(true);
    }
  }
}

/** Creation/state-entry time, shared by the screen, icon list and popups. */
export function taskTime(task: Task): number {
  for (const value of [task.createdAt, task.row?.['created_at'], task.dueDate]) {
    const at = typeof value === 'string' ? Date.parse(value) : NaN;
    if (Number.isFinite(at)) return at;
  }
  return 0;
}
export function sortTasks(tasks: readonly Task[]): readonly Task[] {
  return [...tasks].sort((a,b)=>taskTime(b)-taskTime(a)||b.id.localeCompare(a.id,undefined,{numeric:true}));
}
