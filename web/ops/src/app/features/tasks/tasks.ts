import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute, Router } from '@angular/router';

import { FormatService } from '@hbh/shared/format/format.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { RecordDrawerService } from '../../core/ops/record-drawer.service';
import { Task, TaskAction, TaskEntity, TaskType } from '../../core/tasks/task-model';
import { TasksService } from '../../core/tasks/tasks.service';
import {RouterLink} from '@angular/router';
import {TablePages} from '@hbh/shared/ui/table-pages';

/** The one-click scopes. Everything else is a select. */
type Scope = 'all' | 'mine' | 'role' | 'urgent' | 'overdue' | 'today';

/**
 * What needs doing, in one place.
 *
 * Every card here is a row of another screen in a state somebody must move
 * it out of, read through that screen's own list endpoint. The doing happens
 * there: a card opens the screen already filtered to the row, and when the
 * row moves the card is gone on the next read. See docs/UX-TASK-INBOX.md.
 *
 * THE FILTERS NARROW A LIST ALREADY NARROWED BY PERMISSION. What this account
 * may not read was never asked for (TasksService.sources), so "all" is
 * already "all that is yours to do".
 */
@Component({
  selector: 'hbh-tasks',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon, TranslatePipe, Skeleton, ErrorNote, EmptyState, RouterLink, TablePages],
  templateUrl: './tasks.html',
  styleUrl: './tasks.css',
})
export class Tasks {
  protected readonly svc = inject(TasksService);
  protected readonly auth = inject(OpsAuthService);
  protected readonly format = inject(FormatService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  private readonly drawer = inject(RecordDrawerService);

  protected readonly scope = signal<Scope>('all');
  /** Seeded from ?type=, which is how the dashboard tiles arrive. */
  protected readonly type = signal<string>(this.route.snapshot.queryParamMap.get('type') ?? '');
  protected readonly entity = signal<string>('');
  protected readonly failedAll = signal(false);

  protected readonly scopes: readonly Scope[] = ['all', 'mine', 'role', 'urgent', 'overdue', 'today'];

  /** True when this account can have tasks addressed to it personally. */
  protected readonly hasPersonal = computed(() => !!this.auth.me());

  /** The types present in what was read - a select over what exists, not over the catalogue. */
  protected readonly types = computed<readonly TaskType[]>(() =>
    [...new Set(this.svc.tasks().map((t) => t.taskType))]);
  protected readonly entities = computed<readonly TaskEntity[]>(() =>
    [...new Set(this.svc.tasks().map((t) => t.entityType))]);

  protected readonly visible = computed<readonly Task[]>(() => {
    const now = Date.now();
    const scope = this.scope();
    const type = this.type();
    const entity = this.entity();
    return this.svc.tasks().filter((t) => {
      if (type && t.taskType !== type) {
        return false;
      }
      if (entity && t.entityType !== entity) {
        return false;
      }
      switch (scope) {
        case 'mine': return t.assignedUser === 'me';
        case 'role': return t.assignedUser !== 'me';
        case 'urgent': return t.priority === 'urgent';
        case 'overdue': return !!t.dueDate && Date.parse(t.dueDate) < now;
        case 'today': return !!t.dueDate && this.format.isToday(t.dueDate);
        default: return true;
      }
    });
  });

  protected readonly asOf = computed(() => {
    const at = this.svc.loadedAt();
    return at ? this.format.time(new Date(at)) : '';
  });

  constructor() {
    this.load();
    // A record changed from the drawer beside this list is a task that
    // may be gone: read the inbox again, once the dialog has reported.
    this.drawer.changed$
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe(() => this.load());
  }

  protected load(): void {
    this.failedAll.set(false);
    this.svc.load()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({ error: () => this.failedAll.set(true) });
  }

  protected openTask(task:Task,action:TaskAction=task.primaryAction):void {
    const target=action.drawer;
    if(target)void this.drawer.open({entity:target.entity,id:target.id,action:target.action,source:'TASK_INBOX',row:task.row,context:task.childId?{childId:task.childId,childName:task.childName}:undefined});
  }
  protected setScope(scope: Scope): void {
    this.scope.set(scope);
  }

  protected setType(value: string): void {
    this.type.set(value);
    // Into the address bar, so the filter survives a refresh and can be linked.
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: { type: value || null },
      queryParamsHandling: 'merge',
      replaceUrl: true,
    });
  }

  protected setEntity(value: string): void {
    this.entity.set(value);
  }

  protected countFor(scope: Scope): number {
    const now = Date.now();
    const all = this.svc.tasks();
    switch (scope) {
      case 'mine': return all.filter((t) => t.assignedUser === 'me').length;
      case 'role': return all.filter((t)=>t.assignedUser !== 'me').length;
      case 'urgent': return all.filter((t) => t.priority === 'urgent').length;
      case 'overdue': return all.filter((t) => !!t.dueDate && Date.parse(t.dueDate) < now).length;
      case 'today': return all.filter((t) => !!t.dueDate && this.format.isToday(t.dueDate)).length;
      default: return all.length;
    }
  }

  /** Whether the empty list is "nothing to do" or "nothing under these filters". */
  protected readonly filtered = computed(
    () => this.scope() !== 'all' || !!this.type() || !!this.entity());

  protected clearFilters(): void {
    this.scope.set('all');
    this.entity.set('');
    this.setType('');
  }
}
