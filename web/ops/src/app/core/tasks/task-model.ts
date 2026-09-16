import { Row } from '../api/ops-api';
import { DrawerActionName, DrawerEntity } from '../ops/record-drawer';

/**
 * A task: something a member of staff has to DO, derived from a row that is
 * in a state somebody must move it out of.
 *
 * NOT A TABLE. There is no hbh.tasks, no "close task" and no row written
 * anywhere. Every task here is a row of an existing screen, read through the
 * same list endpoint that screen uses, under a filter that names the state.
 * When the state changes the task is simply not in the next read. That is
 * the whole reason this list cannot lie about what is still outstanding:
 * its source is the source of the screen the work is done on.
 *
 * Contrast the notifications feed (features/inbox): a LOG of things that
 * happened, addressed to one person, which only grows. The two are kept
 * apart on purpose - docs/UX-TASK-INBOX.md section 3.
 */
export type TaskType =
  | 'ENROLMENT_TRIAGE'
  | 'ENROLMENT_BOOK_ASSESSMENT'
  | 'ENROLMENT_CONVERT'
  | 'APPOINTMENT_CONFIRM'
  | 'APPOINTMENT_CHECK_IN'
  | 'SESSION_START'
  | 'SESSION_CLOSE'
  | 'REPORT_FINISH'
  | 'REQUEST_DECIDE'
  | 'CHAT_READ'
  | 'INVOICE_ISSUE'
  | 'INVOICE_OVERDUE'
  | 'CHILD_ASSIGN_THERAPIST'
  | 'THERAPIST_PROFILE_CONSENT'
  | 'SCHEDULE_CONFLICT';

/** The business object a task belongs to - the thing the card opens. */
export type TaskEntity =
  | 'APPLICATION'
  | 'BENEFICIARY'
  | 'APPOINTMENT'
  | 'SESSION'
  | 'REPORT'
  | 'REQUEST'
  | 'INVOICE'
  | 'THERAPIST'
  | 'CONVERSATION';

export type TaskPriority = 'urgent' | 'normal';

/**
 * A button on the card. A navigation, or - for a record the drawer can
 * show - the drawer opened in place, with `link` as what a plain link
 * (the dashboard preview, a message) would carry to the same effect.
 * The doing still happens on the screen that owns the row: the drawer
 * only opens that screen's dialog.
 */
export interface TaskAction {
  readonly labelKey: string;
  readonly link: readonly (string | number)[];
  readonly query?: Readonly<Record<string, string>>;
  /** Open the record drawer here instead of navigating. */
  readonly drawer?: {
    readonly entity: DrawerEntity;
    readonly id: number;
    readonly action?: DrawerActionName;
  };
}

export interface Task {
  /** Unique across types: `${taskType}:${entityId}` (or a pair for conflicts). */
  readonly id: string;
  readonly taskType: TaskType;
  /** i18n key of the task's name ("طلب التحاق جديد"). */
  readonly titleKey: string;
  /** i18n key of what is required ("راجع الطلب وتواصل مع الأسرة"). */
  readonly descriptionKey: string;
  readonly entityType: TaskEntity;
  readonly entityId: number;
  /** The row's own number where it has one: ENR-2026-01029, INV-…, REQ-…. */
  readonly entityNo?: string;
  /** Whom this is about, as a person reads it. */
  readonly entityDisplayName: string;
  readonly parentName?: string;
  readonly childName?: string;
  /** One more line of context (service · therapist · room, or an amount). */
  readonly meta?: string;
  /** Same line, as an i18n key, when the context is a code (a request kind). */
  readonly metaKey?: string;
  /** The row's status code, and the badge key/tone the owning screen uses for it. */
  readonly status?: string;
  readonly statusKey?: string;
  readonly statusTone?: string;
  readonly priority: TaskPriority;
  /** The permission that makes this task somebody's. Roles are the server's business. */
  readonly assignedRole: string;
  /** 'me' when the row is addressed to the signed-in therapist, else undefined (shared by role). */
  readonly assignedUser?: 'me';
  /** UTC instant, when the row carries one (an appointment's start, an invoice's due date). */
  readonly dueDate?: string;
  /** UTC instant the row entered this state, when known. */
  readonly createdAt?: string;
  readonly primaryAction: TaskAction;
  readonly secondaryActions: readonly TaskAction[];
  /** The child behind the row, so every card can open the file. */
  readonly childId?: number;
  /** The row the task was derived from, handed to the drawer so it reads nothing. */
  readonly row?: Row;
}
