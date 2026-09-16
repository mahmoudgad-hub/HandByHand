import { Injectable, inject, signal } from '@angular/core';
import { Observable, Subject, catchError, map, of, switchMap } from 'rxjs';

import { OpsApi, OpsResource, Row } from '../api/ops-api';
import { OpsAuthService } from '../auth/ops-auth.service';
import {
  CASELOAD_SPEC, CHILDREN_SPEC, CHILD_ACTIVITIES_SPEC, GOALS_SPEC, GUARDIANS_SPEC,
  MEASUREMENTS_SPEC, PLANS_SPEC, ResourceSpec,
} from '../resource/resource-spec';
import {
  ActionOutcome, ActionRequest, EmbeddedAction, EmbeddedResource, ResourceRequest,
} from './action-request';
import { DayApi, DayResource } from './day-api';
import {
  APPOINTMENTS_SPEC, CreateAction, DayAction, DaySpec, ENROLMENTS_SPEC, INVOICES_SPEC,
  REPORTS_SPEC, REQUESTS_SPEC, SESSIONS_SPEC,
} from './day-spec';

/**
 * Opens an existing dialog from anywhere.
 *
 * AN ORCHESTRATOR AND NOTHING ELSE. For a day action it finds the action by
 * the key it has in day-spec.ts, asks the same two questions the list
 * screen asks before drawing the button - does the account hold the
 * permission, does the action apply to this row - and hands the action,
 * the row and the spec to one embedded DayScreen (ActionDialogHost) that
 * draws the dialog the list draws. For a resource it does the same with
 * ResourceScreen's editor. The confirm inside the dialog is the only thing
 * that mutates, and it runs the action's own `run` or the resource's own
 * create/update. This file holds no business rule and copies none.
 *
 * Both checks are DRAWING decisions. The server refuses the write
 * regardless of what this service concluded.
 */
@Injectable({ providedIn: 'root' })
export class ActionDialogService {
  private readonly auth = inject(OpsAuthService);
  private readonly day = inject(DayApi);
  private readonly crud = inject(OpsApi);

  /** The day-action dialog currently open, drawn by the host in the shell. */
  readonly active = signal<EmbeddedAction | null>(null);
  /** The resource editor currently open, drawn by the same host. */
  readonly activeResource = signal<EmbeddedResource | null>(null);

  /**
   * Opens a day action's dialog and resolves once with what happened.
   *
   * Resolves DENIED / NOT_APPLICABLE / UNKNOWN_ACTION / NOT_FOUND without
   * drawing anything, so a caller can say why in its own words; DONE or
   * CANCELLED after the person closed the dialog.
   */
  open(request: ActionRequest): Observable<ActionOutcome> {
    const spec = SPEC_BY_RESOURCE[request.entityType];
    const rowAction = spec?.actions.find((item) => item.key === request.actionType);
    const create = spec?.create?.find((item) => item.key === request.actionType);
    const action: DayAction | CreateAction | undefined = rowAction ?? create;
    if (!spec || !action || (rowAction && rowAction.link)) {
      return of('UNKNOWN_ACTION');
    }
    if (!this.auth.can(action.permission)) {
      return of('DENIED');
    }
    if (create) {
      // A create belongs to the screen, not to a row: nothing to read, no
      // state to be in.
      return this.draw(request, spec, create, null);
    }
    const row$: Observable<Row | null> = request.row
      ? of(request.row)
      : request.entityId
        ? this.day.get(request.entityType, request.entityId).pipe(catchError(() => of(null)))
        : of(null);

    return row$.pipe(switchMap((row) => {
      if (!row) {
        return of<ActionOutcome>('NOT_FOUND');
      }
      if (!(rowAction as DayAction).when(row)) {
        return of<ActionOutcome>('NOT_APPLICABLE');
      }
      return this.draw(request, spec, rowAction as DayAction, row);
    }));
  }

  /**
   * Opens a CRUD resource's editor - the one ResourceScreen draws - on a
   * new row (with pre-filled fields) or an existing one.
   */
  openResource(request: ResourceRequest): Observable<ActionOutcome> {
    const spec = RESOURCE_SPECS[request.resource];
    if (!spec) {
      return of('UNKNOWN_ACTION');
    }
    if (!this.auth.can(spec.writePermission)) {
      return of('DENIED');
    }
    if (request.mode === 'create') {
      return this.drawResource(request, spec, null);
    }
    const row$: Observable<Row | null> = request.row
      ? of(request.row)
      : request.entityId
        ? this.crud.get(request.resource, request.entityId).pipe(catchError(() => of(null)))
        : of(null);
    return row$.pipe(switchMap((row) => (row ? this.drawResource(request, spec, row) : of<ActionOutcome>('NOT_FOUND'))));
  }

  /** Whether `open` would draw a row action, for a caller deciding whether to offer a button. */
  canOffer(entityType: DayResource, actionType: string, row: Row): boolean {
    const action = SPEC_BY_RESOURCE[entityType]?.actions.find((item) => item.key === actionType);
    return !!action && !action.link && this.auth.can(action.permission) && action.when(row);
  }

  /** Whether `open` would draw a create action. */
  canCreate(entityType: DayResource, actionType: string): boolean {
    const action = SPEC_BY_RESOURCE[entityType]?.create?.find((item) => item.key === actionType);
    return !!action && this.auth.can(action.permission);
  }

  /** Whether `openResource` would draw for this resource. */
  canWriteResource(resource: OpsResource): boolean {
    const spec = RESOURCE_SPECS[resource];
    return !!spec && this.auth.can(spec.writePermission);
  }

  /** Closes whatever is open, as a cancel. Used when the caller navigates away. */
  dismiss(): void {
    this.active()?.onClose(false);
    this.activeResource()?.onClose(false);
  }

  private draw(request: ActionRequest, spec: DaySpec, action: DayAction | CreateAction, row: Row | null): Observable<ActionOutcome> {
    const closed = new Subject<boolean>();
    let settled = false;
    this.active.set({
      request, spec, action, row,
      onClose: (done) => {
        if (settled) {
          return;
        }
        settled = true;
        this.active.set(null);
        closed.next(done);
        closed.complete();
      },
    });
    return closed.pipe(map((done): ActionOutcome => (done ? 'DONE' : 'CANCELLED')));
  }

  private drawResource(request: ResourceRequest, spec: ResourceSpec, row: Row | null): Observable<ActionOutcome> {
    const closed = new Subject<boolean>();
    let settled = false;
    this.activeResource.set({
      request, spec, row,
      onClose: (done) => {
        if (settled) {
          return;
        }
        settled = true;
        this.activeResource.set(null);
        closed.next(done);
        closed.complete();
      },
    });
    return closed.pipe(map((done): ActionOutcome => (done ? 'DONE' : 'CANCELLED')));
  }
}

const SPEC_BY_RESOURCE: Readonly<Record<DayResource, DaySpec>> = {
  appointments: APPOINTMENTS_SPEC,
  sessions: SESSIONS_SPEC,
  reports: REPORTS_SPEC,
  invoices: INVOICES_SPEC,
  requests: REQUESTS_SPEC,
  enrolments: ENROLMENTS_SPEC,
};

/** The resources whose editor may be opened from a detail page. Others keep their list screen. */
const RESOURCE_SPECS: Partial<Readonly<Record<OpsResource, ResourceSpec>>> = {
  caseload: CASELOAD_SPEC,
  plans: PLANS_SPEC,
  goals: GOALS_SPEC,
  measurements: MEASUREMENTS_SPEC,
  'child-activities': CHILD_ACTIVITIES_SPEC,
  guardians: GUARDIANS_SPEC,
  children: CHILDREN_SPEC,
};
