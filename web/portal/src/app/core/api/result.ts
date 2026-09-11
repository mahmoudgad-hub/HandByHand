import { Observable, catchError, map, of } from 'rxjs';

import { isAuthFailure } from './portal-error';

/**
 * One optional piece of a screen, and whether it arrived.
 *
 * THE WHOLE POINT IS THE THIRD STATE. A parent screen has always had two:
 * the data, or nothing. So a failed request became "no data" - no
 * appointments, no reports, no money owed - and the portal told a family
 * something false about their child with complete confidence.
 *
 * Unknown is not empty, and it is not zero:
 *
 *   a balance that did not load is NOT 0 ج.م.
 *   an attendance figure that did not load is NOT 0%
 *   a report list that did not load is NOT "no reports yet"
 *
 * `failed` exists so a template can say "we could not load this" instead of
 * inventing a fact. An EMPTY ARRAY inside `ok` still means empty - that is
 * a real answer the service gave, and it keeps its meaning.
 */
export type Result<T> =
  | { readonly state: 'ok'; readonly data: T }
  | { readonly state: 'failed' };

export function ok<T>(data: T): Result<T> {
  return { state: 'ok', data };
}

export const failed: Result<never> = { state: 'failed' };

/**
 * Makes one leg of an aggregate survivable.
 *
 * `forkJoin` fails fast: one leg erroring cancels its siblings and the whole
 * object errors, which is why a single failing balance call blanked the
 * welcome screen - children, appointments and reports were all fetched
 * successfully and then thrown away. Wrapping the OPTIONAL legs means the
 * aggregate always completes and each field says for itself whether it
 * arrived.
 *
 * NOT FOR EVERY LEG, and not a substitute for `catchError(() => of([]))`
 * either - that is the bug, written deliberately. Wrap what a screen can
 * usefully be missing. A leg the screen is ABOUT stays bare, so the
 * aggregate still errors and the screen shows its own error with a retry.
 *
 * AUTHENTICATION IS NEVER SWALLOWED. A 401 means the session is over, and
 * turning it into a grey "could not load this section" card would leave a
 * family staring at eight of them while the real answer is "sign in again".
 * Those errors are re-thrown so the interceptor and the guard handle them
 * exactly as they do today.
 */
export function resilient<T>(source: Observable<T>): Observable<Result<T>> {
  return source.pipe(
    map((data) => ok(data)),
    catchError((error: unknown) => {
      if (isAuthFailure(error)) {
        throw error;
      }
      return of(failed);
    }),
  );
}

/** The data if it arrived, otherwise `fallback`. For places that genuinely
 *  have no third state to render - never for a number a parent reads. */
export function dataOr<T>(result: Result<T>, fallback: T): T {
  return result.state === 'ok' ? result.data : fallback;
}
