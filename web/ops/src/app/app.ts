import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { UsageTracker } from '@hbh/shared/analytics/usage-tracker';
import { OpsAuthService } from './core/auth/ops-auth.service';
import { RouterOutlet } from '@angular/router';

import { Connectivity } from '@hbh/shared/a11y/connectivity';
import { RouteAnnouncer } from '@hbh/shared/a11y/route-announcer';
import { IconSprite } from '@hbh/shared/sprite/icon-sprite';
import { Toast } from '@hbh/shared/toast/toast';

/** The console root: the icon sprite, the routed screen, and the shared layers. */
@Component({
  selector: 'hbh-root',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterOutlet, IconSprite, Toast, Connectivity, RouteAnnouncer, UsageTracker],
  template: `
    <hbh-icon-sprite />
    <hbh-connectivity />
    <router-outlet />
    <hbh-toast />
    <hbh-route-announcer />
    <hbh-usage-tracker app="ops" [token]="auth.token" />
  `,
})
export class App { protected readonly auth = inject(OpsAuthService); }
