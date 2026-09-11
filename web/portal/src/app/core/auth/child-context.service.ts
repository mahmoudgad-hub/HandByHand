import { Injectable, signal } from '@angular/core';

import { Child, Uuid } from '../models/portal.models';

const CHILD_KEY = 'hbh.portal.child';

/**
 * Which child the guardian is currently looking at.
 *
 * The child itself is kept in memory. Only the identifier is written to
 * sessionStorage, and only so that reloading a page - or following a link
 * back into the app - does not throw the guardian back to the picker mid-task.
 *
 * Storing the identifier grants nothing. On reload the child is fetched again
 * through the same call any screen would make, and the server re-checks the
 * guardian's link to that child exactly as it does on every other request. A
 * tampered value resolves to nothing and the guardian lands on the picker,
 * which is the same place an unknown identifier has always led.
 *
 * The identifier is not in the route on purpose: a URL invites the belief
 * that editing it changes what may be seen, and it would sit in browser
 * history on a shared phone.
 */
@Injectable({ providedIn: 'root' })
export class ChildContextService {
  private readonly child = signal<Child | null>(null);

  readonly selected = this.child.asReadonly();

  select(child: Child): void {
    this.child.set(child);
    try {
      sessionStorage.setItem(CHILD_KEY, child.id);
    } catch {
      // Storage blocked: the choice simply does not survive a reload.
    }
  }

  clear(): void {
    this.child.set(null);
    try {
      sessionStorage.removeItem(CHILD_KEY);
    } catch {
      // Nothing to clean up if it was never written.
    }
  }

  /** The identifier left over from a previous page, if there is one. */
  rememberedId(): Uuid | null {
    try {
      return sessionStorage.getItem(CHILD_KEY);
    } catch {
      return null;
    }
  }

  /** Throws rather than guessing: a screen with no child must not query one. */
  requireId(): string {
    const current = this.child();
    if (!current) {
      throw new Error('No child selected');
    }
    return current.id;
  }
}
