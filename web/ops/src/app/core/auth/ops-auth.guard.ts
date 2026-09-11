import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { catchError, map, of } from 'rxjs';

import { OpsAuthService } from './ops-auth.service';

/**
 * No token, no console. And on a reload the token survives in sessionStorage
 * but the identity does not, so it is fetched again before any screen draws -
 * otherwise the first frame would have an empty menu and a nameless user.
 */
export const opsAuthGuard: CanActivateFn = () => {
  const auth = inject(OpsAuthService);
  const router = inject(Router);

  if (!auth.isSignedIn()) {
    return router.createUrlTree(['/login']);
  }
  if (auth.me()) {
    return true;
  }

  return auth.loadIdentity().pipe(
    map(() => true),
    // The token was accepted by storage but refused by the server, or the
    // service is down. Either way the console has no identity to draw with.
    catchError(() => of(router.createUrlTree(['/login']))),
  );
};

/**
 * A screen declares the permission it needs in its route data. This keeps a
 * screen from rendering that the server would refuse to fill - it is not the
 * refusal itself, which happens in a policy underneath the query.
 */
export const permissionGuard: CanActivateFn = (route) => {
  const auth = inject(OpsAuthService);
  const router = inject(Router);
  const needed = route.data['permission'] as string | undefined;

  if (!needed || auth.can(needed)) {
    return true;
  }
  return router.createUrlTree(['/denied'], { queryParams: { need: needed } });
};

/** Sends an already signed-in user away from the sign-in screen. */
export const opsGuestGuard: CanActivateFn = () => {
  const auth = inject(OpsAuthService);
  const router = inject(Router);
  return auth.isSignedIn() ? router.createUrlTree(['/dashboard']) : true;
};
