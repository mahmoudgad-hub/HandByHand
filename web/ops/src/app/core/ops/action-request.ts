import { OpsResource, Row } from '../api/ops-api';
import { ResourceSpec } from '../resource/resource-spec';
import { DayResource } from './day-api';
import { CreateAction, DayAction, DaySpec } from './day-spec';

/**
 * A request to open one of the console's existing dialogs from somewhere
 * other than the list screen that owns it - a task card, the application
 * detail, the child's file, the guardian's page.
 *
 * NOTHING HERE IS A RULE. The action is named by the key it already has in
 * day-spec.ts (or the resource it already has in resource-spec.ts); whether
 * it may be opened is decided by the same permission and the same
 * `when(row)` the list screen consults; what it does is the same `run` or
 * the same CRUD create/update. The service that takes this is an
 * orchestrator: it finds the action, checks it the way the list would, and
 * draws the dialog the list draws. It never performs the mutation itself,
 * and a request never runs anything without the person pressing confirm.
 */
export type ActionSource =
  | 'TASK_INBOX' | 'ENROLMENT_DETAIL' | 'DASHBOARD' | 'CHILD_PROFILE'
  | 'GUARDIAN_DETAIL' | 'DEEP_LINK' | 'RECORD_DRAWER' | 'LIST';

export interface ActionRequest {
  /** The action's key in its DaySpec: a row action ('status', 'convert', 'pay', …) or a create ('book', 'newInvoice', 'sell'). */
  readonly actionType: string;
  /** The day resource the row belongs to. */
  readonly entityType: DayResource;
  /** The row's id. Ignored for a create action, which belongs to no row. */
  readonly entityId?: number;
  /** The row, when the caller already holds it. Otherwise it is read (where the service has a single-row read). */
  readonly row?: Row;
  readonly source: ActionSource;
  /** Where the caller wants to be sent back to, if anywhere. */
  readonly returnUrl?: string;
  /** Field values to open the dialog with (a status to pre-select, a child id to book for). */
  readonly prefill?: Readonly<Record<string, string>>;
  /** What a pre-filled id reads as, for pickers that show a name rather than a number. */
  readonly prefillLabels?: Readonly<Record<string, string>>;
}

/** A request to open a CRUD resource's own editor (resource-spec.ts) on a new or existing row. */
export interface ResourceRequest {
  readonly resource: OpsResource;
  readonly mode: 'create' | 'edit';
  /** For edit: the row's id, or the row itself. */
  readonly entityId?: number;
  readonly row?: Row;
  readonly source: ActionSource;
  /** Field values to open the editor with (a child id, a plan id). */
  readonly prefill?: Readonly<Record<string, string>>;
}

export type ActionOutcome =
  | 'DONE'            // the dialog's confirm ran and the server accepted
  | 'CANCELLED'       // closed without running
  | 'DENIED'          // the account lacks the action's permission
  | 'NOT_APPLICABLE'  // the row is not in a state the action applies to
  | 'NOT_FOUND'       // the row could not be read
  | 'UNKNOWN_ACTION'; // no such action key on that resource

/** What the embedded DayScreen receives in place of its route data. */
export interface EmbeddedAction {
  readonly request: ActionRequest;
  readonly spec: DaySpec;
  readonly action: DayAction | CreateAction;
  /** Null for a create action. */
  readonly row: Row | null;
  /** Called exactly once when the dialog closes. `done` is true after a successful confirm. */
  readonly onClose: (done: boolean) => void;
}

/** What the embedded ResourceScreen receives in place of its route data. */
export interface EmbeddedResource {
  readonly request: ResourceRequest;
  readonly spec: ResourceSpec;
  /** The row being edited, or null for a create. */
  readonly row: Row | null;
  readonly onClose: (done: boolean) => void;
}
