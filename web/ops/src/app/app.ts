import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';

import { Connectivity } from '@hbh/shared/a11y/connectivity';
import { RouteAnnouncer } from '@hbh/shared/a11y/route-announcer';
import { IconSprite } from '@hbh/shared/sprite/icon-sprite';
import { Toast } from '@hbh/shared/toast/toast';

/** The console root: the icon sprite, the routed screen, and the shared layers. */
@Component({
  selector: 'hbh-root',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterOutlet, IconSprite, Toast, Connectivity, RouteAnnouncer],
  template: `
    <hbh-icon-sprite />
    <hbh-connectivity />
    <router-outlet />
    <hbh-toast />
    <hbh-route-announcer />
  `,
})
export class App {}
