import {
  ApplicationConfig,
  provideAppInitializer,
  inject,
  provideBrowserGlobalErrorListeners,
} from '@angular/core';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideRouter, withInMemoryScrolling, RouteReuseStrategy } from '@angular/router';
import { ChildRouteReuse } from './core/auth/child-route-reuse';

import { routes } from './app.routes';
import {
  DEFAULT_HBH_CONFIG,
  HBH_CONFIG,
  AppConfig,
} from '@hbh/shared/config/app-config';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { authInterceptor } from './core/auth/auth.interceptor';
import { AuthApi } from './core/auth/auth-api';
import { FixtureAuthApi } from './core/auth/fixture-auth-api';
import { HttpAuthApi } from './core/auth/http-auth-api';
import { PortalApi } from './core/api/portal-api';
import { FixturePortalApi } from './core/api/fixture-portal-api';
import { HttpPortalApi } from './core/api/http-portal-api';
import { usageInterceptor } from '@hbh/shared/analytics/usage-tracker';

/**
 * The portal talks to the real service.
 *
 * It ran on fixtures until now, and that hid something: HttpPortalApi had
 * been written against a contract that was imagined rather than read, and ten
 * of its thirteen calls were to endpoints that do not exist. Nothing caught
 * it, because nothing ever ran it. The fixtures stay - they are how a screen
 * is developed without a database - but they are no longer the default, so an
 * endpoint that moves breaks a build instead of hiding behind a stand-in.
 *
 * apiBaseUrl stays empty: same origin in production, and the dev server
 * proxies /api to the service (web/proxy.conf.json).
 */
const config: AppConfig = { ...DEFAULT_HBH_CONFIG, useFixtures: false };

export const appConfig: ApplicationConfig = {
  providers: [
    { provide: RouteReuseStrategy, useExisting: ChildRouteReuse },
    provideBrowserGlobalErrorListeners(),
    provideRouter(
      routes,
      withInMemoryScrolling({ scrollPositionRestoration: 'top' }),
    ),
    provideHttpClient(withInterceptors([authInterceptor, usageInterceptor])),

    { provide: HBH_CONFIG, useValue: config },

    // One switch decides whether the portal talks to the Go service or to the
    // fixtures. Screens never learn which, because they only ever see the
    // abstract class.
    { provide: PortalApi, useClass: config.useFixtures ? FixturePortalApi : HttpPortalApi },
    { provide: AuthApi, useClass: config.useFixtures ? FixtureAuthApi : HttpAuthApi },

    // Nothing renders before the Arabic bundle is in memory, so no screen can
    // flash its translation keys.
    provideAppInitializer(() => inject(I18nService).load('ar')),
  ],
};
