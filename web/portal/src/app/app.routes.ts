import { Routes } from '@angular/router';

import { authGuard, childSelectedGuard, guestOnlyGuard } from './core/auth/auth.guard';

/**
 * Two shapes of screen. Sign-in and the welcome screen stand alone, with no
 * navigation around them, because each has exactly one intended way out. The
 * rest live inside the shell, which owns the header and the tab bar.
 *
 * No route carries a child identifier. The chosen child lives in
 * ChildContextService: a route parameter would suggest that editing the
 * address bar changes what may be seen, and the server is what decides that.
 */
export const routes: Routes = [
  {
    path: 'login',
    canActivate: [guestOnlyGuard],
    data: { titleKey: 'login.title' },
    loadComponent: () => import('./features/login/login').then((m) => m.Login),
    children: [{
      path: 'otp',
      data: { titleKey: 'otp.title' },
      loadComponent: () => import('./features/otp/otp').then((m) => m.Otp),
    }],
  },
  {
    // The one route in this app with no guard at all, and it cannot have
    // one: a family with no account is exactly who it is for. The endpoint
    // behind it is the service's only unauthenticated write.
    path: 'apply',
    data: { titleKey: 'apply.title' },
    loadComponent: () => import('./features/apply/apply').then((m) => m.Apply),
  },
  {
    path: 'otp',
    redirectTo: 'login/otp',
    pathMatch: 'full',
  },
  {
    path: 'welcome',
    canActivate: [authGuard],
    data: { titleKey: 'welcome.title' },
    loadComponent: () => import('./features/welcome/welcome').then((m) => m.Welcome),
  },
  {
    path: '',
    canActivate: [authGuard],
    loadComponent: () => import('./layout/shell/shell').then((m) => m.Shell),
    children: [
      {path:'communications',data:{titleKey:'nav.communications',tab:'requests'},loadComponent:()=>import('@hbh/shared/ui/family-messages').then(m=>m.FamilyMessages)},
      {
        path: 'home',
        canActivate: [childSelectedGuard],
        data: { titleKey: 'nav.home', subtitle: 'child', tab: 'home' },
        loadComponent: () => import('./features/home/home').then((m) => m.Home),
      },
      {
        path: 'schedule',
        canActivate: [childSelectedGuard],
        data: { titleKey: 'nav.schedule', subtitle: 'child', tab: 'schedule' },
        loadComponent: () =>
          import('./features/schedule/schedule').then((m) => m.Schedule),
      },
      {
        path: 'progress',
        canActivate: [childSelectedGuard],
        data: { titleKey: 'nav.progress', subtitle: 'child', tab: 'progress' },
        loadComponent: () =>
          import('./features/progress/progress').then((m) => m.Progress),
      },
      {
        path: 'activities',
        canActivate: [childSelectedGuard],
        data: { titleKey: 'nav.activities', subtitle: 'child', tab: 'activities' },
        loadComponent: () =>
          import('./features/activities/activities').then((m) => m.Activities),
      },
      {
        path: 'live',
        canActivate: [childSelectedGuard],
        data: { titleKey: 'live.title', subtitle: 'child', back: '/home' },
        loadComponent: () => import('./features/live/live').then((m) => m.Live),
      },
      {
        path: 'reports',
        canActivate: [childSelectedGuard],
        data: { titleKey: 'reports.title', subtitle: 'child', back: '/home', tab: 'reports' },
        loadComponent: () =>
          import('./features/reports/reports').then((m) => m.Reports),
      },
      {
        // One report, open. `back` returns to the list rather than to home:
        // somebody who opened a report from a list of five wants the other
        // four, not the front page.
        path: 'reports/:reportId',
        canActivate: [childSelectedGuard],
        data: { titleKey: 'report.title', subtitle: 'child', back: '/reports', tab: 'reports' },
        loadComponent: () =>
          import('./features/report/report').then((m) => m.Report),
      },
      {
        path: 'billing',
        data: { titleKey: 'billing.title', back: '/home', tab: 'billing' },
        loadComponent: () =>
          import('./features/billing/billing').then((m) => m.Billing),
      },
      {
        path: 'requests',
        data: { titleKey: 'requests.title', back: '/home', tab: 'requests' },
        loadComponent: () =>
          import('./features/requests/requests').then((m) => m.Requests),
      },
      {
        // One therapist, reached by tapping their name on an appointment.
        //
        // The identifier IS in the path here, unlike a child's - and the
        // difference is not an inconsistency. A child is the guardian's own
        // data and a route parameter would suggest that editing the address
        // decides what may be seen. A therapist is a member of centre staff
        // every family may look up, and the service masks on the row itself
        // what a family may not see.
        path: 'therapists/:therapistId',
        data: { titleKey: 'therapist.title', back: true },
        loadComponent: () =>
          import('./features/therapist/therapist').then((m) => m.Therapist),
      },
      {
        // NO childSelectedGuard. The feed is addressed to a PERSON and spans
        // every child in the family - a report about one and an invoice about
        // another sit in the same list. Requiring a child to be chosen first
        // would be the same category error as putting a child id in its URL.
        path: 'notifications',
        data: { titleKey: 'notifications.title', back: '/home' },
        loadComponent: () =>
          import('./features/notifications/notifications').then((m) => m.Notifications),
      },
      {
        path: 'profile',
        data: { titleKey: 'nav.profile', tab: 'profile' },
        loadComponent: () =>
          import('./features/profile/profile').then((m) => m.Profile),
      },
      { path: '', pathMatch: 'full', redirectTo: '/welcome' },
    ],
  },
  { path: '**', redirectTo: '/welcome' },
];
