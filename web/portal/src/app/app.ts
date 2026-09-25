import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { RouterOutlet } from '@angular/router';

import { Connectivity } from '@hbh/shared/a11y/connectivity';
import { RouteAnnouncer } from '@hbh/shared/a11y/route-announcer';
import { IconSprite } from '@hbh/shared/sprite/icon-sprite';
import { Toast } from '@hbh/shared/toast/toast';
import { AuthService } from './core/auth/auth.service';
import { NpsCard } from './features/nps/nps-card';
import { NotificationPush } from './core/alerts/notification-push';
import { UsageTracker } from '@hbh/shared/analytics/usage-tracker';

/**
 * The application root holds the pieces every screen shares and no logic of
 * its own: the icon sprite each screen draws from, the routed screen, the
 * toast layer, the offline bar, and the live region that tells a screen
 * reader which screen it has landed on.
 */
@Component({
  selector: 'hbh-root',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterOutlet, IconSprite, Toast, Connectivity, RouteAnnouncer, NpsCard, UsageTracker, NotificationPush],
  template: `
    <hbh-icon-sprite />
    <hbh-connectivity />
    <router-outlet />
    <hbh-toast />
    <hbh-route-announcer />
    <hbh-usage-tracker app="portal" [token]="auth.token" />

    <!--
      The satisfaction question, asked straight after signing in.

      HERE AND NOT IN THE SHELL, because the welcome screen - the first thing
      a parent sees after signing in, and the whole point of asking "straight
      after login" - is a standalone route with no shell around it.

      GATED ON BEING SIGNED IN, and the gate is what makes it work rather than
      what makes it tidy: the card asks the service once, when it is created.
      Rendered unconditionally it would be created at start-up, on the sign-in
      screen, ask nobody, and then sit there for the rest of the session
      having already decided there was nothing to ask. Signing in flips this
      to true and builds it at that moment. Signing out destroys it, so the
      next person to use the phone is asked about their own visits.
    -->
    @if (auth.isSignedIn()) {
      <hbh-notification-push />
      <hbh-nps-card />
    }
  `,
})
export class App {
  protected readonly auth = inject(AuthService);
}
