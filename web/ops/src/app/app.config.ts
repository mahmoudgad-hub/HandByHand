import {
  ApplicationConfig, inject, provideAppInitializer, provideBrowserGlobalErrorListeners,
} from '@angular/core';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideRouter, withInMemoryScrolling } from '@angular/router';

import { AppConfig, DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { DEV_ACCOUNTS } from './dev-accounts';
import { routes } from './app.routes';
import { opsAuthInterceptor } from './core/auth/ops-auth.interceptor';

/**
 * The console talks to the real service. There is no fixture switch here:
 * the fourteen resources it needs are served and have an acceptance suite
 * behind them, so a stand-in would only be a second thing to keep in step.
 *
 * Currency and time zone come from GET /me at sign-in and replace these
 * development defaults - a centre in another country needs a row, not a
 * release.
 */

const config: AppConfig = {
  ...DEFAULT_HBH_CONFIG,
  useFixtures: false,
  // Empty in a production build: dev-accounts.prod.ts replaces the import
  // through fileReplacements in angular.json, so the credentials are not
  // compiled into a shipped bundle at all. See dev-accounts.ts for why a
  // flag was not enough.
  devAccounts: DEV_ACCOUNTS,
};

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideRouter(routes, withInMemoryScrolling({ scrollPositionRestoration: 'top' })),
    provideHttpClient(withInterceptors([opsAuthInterceptor])),
    { provide: HBH_CONFIG, useValue: config },
    provideAppInitializer(() => inject(I18nService).load('ar')),
  ],
};
