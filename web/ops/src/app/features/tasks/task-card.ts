import { ChangeDetectionStrategy, Component, computed, inject, input } from '@angular/core';
import { RouterLink } from '@angular/router';

import { FormatService } from '@hbh/shared/format/format.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon, IconName } from '@hbh/shared/icon/icon';
import { RecordDrawerService } from '../../core/ops/record-drawer.service';
import { Task, TaskAction, TaskEntity } from '../../core/tasks/task-model';

/**
 * One task, drawn the same way whatever its type.
 *
 * ONE COMPONENT FOR EVERY KIND. The catalogue decides what a task says and
 * where its button goes; this decides only how a task looks. A card per
 * type would be fourteen ways for the same information to drift apart.
 *
 * Every button is a link. Nothing is done from here: the card opens the
 * screen that owns the row, and that screen offers whatever the server's
 * state machine allows at that moment.
 */
@Component({
  selector: 'hbh-task-card',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Icon, TranslatePipe],
  styleUrl: './task-card.css',
  template: `
    @let t = task();
    <article class="task" [class.is-urgent]="t.priority === 'urgent'">
      <span class="task__ic"><hbh-icon [name]="icon()" /></span>
      <div class="task__body">
        <div class="task__head">
          <span class="task__title">{{ t.titleKey | t }}</span>
          @if (t.priority === 'urgent') {
            <span class="hbh-badge hbh-badge--danger">{{ 'tasks.urgent' | t }}</span>
          }
          @if (t.assignedUser === 'me') {
            <span class="hbh-badge hbh-badge--info">{{ 'tasks.mine' | t }}</span>
          }
        </div>

        <div class="task__who">
          <b>{{ t.entityDisplayName }}</b>
          @if (t.entityNo) { <span class="task__no" dir="ltr">{{ t.entityNo }}</span> }
        </div>
        @if (t.parentName) {
          <div class="task__line">{{ 'field.guardian' | t }}: {{ t.parentName }}</div>
        }
        @if (t.metaKey) {
          <div class="task__line">{{ t.metaKey | t }}</div>
        } @else if (t.meta) {
          <div class="task__line" dir="auto">{{ t.meta }}</div>
        }

        <div class="task__state">
          @if (t.statusKey) {
            <span class="hbh-badge" [class]="'hbh-badge ' + (t.statusTone ?? '')">{{ t.statusKey | t }}</span>
          }
          @if (t.dueDate) {
            <span class="task__when">{{ due() }}</span>
          } @else if (t.createdAt) {
            <span class="task__when">{{ 'tasks.since' | t }} {{ format.dayMonthYear(t.createdAt) }}</span>
          }
        </div>

        <div class="task__ask">
          <span class="task__ask-l">{{ 'tasks.required' | t }}:</span>
          {{ t.descriptionKey | t }}
        </div>
      </div>

      <div class="task__actions">
        <!-- A record the drawer can show opens HERE, beside the inbox, with
             the step proposed; everything else is a navigation to the
             screen that owns the row. Either way nothing is done from the
             card: the drawer opens that screen's own dialog. -->
        @if (t.primaryAction.drawer; as target) {
          <button class="hbh-btn hbh-btn--primary hbh-btn--sm" type="button" (click)="openDrawer(target)">
            {{ t.primaryAction.labelKey | t }}
          </button>
        } @else {
          <a class="hbh-btn hbh-btn--primary hbh-btn--sm" [routerLink]="t.primaryAction.link"
             [queryParams]="t.primaryAction.query ?? null">
            {{ t.primaryAction.labelKey | t }}
          </a>
        }
        @for (action of t.secondaryActions; track action.labelKey + action.link.join('/')) {
          @if (action.drawer; as target) {
            <button class="hbh-btn hbh-btn--ghost hbh-btn--sm" type="button" (click)="openDrawer(target)">
              {{ action.labelKey | t }}
            </button>
          } @else {
            <a class="hbh-btn hbh-btn--ghost hbh-btn--sm" [routerLink]="action.link"
               [queryParams]="action.query ?? null">
              {{ action.labelKey | t }}
            </a>
          }
        }
      </div>
    </article>
  `,
})
export class TaskCard {
  readonly task = input.required<Task>();
  protected readonly format = inject(FormatService);
  private readonly drawer = inject(RecordDrawerService);

  /** Opens the record drawer on the task's row - no read, the row is already here. */
  protected openDrawer(target: NonNullable<TaskAction['drawer']>): void {
    const t = this.task();
    void this.drawer.open({
      entity: target.entity, id: target.id, action: target.action, source: 'TASK_INBOX',
      row: t.row && t.entityId === target.id ? t.row : undefined,
      context: t.childId ? { childId: t.childId, childName: t.childName } : undefined,
    });
  }

  protected readonly icon = computed<IconName>(() => ICON_BY_ENTITY[this.task().entityType]);

  /** "Today 10:00" when it is today, otherwise the date and time. */
  protected readonly due = computed(() => {
    const at = this.task().dueDate;
    if (!at) {
      return '';
    }
    return this.format.isToday(at)
      ? `${this.format.time(at)}`
      : `${this.format.dayMonthYear(at)} · ${this.format.time(at)}`;
  });
}

const ICON_BY_ENTITY: Readonly<Record<TaskEntity, IconName>> = {
  CONVERSATION: 'ic-chat',
  APPLICATION: 'ic-user-plus',
  BENEFICIARY: 'ic-users',
  APPOINTMENT: 'ic-calendar',
  SESSION: 'ic-activity',
  REPORT: 'ic-file',
  REQUEST: 'ic-chat',
  INVOICE: 'ic-receipt',
  THERAPIST: 'ic-user-check',
};
