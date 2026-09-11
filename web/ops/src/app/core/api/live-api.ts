import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';

/**
 * What the service answers when it lets somebody watch.
 *
 * READ WHAT IS NOT HERE, because it is the design:
 *
 *   No token. The stream credential is set as an HttpOnly cookie scoped to
 *   the playback path, so the browser sends it and no script can read it, and
 *   it never appears in a URL where a proxy log or a browser history would
 *   keep it. This client never sees it and must never try to.
 *
 *   No camera identifier, no gateway path, no address, no credential. The API
 *   talks to the media gateway; this client talks to the API.
 *
 * `playback_path` is a fixed path on the service, identical for every viewer
 * and every session, so it identifies nothing on its own.
 */
export interface StreamGrant {
  readonly playback_path: string;
  readonly expires_at: string;
  /**
   * The window in seconds. Capped at fifteen minutes by the database - in
   * the function that issues the token AND by a constraint on the row - so
   * no caller can widen it. The player renews against this rather than doing
   * clock arithmetic of its own.
   */
  readonly expires_in_seconds: number;
}

@Injectable({ providedIn: 'root' })
export class LiveApi {
  private readonly http = inject(HttpClient);
  private readonly base = `${inject(HBH_CONFIG).apiBaseUrl}/api/v1`;

  /**
   * Asks to watch. Every call is recorded in the audit log with the user, the
   * camera and the time - watching a child in therapy is a sensitive read and
   * the schema logs it explicitly rather than relying on triggers.
   *
   * `withCredentials` because the answer is a cookie. In production the
   * console and the service share an origin; in development they do not, and
   * without this the browser would drop the cookie and the player would get a
   * 401 from a request that looked fine.
   */
  open(sessionId: number): Observable<StreamGrant> {
    return this.http.post<StreamGrant>(
      `${this.base}/sessions/${sessionId}/stream`, {}, { withCredentials: true });
  }

  /**
   * Gives the credential back before it expires.
   *
   * Called when the viewer leaves. Letting it lapse on its own would also be
   * safe - it is fifteen minutes at most - but a token nobody revoked is a
   * token that still works while the person who opened it has walked away.
   */
  close(): Observable<void> {
    return this.http.post<void>(
      `${this.base}/stream/close`, {}, { withCredentials: true });
  }
}
