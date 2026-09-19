import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { catchError, throwError } from 'rxjs';

import { OpsAuthService } from './ops-auth.service';

/**
 * Attaches the bearer token and reacts only to 401.
 *
 * A 403 is left alone deliberately. It means the server knows who this is and
 * refused this particular thing - the authorisation boundary working. Signing
 * someone out over it would hide a refusal behind a login screen and send
 * them hunting for a password problem they do not have.
 *
 * AND ONLY 401 ON A REQUEST THAT CARRIED A TOKEN. A refused sign-in is a 401
 * as well, and no session stands behind it to expire. Without this guard a
 * wrong password cleared state and re-entered the sign-in route underneath
 * the screen that was already showing the refusal - the message survived by
 * luck of the router reusing the component, and would stop surviving the day
 * it did not.
 *
 * THE TOKEN GOES TO THE SERVICE AND NOWHERE ELSE, and the rule is written
 * that way round on purpose. It used to read `!req.url.startsWith('assets/')`
 * - everything except the translation bundle - which is a deny-list, and a
 * deny-list can only name what somebody already thought of. The day a screen
 * reaches for a font host, a map tile or an analytics beacon, that request
 * leaves with a staff session token on it and nothing in the change looks
 * wrong.
 *
 * Every call this console makes is `${apiBaseUrl}/api/v1/...` - measured
 * across the whole app, not assumed - and the translation bundle is the only
 * request that is not the API. So the condition is the prefix itself, taken
 * from the same config the callers build their URLs from rather than written
 * out again here: a list derived from one place cannot drift from it.
 */
export const opsAuthInterceptor: HttpInterceptorFn = (req, next) => {
  const auth = inject(OpsAuthService);
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
