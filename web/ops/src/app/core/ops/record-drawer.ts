import { Row } from '../api/ops-api';
import { ActionSource } from './action-request';
import { DayResource } from './day-api';

/**
 * A record drawer: one appointment or one invoice, shown beside the screen
 * that mentioned it, without leaving that screen.
 *
 * The drawer is addressed in the URL as `?open=appointment:881` (or
 * `invoice:12`), so it survives a refresh, can be linked from a task or a
 * message, and closes on the browser's back button. The value is parsed
 * strictly: anything that is not `<entity>:<positive integer>` is ignored,
 * never guessed at.
 *
 * NOTHING HERE IS A RULE. What a drawer may DO is the owning list's own
 * action set (day-spec.ts), opened through ActionDialogService with the
 * same permission and the same `when(row)` the list consults. A step named
 * in `?action=` opens that dialog and nothing else - it never runs it.
 */
export type DrawerEntity = 'appointment' | 'invoice';

export interface DrawerTarget {
  readonly entity: DrawerEntity;
  readonly id: number;
}

/**
 * What the caller already knows about the record's child, when the row
 * itself does not carry it (the child-scoped reads omit the child).
 */
export interface DrawerContext {
  readonly childId?: number;
  readonly childName?: string;
  readonly childNo?: string;
}

/** The named steps a deep link or a task may ask the drawer to open. */
export type DrawerActionName =
  | 'confirm' | 'check-in' | 'cancel' | 'no-show' | 'status' | 'start'
  | 'issue' | 'pay' | 'add-line';

export interface DrawerRequest extends DrawerTarget {
  /** The row, when the caller holds it. Otherwise the drawer locates it. */
  readonly row?: Row;
  readonly context?: DrawerContext;
  readonly source: ActionSource;
  /** A step to open at once - checked, never run. */
  readonly action?: DrawerActionName;
}

/** A step, resolved to the day-spec action it is a pre-filled form of. */
export interface DrawerStep {
  readonly actionType: string;
  readonly entityType: DayResource;
  readonly prefill?: Readonly<Record<string, string>>;
}

/**
 * The steps, per entity. Each names an action that exists in day-spec.ts
 * and a value to pre-select in it; the dialog still shows the select, and
 * the person still confirms. `status` on its own opens the dialog with
 * nothing chosen.
 */
const STEPS: Readonly<Record<DrawerEntity, Partial<Readonly<Record<DrawerActionName, DrawerStep>>>>> = {
  appointment: {
    confirm: { actionType: 'status', entityType: 'appointments', prefill: { status: 'CONFIRMED' } },
    'check-in': { actionType: 'status', entityType: 'appointments', prefill: { status: 'CHECKED_IN' } },
    cancel: { actionType: 'status', entityType: 'appointments', prefill: { status: 'CANCELLED' } },
    'no-show': { actionType: 'status', entityType: 'appointments', prefill: { status: 'NO_SHOW' } },
    status: { actionType: 'status', entityType: 'appointments' },
    start: { actionType: 'start', entityType: 'appointments' },
  },
  invoice: {
    issue: { actionType: 'issue', entityType: 'invoices' },
    pay: { actionType: 'pay', entityType: 'invoices' },
    'add-line': { actionType: 'addLine', entityType: 'invoices' },
  },
};

/** The day resource a drawer entity's rows belong to. */
export const RESOURCE_OF: Readonly<Record<DrawerEntity, DayResource>> = {
  appointment: 'appointments',
  invoice: 'invoices',
};

/** The step a name means for this entity, or null for a name it has no step for. */
export function stepFor(entity: DrawerEntity, name: string | null | undefined): DrawerStep | null {
  if (!name) {
    return null;
  }
  return STEPS[entity][name as DrawerActionName] ?? null;
}

/** Whether a string is one of the step names at all. */
export function isDrawerAction(name: string | null | undefined): name is DrawerActionName {
  return !!name && (name in STEPS.appointment || name in STEPS.invoice);
}

const OPEN = /^(appointment|invoice):([1-9][0-9]{0,9})$/;

/** `appointment:881` → a target; anything else → null. */
export function parseOpen(value: string | null | undefined): DrawerTarget | null {
  const hit = OPEN.exec(value ?? '');
  if (!hit) {
    return null;
  }
  return { entity: hit[1] as DrawerEntity, id: Number(hit[2]) };
}

export function formatOpen(target: DrawerTarget): string {
  return `${target.entity}:${target.id}`;
}

export function sameTarget(a: DrawerTarget | null | undefined, b: DrawerTarget | null | undefined): boolean {
  return !!a && !!b && a.entity === b.entity && a.id === b.id;
}

/** The child a record is about, as the drawer prints it. */
export interface DrawerChild {
  readonly id: number;
  readonly name: string;
  readonly no: string;
}

/** `/children/604/...` → 604; anything else → null. */
export function childIdFromPath(url: string): number | null {
  const hit = /^\/children\/([1-9][0-9]*)(?:[/?#]|$)/.exec(url);
  return hit ? Number(hit[1]) : null;
}
