import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
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
 * Translation bundles are skipped: they are static files, and a session token
 * in a request for one only puts it in a log.
 */
export const opsAuthInterceptor: HttpInterceptorFn = (req, next) => {
  const auth = inject(OpsAuthService);
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
