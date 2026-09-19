import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { catchError, throwError } from 'rxjs';

import { AuthService } from './auth.service';

/**
 * Attaches the bearer token and reacts to the server rejecting it.
 *
 * Only 401 clears the session. A 403 means the server understood who the
 * guardian is and refused this particular thing - that is the authorisation
 * boundary doing its job, and signing the guardian out over it would hide a
 * refusal behind a login screen.
 *
 * AND ONLY 401 ON A REQUEST THAT CARRIED A TOKEN. Sign-in answers 401 too,
 * and there is no session behind those to end: a wrong one-time code comes
 * back `WRONG_CODE` with `attempts_left`, and this used to read it as an
 * expiry. The guardian was signed out of a screen they were not signed in
 * to - the outstanding code destroyed, the number field emptied, and "wrong
 * code, 4 attempts left" replaced by "your session expired", which is untrue
 * and leaves nothing to do about it. The whole of the code screen's failure
 * handling - the attempt counter, the lock - was unreachable behind it.
 *
 * THE TOKEN GOES TO THE SERVICE AND NOWHERE ELSE, and the rule is written
 * that way round on purpose. It used to read `!req.url.startsWith('assets/')`
 * - everything except the translation bundle - which is a deny-list, and a
 * deny-list can only name what somebody already thought of. The day a screen
 * reaches for a font host, a map tile, an analytics beacon or a help page,
 * that request leaves with a guardian's session token on it and nothing in
 * the change looks wrong.
 *
 * Every call this portal makes is `${apiBaseUrl}/api/v1/...` - measured
 * across the whole app, not assumed - and the translation bundle is the only
 * request that is not the API. So the condition is the prefix itself, taken
 * from the same config the callers build their URLs from rather than written
 * out again here: a list derived from one place cannot drift from it.
 */
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const auth = inject(AuthService);
  const token = auth.token;
  const apiPrefix = `${inject(HBH_CONFIG).apiBaseUrl}/api/`;

  const request = token && req.url.startsWith(apiPrefix)
    ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } })
    : req;

  // "Only 401 on a request that CARRIED a token" is what the paragraph above
  // says, and `token` alone did not say it - it said a session exists. Now
  // that the token no longer goes everywhere, the two differ: a 401 from some
  // static host would have ended a perfectly good session.
  const carried = request !== req;

  return next(request).pipe(
    catchError((error: unknown) => {
      if (carried && error instanceof HttpErrorResponse && error.status === 401) {
        auth.sessionExpired();
      }
      return throwError(() => error);
    }),
  );
};
