import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
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
 * Translation bundles are skipped: they are static files, and sending a
 * session token to fetch one puts it in a log for no reason.
 */
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const auth = inject(AuthService);
  const token = auth.token;

  const request = token && !req.url.startsWith('assets/')
    ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } })
    : req;

  return next(request).pipe(
    catchError((error: unknown) => {
      if (token && error instanceof HttpErrorResponse && error.status === 401) {
        auth.sessionExpired();
      }
      return throwError(() => error);
    }),
  );
};
