import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { catchError, map, of } from 'rxjs';

import { PortalApi } from '../api/portal-api';

import { AuthService } from './auth.service';
import { ChildContextService } from './child-context.service';

/**
 * No identity, no screen. The redirect carries no return URL that could hold
 * anything about the guardian - after signing in they land on the welcome
 * screen and choose again.
 */
export const authGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  return auth.isSignedIn() ? true : router.createUrlTree(['/login']);
};

/**
 * The child screens need a child chosen. Choosing one is not permission to
 * see it: the server re-checks the guardian's link on every request, and this
 * guard only keeps the interface from rendering an empty shell.
 *
 * On a reload the choice is gone from memory but its identifier is still in
 * sessionStorage, so the guard asks the server for this guardian's children
 * and picks it out of the answer. That list is the server's own definition of
 * who this guardian may see - an identifier that is not in it resolves to
 * nothing, and the guardian lands on the picker.
 */
export const childSelectedGuard: CanActivateFn = () => {
  const child = inject(ChildContextService);
  const api = inject(PortalApi);
  const router = inject(Router);

  if (child.selected()) {
    return true;
  }

  const remembered = child.rememberedId();
  if (!remembered) {
    return router.createUrlTree(['/welcome']);
  }

  // family(), not welcome(): this needs the list of children, and welcome()
  // fetched four more things per child on every reload of a child screen.
  return api.family().pipe(
    map((summary) => {
      const found = summary.children.find((candidate) => candidate.id === remembered);
      if (!found) {
        child.clear();
        return router.createUrlTree(['/welcome']);
      }
      child.select(found);
      return true;
    }),
    // A failure here is not a refusal - the network is down, or the service
    // is restarting. The picker can say so; a blank child screen cannot.
    catchError(() => of(router.createUrlTree(['/welcome']))),
  );
};

/** Messages span the family; only composing child requests requires a selection. */
export const requestChildGuard: CanActivateFn = (route, state) =>
  route.queryParamMap.get('tab') === 'messages' ? true : childSelectedGuard(route, state);

/** Sends an already signed-in visitor away from the sign-in screens. */
export const guestOnlyGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  return auth.isSignedIn() ? router.createUrlTree(['/welcome']) : true;
};
