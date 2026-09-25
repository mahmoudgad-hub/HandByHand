import { Location } from '@angular/common';
import { Injectable, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { NavigationEnd, Router } from '@angular/router';
import { Observable, Subject, filter } from 'rxjs';

import { Row } from '../api/ops-api';
import { ActionSource } from './action-request';
import {
  DrawerActionName, DrawerContext, DrawerRequest, DrawerTarget, formatOpen, isDrawerAction,
  parseOpen, sameTarget,
} from './record-drawer';

/** The drawer that is open, as the host draws it. */
export interface DrawerState {
  readonly target: DrawerTarget;
  /** The row the caller handed over, or null when the host must locate it. */
  readonly row: Row | null;
  readonly context: DrawerContext | undefined;
  readonly source: ActionSource;
  readonly action: DrawerActionName | undefined;
  /**
   * True when THIS service pushed the `?open=` entry onto the history.
   * Closing such a drawer steps back, so the address bar and the
   * back button agree; a drawer that arrived in the address (a link, a
   * refresh) is closed by rewriting the address in place instead - the
   * person is on the page they were sent to and should stay there.
   */
  readonly pushed: boolean;
  /** What had focus when the drawer opened, to return to on close. */
  readonly opener: HTMLElement | null;
}

/**
 * Opens and closes the record drawer, and keeps it in step with the URL.
 *
 * ONE SOURCE OF TRUTH FOR "IS A DRAWER OPEN": the address bar. `open()`
 * writes `?open=` and the host draws whatever the address says; the back
 * button, a refresh and a pasted link all go through the same path, so
 * there is no way for the screen and the address to disagree.
 *
 * The row is REMEMBERED, not required. A list that opens a drawer on a
 * row it already holds passes it along and nothing is read; a link with
 * only an id lets the host locate the row itself.
 */
@Injectable({ providedIn: 'root' })
export class RecordDrawerService {
  private readonly router = inject(Router);
  private readonly location = inject(Location);

  readonly active = signal<DrawerState | null>(null);

  /** Rows handed over by callers, by `entity:id`, so a re-open costs no read. */
  private readonly rows = new Map<string, Row>();

  private readonly changedSubject = new Subject<DrawerTarget>();
  /**
   * Fires after an action confirmed from the drawer succeeded. The screen
   * behind it re-reads the part it shows the record in - and only that
   * part; the rest of the page is untouched.
   */
  readonly changed$: Observable<DrawerTarget> = this.changedSubject.asObservable();

  constructor() {
    this.router.events.pipe(
      filter((event) => event instanceof NavigationEnd),
      takeUntilDestroyed(),
    ).subscribe(() => this.syncFromUrl());
    this.syncFromUrl();
  }

  /** Opens the drawer on a record, from a screen that names it. Resolves once the address is written. */
  open(request: DrawerRequest): Promise<void> {
    const target: DrawerTarget = { entity: request.entity, id: request.id };
    if (request.row) {
      this.rows.set(formatOpen(target), request.row);
    }
    const focused = typeof document === 'undefined' ? null : document.activeElement;
    const current = this.active();
    this.active.set({
      target,
      row: request.row ?? this.rows.get(formatOpen(target)) ?? null,
      context: request.context,
      source: request.source,
      action: request.action,
      // A drawer replacing another keeps the first one's history entry:
      // one step back closes both, which is what "back" means here.
      pushed: current?.pushed ?? true,
      opener: current?.opener ?? (focused instanceof HTMLElement ? focused : null),
    });
    // The step is NOT written to the address. It is offered the moment the
    // record is drawn and consumed at once, so an address that named it
    // would propose the step again on every refresh; only a link that
    // arrives with ?action= carries one, and consumeAction takes it off.
    const tree = this.router.parseUrl(this.router.url);
    tree.queryParams = { ...tree.queryParams, open: formatOpen(target) };
    delete tree.queryParams['recordAt'];
    const startsAt = request.row?.['starts_at'];
    if (target.entity === 'appointment' && typeof startsAt === 'string' && Number.isFinite(Date.parse(startsAt))) {
      tree.queryParams['recordAt'] = new Date(startsAt).toISOString();
    }
    delete tree.queryParams['action'];
    return this.router.navigateByUrl(tree, { replaceUrl: !!current }).then(() => undefined);
  }

  /** Closes it. The address is what closes the drawer; this only asks. */
  close(): Promise<void> {
    const current = this.active();
    if (!current) {
      return Promise.resolve();
    }
    if (current.pushed) {
      this.location.back();
      return Promise.resolve();
    }
    const tree = this.router.parseUrl(this.router.url);
    delete tree.queryParams['open'];
    delete tree.queryParams['recordAt'];
    delete tree.queryParams['action'];
    return this.router.navigateByUrl(tree, { replaceUrl: true }).then(() => undefined);
  }

  /**
   * Takes `?action=` off the address once its dialog has been offered, so
   * a refresh shows the record and does not propose the step again.
   */
  consumeAction(): Promise<void> {
    const current = this.active();
    if (!current?.action) {
      return Promise.resolve();
    }
    this.active.set({ ...current, action: undefined });
    const tree = this.router.parseUrl(this.router.url);
    if (!('action' in tree.queryParams)) {
      return Promise.resolve();
    }
    delete tree.queryParams['action'];
    return this.router.navigateByUrl(tree, { replaceUrl: true }).then(() => undefined);
  }

  /** Keeps a located row, so the next open of the same record costs nothing. */
  remember(target: DrawerTarget, row: Row): void {
    this.rows.set(formatOpen(target), row);
    const current = this.active();
    if (current && sameTarget(current.target, target) && current.row !== row) {
      this.active.set({ ...current, row });
    }
  }

  /** Forgets a row after it changed, so it is read again rather than shown stale. */
  forget(target: DrawerTarget): void {
    this.rows.delete(formatOpen(target));
    const current = this.active();
    if (current && sameTarget(current.target, target) && current.row !== null) {
      this.active.set({ ...current, row: null });
    }
  }

  notifyChanged(target: DrawerTarget): void {
    this.forget(target);
    this.changedSubject.next(target);
  }

  /**
   * Draws what the address says. Called on every navigation end and once
   * at construction, and idempotent: a drawer already open on the same
   * record is left alone, a drawer the address no longer names is closed,
   * and an address naming a record nobody opened from a screen opens it
   * from the address alone.
   */
  private syncFromUrl(): void {
    const params = this.router.parseUrl(this.router.url).queryParams;
    const target = parseOpen(params['open']);
    const current = this.active();
    if (!target) {
      if (current) {
        this.active.set(null);
        this.restoreFocus(current);
      }
      return;
    }
    if (current && sameTarget(current.target, target)) {
      return;
    }
    const action = params['action'];
    this.active.set({
      target,
      row: this.rows.get(formatOpen(target)) ?? null,
      context: undefined,
      source: 'DEEP_LINK',
      action: isDrawerAction(action) ? action : undefined,
      pushed: false,
      opener: null,
    });
  }

  private restoreFocus(closed: DrawerState): void {
    const opener = closed.opener;
    if (opener && opener.isConnected) {
      // After the dialog element is gone: a modal dialog that is still in
      // the top layer takes focus back the moment it is given away.
      setTimeout(() => opener.focus(), 0);
    }
  }
}
