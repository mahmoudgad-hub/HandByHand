import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';

/** GET /api/v1/notifications, verbatim. */
interface FeedResponse {
  readonly rows: readonly {
    readonly notification_id: number;
    readonly kind_code: string;
    readonly title_ar: string;
    readonly body_ar?: string | null;
    readonly link_kind?: string | null;
    readonly link_id?: number | null;
    readonly child_id?: number | null;
    readonly read_at?: string | null;
    readonly created_at: string;
  }[];
  readonly unread: number;
  readonly total: number;
}

export interface InboxItem {
  readonly id: number;
  readonly kind: string;
  readonly title: string;
  readonly body: string;
  readonly at: string;
  readonly read: boolean;
  /** Where this item leads, or null when it leads nowhere. */
  readonly targetQuery?: {peer:number};
  readonly target: readonly (string | number)[] | null;
}

export interface Inbox {
  readonly rows: readonly InboxItem[];
  readonly unread: number;
  readonly total: number;
}

/**
 * What the centre has told THIS member of staff.
 *
 * The table, the triggers and this route have all existed for a while and
 * the console never read them: hbh.notifications was filling up for
 * guardians only because the parent portal had a screen and this one did
 * not. A therapist given a new child, a receptionist with a request to
 * answer - the row was written and nobody could see it.
 *
 * THE FEED IS ALREADY SCOPED TO THE CALLER. The policy on the table is
 * `user_id = hbh.current_user_id()`, so there is no "whose inbox" parameter
 * here and there must never be one: an inbox that takes a user id is an
 * inbox somebody can address to somebody else.
 */
@Injectable({ providedIn: 'root' })
export class InboxApi {
  private readonly http = inject(HttpClient);
  private readonly base = `${inject(HBH_CONFIG).apiBaseUrl}/api/v1`;

  list(limit = 50): Observable<Inbox> {
    return this.http.get<FeedResponse>(`${this.base}/notifications`, {
      params: { limit },
    }).pipe(map((body) => ({
      unread: body.unread,
      total: body.total,
      rows: body.rows.map((row) => ({
        id: row.notification_id,
        kind: row.kind_code,
        title: row.title_ar,
        body: row.body_ar ?? '',
        at: row.created_at,
        read: !!row.read_at,
        targetQuery: row.link_kind==='CHAT' && row.link_id ? {peer:row.link_id} : undefined,
        target: InboxApi.target(row.link_kind, row.link_id, row.child_id),
      })),
    })));
  }

  markRead(id: number): Observable<unknown> {
    return this.http.post(`${this.base}/notifications/${id}/read`, {});
  }

  /**
   * Mark the whole feed read. Answers how many rows actually moved.
   *
   * IT NAMES NOBODY, and that is the point of the shape. "All" is decided by
   * hbh.mark_all_notifications_read() from the caller's own identity, so
   * there is no body and no parameter - an endpoint that took a user id
   * would be a way to clear somebody else's bell.
   *
   * The count is the service's answer, not a number counted here. A feed
   * shows the newest fifty; the write clears every unread row the person
   * has, so a screen that reported its own visible count would understate
   * what it just did.
   */
  markAllRead(): Observable<number> {
    return this.http
      .post<{ marked?: number }>(`${this.base}/notifications/read-all`, {})
      .pipe(map((body) => body.marked ?? 0));
  }

  /**
   * Where an item leads.
   *
   * A notification that names a thing and cannot open it is a to-do list
   * item with the doing removed - which is most of the value of an inbox.
   * The row already carries link_kind and link_id; this turns them into the
   * console's own routes.
   *
   * An unknown kind returns null and the item is still shown, unclickable.
   * Guessing a route from a kind this build has not been taught would send
   * somebody to a screen that says "not found" about a thing that exists.
   */
  private static target(
    kind: string | null | undefined,
    id: number | null | undefined,
    childId: number | null | undefined,
  ): readonly (string | number)[] | null {
    if(kind==='CHAT' && id) return ['/communications'];
    if (kind === 'CHILD' && id) {
      return ['/children', id];
    }
    if (kind === 'REPORT' && id) {
      return ['/reports'];
    }
    if (kind === 'REQUEST' && id) {
      return ['/requests'];
    }
    if (kind === 'APPOINTMENT' && id) {
      return ['/appointments'];
    }
    if (kind === 'INVOICE' && id) {
      // /billing, not /invoices: there has never been an /invoices route, so
      // this link fell through the wildcard onto the dashboard and the person
      // never saw the invoice they were told about.
      return ['/billing'];
    }
    // No link of its own, but it names a child - open the child.
    if (childId) {
      return ['/children', childId];
    }
    return null;
  }
}
