import { Observable, forkJoin, map, of } from 'rxjs';
import { FormatService } from '@hbh/shared/format/format.service';

import { OpsApi, Row } from '../api/ops-api';
import { readAllPages } from '../api/read-all-pages';
import { DayApi, DayQuery } from '../ops/day-api';
import {
  APPOINTMENTS_SPEC, ENROLMENTS_SPEC, INVOICES_SPEC, REPORTS_SPEC, REQUESTS_SPEC,
  SESSIONS_SPEC,
} from '../ops/day-spec';
import { DrawerActionName } from '../ops/record-drawer';
import { Task, TaskEntity, TaskPriority, TaskType } from './task-model';

/**
 * The task catalogue: one source per task type, each a READ the console
 * already makes somewhere else.
 *
 * docs/UX-TASK-INBOX.md section 2.3 lists twenty-three kinds. The ones here
 * are those whose source exists today as a list endpoint with a status
 * filter. What is NOT here, and why, so nobody adds a card with no row
 * behind it:
 *
 *   SESSION_NOTE      - GET /sessions does not say whether a note exists.
 *   CONSENT_MISSING   - surfaces at the moment of a refusal, not as a list.
 *   PACKAGE_RENEW     - the balances ledger names no thresholds; the
 *                       thresholds are a centre policy and belong in
 *                       sys_params before a card can claim "about to lapse".
 *   PLAN_APPROVE, GUARDIAN_GRANT_PORTAL, PROFILE_INCOMPLETE, INSTALLMENT_DUE
 *                     - no route (UX-PROBLEMS.md R-02, R-05, EN-06, 0142).
 *   SITE_PUBLISH      - eleven resources for a low-value card; deferred.
 *
 * EVERY CONDITION HERE IS DISPLAY, NOT A RULE. "Overdue" is due_date before
 * today; "about to start" is starts_at within fifteen minutes. Nothing is
 * written from them, and the screen the card opens re-reads the row and
 * offers whatever the server's state machine allows.
 */

/** What a source needs to read with. */
export interface TaskContext {
  readonly format: FormatService;
  readonly day: DayApi;
  readonly crud: OpsApi;
  /** The signed-in therapist's id, when the account has one. */
  readonly therapistId: number | undefined;
  /** The centre's today, YYYY-MM-DD. */
  readonly today: string;
  readonly now: Date;
}

export interface TaskSource {
  readonly type: TaskType;
  readonly entity: TaskEntity;
  /** Drawn only for an account holding this. The server refuses the read regardless. */
  readonly permission: string;
  readonly fetch: (ctx: TaskContext) => Observable<readonly Task[]>;
}

// ---- small readers over the rows the list endpoints return --------------

function text(row: Row, key: string): string {
  const value = row[key];
  return value == null ? '' : String(value);
}

function num(row: Row, key: string): number {
  const value = Number(row[key]);
  return Number.isFinite(value) ? value : 0;
}

function ref(row: Row, object: string, key: string): string {
  const nested = row[object];
  if (nested && typeof nested === 'object') {
    return text(nested as Row, key);
  }
  return '';
}

function refId(row: Row, object: string, key: string): number | undefined {
  const nested = row[object];
  if (nested && typeof nested === 'object') {
    const value = Number((nested as Row)[key]);
    return Number.isFinite(value) && value > 0 ? value : undefined;
  }
  return undefined;
}

const HOUR = 60 * 60 * 1000;

function olderThan(iso: string, hours: number, now: Date): boolean {
  const at = Date.parse(iso);
  return Number.isFinite(at) && now.getTime() - at > hours * HOUR;
}

function within(iso: string, minutes: number, now: Date): boolean {
  const at = Date.parse(iso);
  return Number.isFinite(at) && at - now.getTime() <= minutes * 60 * 1000;
}

/** Complete the filtered list before deriving tasks from it. */
function list(ctx: TaskContext, resource: Parameters<DayApi['list']>[0], query: DayQuery): Observable<readonly Row[]> {
  return readAllPages((page) => ctx.day.list(resource, { ...query, limit: 100, page }));
}

/** `mine` only when the account can have a personal day; otherwise the centre's. */
function mineIf(ctx: TaskContext): DayQuery {
  return ctx.therapistId !== undefined ? { mine: true } : {};
}

function priority(urgent: boolean): TaskPriority {
  return urgent ? 'urgent' : 'normal';
}

// ---- sources -------------------------------------------------------------

/**
 * The action an enrolment task's button opens on the application page.
 * Named, not performed: the page checks the status and the permission again
 * and opens the list's own dialog; the person confirms.
 */
const ENROLMENT_TASK_ACTION: Readonly<Record<string, string>> = {
  ENROLMENT_TRIAGE: 'contact',
  ENROLMENT_CONVERT: 'convert',
};

const enrolmentTask = (
  type: TaskType, status: string, ctx: TaskContext, staleHours: number,
) => list(ctx, 'enrolments', { status }).pipe(map((rows) => rows.map((row): Task => {
  const id = num(row, 'application_id');
  const submitted = text(row, 'submitted_at');
  const contacted = text(row, 'contacted_at');
  return {
    id: `${type}:${id}`,
    taskType: type,
    titleKey: `tasks.type.${type}.title`,
    descriptionKey: `tasks.type.${type}.action`,
    entityType: 'APPLICATION',
    entityId: id,
    entityNo: text(row, 'application_no'),
    entityDisplayName: text(row, 'child_name_ar'),
    childName: text(row, 'child_name_ar'),
    parentName: text(row, 'parent_name_ar'),
    meta: text(row, 'parent_mobile'),
    status,
    statusKey: `${ENROLMENTS_SPEC.statusPrefix}${status}`,
    statusTone: ENROLMENTS_SPEC.tone(status),
    priority: priority(olderThan(contacted || submitted, staleHours, ctx.now)),
    assignedRole: 'ENROLMENT.MANAGE',
    createdAt: contacted || submitted,
    // The application's own page, asked to open the step's dialog. The
    // page re-checks status and permission and never runs anything on its
    // own; `returnUrl` brings the person back here afterwards.
    primaryAction: {
      labelKey: `tasks.type.${type}.cta`,
      link: ['/enrolments', id],
      query: { ...(ENROLMENT_TASK_ACTION[type] ? { action: ENROLMENT_TASK_ACTION[type] } : {}), returnUrl: '/tasks' },
    },
    secondaryActions: [
      { labelKey: 'tasks.openList', link: ['/enrolments'], query: { status, focus: String(id) } },
    ],
  };
})));

/**
 * The step an appointment task's button opens in the record drawer -
 * the diary's own status/start dialog, pre-selecting the move the task
 * is about. Named, not performed: the drawer checks the row's state and
 * the permission again, and the person confirms.
 */
const APPOINTMENT_TASK_ACTION: Readonly<Partial<Record<TaskType, DrawerActionName>>> = {
  APPOINTMENT_CONFIRM: 'confirm',
  APPOINTMENT_CHECK_IN: 'check-in',
  SESSION_START: 'start',
};

const appointmentTask = (
  type: TaskType, status: string, ctx: TaskContext, keep: (row: Row) => boolean,
  urgent: (row: Row) => boolean, permission: string, query: DayQuery = {},
) => list(ctx, 'appointments', { date: ctx.today, status, ...query }).pipe(
  map((rows) => rows.filter(keep).map((row): Task => {
    const id = num(row, 'appointment_id');
    const childId = refId(row, 'child', 'child_id');
    const mine = ctx.therapistId !== undefined
      && refId(row, 'therapist', 'therapist_id') === ctx.therapistId;
    const view: Record<string, string> =
      type === 'SESSION_START' && ctx.therapistId !== undefined ? { view: 'mine' } : {};
    const action = APPOINTMENT_TASK_ACTION[type];
    return {
      id: `${type}:${id}`,
      taskType: type,
      titleKey: `tasks.type.${type}.title`,
      descriptionKey: `tasks.type.${type}.action`,
      entityType: 'APPOINTMENT',
      entityId: id,
      entityNo: text(row, 'appointment_no'),
      entityDisplayName: ref(row, 'child', 'full_name_ar'),
      childName: ref(row, 'child', 'full_name_ar'),
      childId,
      meta: [ref(row, 'service', 'name_ar'), ref(row, 'therapist', 'full_name_ar'), ref(row, 'room', 'name_ar')]
        .filter(Boolean).join(' · '),
      status,
      statusKey: `${APPOINTMENTS_SPEC.statusPrefix}${status}`,
      statusTone: APPOINTMENTS_SPEC.tone(status),
      priority: priority(urgent(row)),
      assignedRole: permission,
      assignedUser: mine ? 'me' : undefined,
      dueDate: text(row, 'starts_at'),
      row,
      // The record drawer, here in the inbox, with the step pre-selected.
      // The link is what a plain anchor (the dashboard preview) carries
      // to the same effect: the inbox, with the drawer addressed.
      primaryAction: {
        labelKey: `tasks.type.${type}.cta`,
        link: ['/tasks'],
        query: { open: `appointment:${id}`, ...(action ? { action } : {}) },
        drawer: { entity: 'appointment', id, action },
      },
      secondaryActions: [
        { labelKey: 'tasks.openList', link: ['/appointments'], query: { ...view, status, focus: String(id) } },
        ...(childId ? [{ labelKey: 'tasks.openChild', link: ['/children', childId] }] : []),
      ],
    };
  })),
);

export const TASK_CATALOG: readonly TaskSource[] = [
  {
    type:'CHAT_READ',entity:'CONVERSATION',permission:'PORTAL.VIEW',
    fetch:ctx=>ctx.crud.chatContacts().pipe(map(rows=>rows.filter(row=>num(row,'user_id')>0 && num(row,'unread')>0).map((row):Task=>({
      id:'CHAT_READ:'+num(row,'user_id'),taskType:'CHAT_READ',entityType:'CONVERSATION',entityId:num(row,'user_id'),
      titleKey:'tasks.type.CHAT_READ.title',descriptionKey:'tasks.type.CHAT_READ.action',
      entityDisplayName:text(row,'name'),meta:text(row,'last_message'),
      status:'UNREAD',statusKey:'tasks.chatUnread',statusTone:'hbh-badge--info',priority:'normal',
      assignedRole:'PORTAL.VIEW',assignedUser:'me',createdAt:text(row,'last_at'),
      primaryAction:{labelKey:'tasks.type.CHAT_READ.cta',link:['/communications'],query:{peer:String(num(row,'user_id'))}},secondaryActions:[],
    })))),
  },
  {
    type: 'ENROLMENT_TRIAGE', entity: 'APPLICATION', permission: 'ENROLMENT.MANAGE',
    fetch: (ctx) => enrolmentTask('ENROLMENT_TRIAGE', 'NEW', ctx, 24),
  },
  {
    type: 'ENROLMENT_BOOK_ASSESSMENT', entity: 'APPLICATION', permission: 'ENROLMENT.MANAGE',
    fetch: (ctx) => enrolmentTask('ENROLMENT_BOOK_ASSESSMENT', 'CONTACTED', ctx, 72),
  },
  {
    type: 'ENROLMENT_CONVERT', entity: 'APPLICATION', permission: 'ENROLMENT.MANAGE',
    fetch: (ctx) => enrolmentTask('ENROLMENT_CONVERT', 'ASSESSMENT_BOOKED', ctx, 24 * 14),
  },
  {
    type: 'APPOINTMENT_CONFIRM', entity: 'APPOINTMENT', permission: 'APPOINTMENT.BOOK',
    fetch: (ctx) => appointmentTask('APPOINTMENT_CONFIRM', 'BOOKED', ctx,
      () => true, (row) => within(text(row, 'starts_at'), 120, ctx.now), 'APPOINTMENT.BOOK'),
  },
  {
    type: 'APPOINTMENT_CHECK_IN', entity: 'APPOINTMENT', permission: 'APPOINTMENT.BOOK',
    // Confirmed and about to start: the family is expected at the door.
    fetch: (ctx) => appointmentTask('APPOINTMENT_CHECK_IN', 'CONFIRMED', ctx,
      (row) => within(text(row, 'starts_at'), 15, ctx.now), () => true, 'APPOINTMENT.BOOK'),
  },
  {
    type: 'SESSION_START', entity: 'APPOINTMENT', permission: 'SESSION.START',
    // The same three conditions as day-spec's `start` action and the
    // dashboard's shortcut: CHECKED_IN, no session yet. Copied, not widened.
    fetch: (ctx) => appointmentTask('SESSION_START', 'CHECKED_IN', ctx,
      (row) => row['session_id'] == null, () => true, 'SESSION.START', mineIf(ctx)),
  },
  {
    type: 'SESSION_CLOSE', entity: 'SESSION', permission: 'SESSION.COMPLETE',
    fetch: (ctx) => list(ctx, 'sessions', {
      from: new Date(ctx.now.getTime() - 30 * 86_400_000).toISOString(),
      to: ctx.now.toISOString(), status: 'IN_PROGRESS', ...mineIf(ctx),
    })
      .pipe(map((rows) => rows.map((row): Task => {
        const id = num(row, 'session_id');
        const childId = refId(row, 'child', 'child_id');
        const mine = ctx.therapistId !== undefined
          && refId(row, 'therapist', 'therapist_id') === ctx.therapistId;
        return {
          id: `SESSION_CLOSE:${id}`,
          taskType: 'SESSION_CLOSE',
          titleKey: 'tasks.type.SESSION_CLOSE.title',
          descriptionKey: 'tasks.type.SESSION_CLOSE.action',
          entityType: 'SESSION',
          entityId: id,
          entityDisplayName: ref(row, 'child', 'full_name_ar'),
          childName: ref(row, 'child', 'full_name_ar'),
          childId,
          meta: [ref(row, 'service', 'name_ar'), ref(row, 'therapist', 'full_name_ar')].filter(Boolean).join(' · '),
          status: 'IN_PROGRESS',
          statusKey: `${SESSIONS_SPEC.statusPrefix}IN_PROGRESS`,
          statusTone: SESSIONS_SPEC.tone('IN_PROGRESS'),
          // A session running longer than two hours is one somebody forgot to close.
          priority: priority(olderThan(text(row, 'started_at'), 2, ctx.now)),
          assignedRole: 'SESSION.COMPLETE',
          assignedUser: mine ? 'me' : undefined,
          createdAt: text(row, 'started_at'),
          primaryAction: {
            labelKey: 'tasks.type.SESSION_CLOSE.cta',
            link: ['/sessions'], query: {
              status: 'IN_PROGRESS', focus: String(id),
              date: ctx.format.today(new Date(text(row, 'started_at'))),
              ...(mineIf(ctx).mine ? { view: 'mine' } : {}),
            },
          },
          secondaryActions: childId ? [{ labelKey: 'tasks.openChild', link: ['/children', childId] }] : [],
        };
      }))),
  },
  {
    type: 'REPORT_FINISH', entity: 'REPORT', permission: 'REPORT.WRITE',
    fetch: (ctx) => list(ctx, 'reports', { status: 'DRAFT' }).pipe(map((rows) => rows.map((row): Task => {
      const id = num(row, 'report_id');
      const childId = refId(row, 'child', 'child_id');
      return {
        id: `REPORT_FINISH:${id}`,
        taskType: 'REPORT_FINISH',
        titleKey: 'tasks.type.REPORT_FINISH.title',
        descriptionKey: 'tasks.type.REPORT_FINISH.action',
        entityType: 'REPORT',
        entityId: id,
        entityNo: text(row, 'report_no'),
        entityDisplayName: ref(row, 'child', 'full_name_ar'),
        childName: ref(row, 'child', 'full_name_ar'),
        childId,
        meta: text(row, 'title_ar'),
        status: 'DRAFT',
        statusKey: `${REPORTS_SPEC.statusPrefix}DRAFT`,
        statusTone: REPORTS_SPEC.tone('DRAFT'),
        priority: 'normal',
        assignedRole: 'REPORT.WRITE',
        // The editor is where a draft is finished; the list only publishes.
        primaryAction: childId
          ? { labelKey: 'tasks.type.REPORT_FINISH.cta', link: ['/children', childId, 'reports', id] }
          : { labelKey: 'tasks.type.REPORT_FINISH.cta', link: ['/reports'], query: { status: 'DRAFT', focus: String(id) } },
        secondaryActions: [{ labelKey: 'tasks.openList', link: ['/reports'], query: { status: 'DRAFT', focus: String(id) } }],
      };
    }))),
  },
  {
    type: 'REQUEST_DECIDE', entity: 'REQUEST', permission: 'REQUEST.MANAGE',
    fetch: (ctx) => list(ctx, 'requests', { status: 'NEW' }).pipe(map((rows) => rows.map((row): Task => {
      const id = num(row, 'request_id');
      const childId = refId(row, 'child', 'child_id');
      const kind = text(row, 'kind_code');
      return {
        id: `REQUEST_DECIDE:${id}`,
        taskType: 'REQUEST_DECIDE',
        titleKey: 'tasks.type.REQUEST_DECIDE.title',
        descriptionKey: 'tasks.type.REQUEST_DECIDE.action',
        entityType: 'REQUEST',
        entityId: id,
        entityNo: text(row, 'request_no'),
        entityDisplayName: ref(row, 'child', 'full_name_ar'),
        childName: ref(row, 'child', 'full_name_ar'),
        parentName: ref(row, 'guardian', 'full_name_ar'),
        childId,
        metaKey: kind ? `${REQUESTS_SPEC.kindPrefix ?? 'kind.request.'}${kind}` : undefined,
        status: 'NEW',
        statusKey: `${REQUESTS_SPEC.statusPrefix}NEW`,
        statusTone: REQUESTS_SPEC.tone('NEW'),
        priority: priority(olderThan(text(row, 'created_at'), 24, ctx.now)),
        assignedRole: 'REQUEST.MANAGE',
        createdAt: text(row, 'created_at'),
        primaryAction: {
          labelKey: 'tasks.type.REQUEST_DECIDE.cta',
          link: ['/requests'], query: { status: 'NEW', focus: String(id) },
        },
        secondaryActions: childId ? [{ labelKey: 'tasks.openChild', link: ['/children', childId] }] : [],
      };
    }))),
  },
  {
    type: 'INVOICE_ISSUE', entity: 'INVOICE', permission: 'BILLING.MANAGE',
    fetch: (ctx) => list(ctx, 'invoices', { status: 'DRAFT' }).pipe(map((rows) => rows.map((row) =>
      invoiceTask('INVOICE_ISSUE', row, 'BILLING.MANAGE', 'normal')))),
  },
  {
    type: 'INVOICE_OVERDUE', entity: 'INVOICE', permission: 'BILLING.VIEW',
    // Two filters the service cannot combine; asked twice, shown once.
    // "Overdue" is due_date before today - displayed, never stored.
    fetch: (ctx) => forkJoin([
      list(ctx, 'invoices', { status: 'ISSUED' }),
      list(ctx, 'invoices', { status: 'PARTIALLY_PAID' }),
    ]).pipe(map(([issued, partial]) => [...issued, ...partial]
      .filter((row) => text(row, 'due_date') !== '' && text(row, 'due_date') < ctx.today)
      .map((row) => invoiceTask('INVOICE_OVERDUE', row, 'BILLING.VIEW',
        priority(text(row, 'due_date') < shiftDays(ctx.today, -7)))))),
  },
  {
    type: 'CHILD_ASSIGN_THERAPIST', entity: 'BENEFICIARY', permission: 'STAFF.MANAGE',
    // Absence only means unassigned after both lists have been read fully.
    fetch: (ctx) => forkJoin([
      readAllPages((page) => ctx.crud.list('children', { limit: 100, page })),
      readAllPages((page) => ctx.crud.list('caseload', { limit: 100, page })),
    ]).pipe(map(([children, caseload]) => {
      const assigned = new Set(caseload.map((row) => num(row, 'child_id')));
      return children
        .filter((row) => text(row, 'status') === 'ACTIVE' && !assigned.has(num(row, 'child_id')))
        .map((row): Task => {
          const id = num(row, 'child_id');
          return {
            id: `CHILD_ASSIGN_THERAPIST:${id}`,
            taskType: 'CHILD_ASSIGN_THERAPIST',
            titleKey: 'tasks.type.CHILD_ASSIGN_THERAPIST.title',
            descriptionKey: 'tasks.type.CHILD_ASSIGN_THERAPIST.action',
            entityType: 'BENEFICIARY',
            entityId: id,
            entityNo: text(row, 'child_no'),
            entityDisplayName: text(row, 'full_name_ar'),
            childName: text(row, 'full_name_ar'),
            childId: id,
            priority: 'normal',
            assignedRole: 'STAFF.MANAGE',
            primaryAction: { labelKey: 'tasks.type.CHILD_ASSIGN_THERAPIST.cta', link: ['/children', id], query: { action: 'assign' } },
            secondaryActions: [{ labelKey: 'tasks.openChild', link: ['/children', id] }],
          };
        });
    })),
  },
  {
    type: 'THERAPIST_PROFILE_CONSENT', entity: 'THERAPIST', permission: 'PORTAL.VIEW',
    // Addressed to the therapist themself: the one consent nobody else can record.
    fetch: (ctx) => ctx.therapistId === undefined ? of([]) : ctx.crud.get('therapists', ctx.therapistId).pipe(
      map((row): readonly Task[] => {
        if (text(row, 'profile_status') !== 'DRAFT' || text(row, 'consent_at') !== '') {
          return [];
        }
        const id = ctx.therapistId as number;
        return [{
          id: `THERAPIST_PROFILE_CONSENT:${id}`,
          taskType: 'THERAPIST_PROFILE_CONSENT',
          titleKey: 'tasks.type.THERAPIST_PROFILE_CONSENT.title',
          descriptionKey: 'tasks.type.THERAPIST_PROFILE_CONSENT.action',
          entityType: 'THERAPIST',
          entityId: id,
          entityDisplayName: text(row, 'full_name_ar'),
          status: 'DRAFT',
          statusKey: 'status.profile.DRAFT',
          statusTone: 'hbh-badge--muted',
          priority: 'normal',
          assignedRole: 'PORTAL.VIEW',
          assignedUser: 'me',
          primaryAction: { labelKey: 'tasks.type.THERAPIST_PROFILE_CONSENT.cta', link: ['/therapists', id, 'profile'] },
          secondaryActions: [],
        }];
      })),
  },
  {
    type: 'SCHEDULE_CONFLICT', entity: 'APPOINTMENT', permission: 'APPOINTMENT.BOOK',
    // The same overlap the appointments screen lists under "تداخلات": two
    // live appointments sharing a therapist or a room and an hour.
    fetch: (ctx) => list(ctx, 'appointments', { date: ctx.today }).pipe(map((rows) => {
      const live = rows.filter((row) => ['BOOKED', 'CONFIRMED', 'CHECKED_IN'].includes(text(row, 'status')));
      const out: Task[] = [];
      for (let i = 0; i < live.length; i++) {
        for (let j = i + 1; j < live.length; j++) {
          const a = live[i]; const b = live[j];
          const sameTherapist = refId(a, 'therapist', 'therapist_id') !== undefined
            && refId(a, 'therapist', 'therapist_id') === refId(b, 'therapist', 'therapist_id');
          const sameRoom = refId(a, 'room', 'room_id') !== undefined
            && refId(a, 'room', 'room_id') === refId(b, 'room', 'room_id');
          const overlap = text(a, 'starts_at') < text(b, 'ends_at') && text(b, 'starts_at') < text(a, 'ends_at');
          if ((sameTherapist || sameRoom) && overlap) {
            const idA = num(a, 'appointment_id'); const idB = num(b, 'appointment_id');
            out.push({
              id: `SCHEDULE_CONFLICT:${idA}:${idB}`,
              taskType: 'SCHEDULE_CONFLICT',
              titleKey: 'tasks.type.SCHEDULE_CONFLICT.title',
              descriptionKey: 'tasks.type.SCHEDULE_CONFLICT.action',
              entityType: 'APPOINTMENT',
              entityId: idA,
              entityDisplayName: `${ref(a, 'child', 'full_name_ar')} / ${ref(b, 'child', 'full_name_ar')}`,
              meta: sameTherapist ? ref(a, 'therapist', 'full_name_ar') : ref(a, 'room', 'name_ar'),
              priority: 'urgent',
              assignedRole: 'APPOINTMENT.BOOK',
              dueDate: text(a, 'starts_at') < text(b, 'starts_at') ? text(a, 'starts_at') : text(b, 'starts_at'),
              row: a,
              // Both sides of the clash open in the drawer; the diary link
              // stays for seeing them side by side.
              primaryAction: { labelKey: 'tasks.type.SCHEDULE_CONFLICT.cta', link: ['/tasks'], query: { open: `appointment:${idA}` }, drawer: { entity: 'appointment', id: idA } },
              secondaryActions: [
                { labelKey: 'tasks.openOther', link: ['/tasks'], query: { open: `appointment:${idB}` }, drawer: { entity: 'appointment', id: idB } },
                { labelKey: 'tasks.openList', link: ['/appointments'], query: { focus: String(idA) } },
              ],
            });
          }
        }
      }
      return out;
    })),
  },
];

function invoiceTask(type: TaskType, row: Row, permission: string, prio: TaskPriority): Task {
  const id = num(row, 'invoice_id');
  const childId = refId(row, 'child', 'child_id');
  const status = text(row, 'status');
  return {
    id: `${type}:${id}`,
    taskType: type,
    titleKey: `tasks.type.${type}.title`,
    descriptionKey: `tasks.type.${type}.action`,
    entityType: 'INVOICE',
    entityId: id,
    entityNo: text(row, 'invoice_no'),
    entityDisplayName: ref(row, 'child', 'full_name_ar'),
    childName: ref(row, 'child', 'full_name_ar'),
    childId,
    meta: `${text(row, 'total_amt')} / ${text(row, 'paid_amt')} ${text(row, 'currency_code')}`,
    status,
    statusKey: `${INVOICES_SPEC.statusPrefix}${status}`,
    statusTone: INVOICES_SPEC.tone(status),
    priority: prio,
    assignedRole: permission,
    dueDate: type === 'INVOICE_OVERDUE' ? `${text(row, 'due_date')}T00:00:00Z` : undefined,
    createdAt: text(row, 'issue_date') ? `${text(row, 'issue_date')}T00:00:00Z` : undefined,
    row,
    // A draft opens with "issue" proposed. An overdue one opens plain: what
    // may be done about it - a payment, for BILLING.MANAGE; nothing, for
    // BILLING.VIEW (OQ-13) - is the drawer's to offer by permission.
    primaryAction: {
      labelKey: `tasks.type.${type}.cta`,
      link: ['/tasks'],
      query: { open: `invoice:${id}`, ...(type === 'INVOICE_ISSUE' ? { action: 'issue' } : {}) },
      drawer: { entity: 'invoice', id, action: type === 'INVOICE_ISSUE' ? 'issue' : undefined },
    },
    secondaryActions: [
      { labelKey: 'tasks.openList', link: ['/billing'], query: { status, focus: String(id) } },
      ...(childId ? [{ labelKey: 'tasks.openChild', link: ['/children', childId] }] : []),
    ],
  };
}

/** YYYY-MM-DD shifted by whole days, for a display threshold only. */
function shiftDays(day: string, delta: number): string {
  const at = new Date(`${day}T00:00:00Z`);
  at.setUTCDate(at.getUTCDate() + delta);
  return at.toISOString().slice(0, 10);
}
