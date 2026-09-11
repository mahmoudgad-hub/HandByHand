/**
 * Reading a refusal from the service, in the portal.
 *
 * EVERY refusal this service sends carries a code, and a validation refusal
 * also names the FIELD it is about. Screens here were throwing all of that
 * away and showing "could not load the data" for anything that was not a
 * success - which is how a bad query parameter became a parent bounced off
 * their own child's diary with a message that pointed at nothing.
 *
 * The service answers with codes and never with sentences, so this file is
 * the only place that knows them and everything above it asks for a key.
 */
export interface PortalRefusal {
  readonly code: string;
  /** The field a validation refusal named, when it named one. */
  readonly field: string | null;
  /**
   * The service's own id for this request, present on every response.
   *
   * It is the ONLY thing that ties what a parent saw to a line in the
   * centre's log - the reason itself never leaves the server - so it is
   * shown on an unexpected failure and nowhere else. It identifies the
   * request and says nothing about the account or the child.
   */
  readonly requestId: string | null;
  readonly status: number;
}

export function readRefusal(error: unknown): PortalRefusal {
  const shaped = error as {
    status?: number;
    error?: {
      error?: { code?: string; request_id?: string; fields?: { field?: string } };
    };
  };
  const body = shaped?.error?.error;
  return {
    code: body?.code ?? '',
    field: body?.fields?.field ?? null,
    requestId: body?.request_id ?? null,
    status: shaped?.status ?? 0,
  };
}

/**
 * The message key for a failed read.
 *
 * The distinction that matters to somebody looking at the screen:
 *
 *   nothing arrived        - the network, or the service being restarted
 *   the request was wrong  - a filter this screen sent; retrying is useless
 *   the answer was refused - a permission or an ownership boundary
 *
 * Collapsing the three into "could not load" invites a person to press retry
 * against a request that will be refused identically forever.
 */
/**
 * Whether this refusal means the session is over.
 *
 * Used by `resilient` to decide what NOT to swallow. A 401 is the one
 * failure that must never become a grey "could not load this section" card:
 * the answer is to sign in again, and a screen showing eight of those cards
 * while the token is dead tells a family the centre is broken. The
 * interceptor already clears the session on 401 - this only keeps the error
 * travelling so it can.
 *
 * 403 is deliberately NOT here. It is an answer about the ROW, not about the
 * session, and a section a family may not read is a section that degrades
 * like any other.
 */
export function isAuthFailure(error: unknown): boolean {
  return readRefusal(error).status === 401;
}

export function loadErrorKey(error: unknown): string {
  const refusal = readRefusal(error);
  if (refusal.status === 0) {
    return 'error.network';
  }
  if (refusal.status === 400 || refusal.code === 'VALIDATION') {
    return 'error.badFilter';
  }
  if (refusal.status === 403) {
    return 'error.notYours';
  }
  if (refusal.status === 404) {
    return 'error.notFound';
  }
  return 'error.load';
}

/**
 * The request id to put under an unexpected failure, or nothing.
 *
 * Only for the cases nobody can act on - a 500, or a code this app has not
 * been taught. On a refusal a person CAN act on, a reference number is noise
 * beside a sentence that already says what to do.
 *
 * Why show it at all: the reason for a 500 deliberately never reaches a
 * client, so this string is the single thread between "it did not work for
 * me" and the line in the centre's log that says why.
 */
export function traceIdFor(error: unknown): string | null {
  const refusal = readRefusal(error);
  const actionable = refusal.status === 0 || refusal.status === 400
    || refusal.status === 403 || refusal.status === 404
    || refusal.code === 'VALIDATION';
  return actionable ? null : refusal.requestId;
}
