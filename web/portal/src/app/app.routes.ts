import { inject } from '@angular/core';
import { Router, Routes } from '@angular/router';

import { authGuard, childSelectedGuard, guestOnlyGuard, requestChildGuard } from './core/auth/auth.guard';

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
      { path: 'communications', pathMatch: 'full', redirectTo: ({ queryParams }) =>
        inject(Router).createUrlTree(['/requests'], { queryParams: { ...queryParams, tab: 'messages' } }) },
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
          import('./features/progress/progress-hub').then((m) => m.ProgressHub),
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
        // One online consultation, opened.
        //
        // The appointment id IS in the path, like a report's and unlike a
        // child's. The rule this file states above still holds - editing the
        // address must not decide what may be seen - and it holds because
        // hbh.authorize_meeting_entry re-asks whose appointment this is on
        // every single call. A parent who types somebody else's number here
        // is answered 404, which is the same answer they get for an
        // appointment that does not exist.
        //
        // NO childSelectedGuard. The appointment names its own child, so
        // requiring one to be chosen first would add a condition that
        // decides nothing - and a family arriving from a message about one
        // child's consultation should not be stopped to pick a child.
        path: 'consultation/:appointmentId',
        data: { titleKey: 'consult.title', back: '/schedule' },
        loadComponent: () =>
          import('./features/consultation/consultation').then((m) => m.Consultation),
      },
      {
        path: 'reports',
        pathMatch: 'full',
        redirectTo: ({ queryParams }) => inject(Router).createUrlTree(['/progress'], {
          queryParams: { ...queryParams, tab: queryParams['tab'] === 'notes' || queryParams['scope'] === 'notes' ? 'notes' : 'reports' },
        }),
      },
      {
        // One report, open. `back` returns to the list rather than to home:
        // somebody who opened a report from a list of five wants the other
        // four, not the front page.
        path: 'reports/:reportId',
        canActivate: [childSelectedGuard],
        data: { titleKey: 'report.title', subtitle: 'child', back: '/reports', tab: 'progress' },
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
        canActivate: [requestChildGuard],
        runGuardsAndResolvers: 'paramsOrQueryParamsChange',
        data: { titleKey: 'requests.title', back: '/home', tab: 'requests' },
        loadComponent: () =>
          import('./features/requests/requests-hub').then((m) => m.RequestsHub),
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
