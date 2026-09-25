import { inject } from '@angular/core';
import { Router, Routes } from '@angular/router';

import { opsAuthGuard, opsGuestGuard, permissionGuard } from './core/auth/ops-auth.guard';
import {
  ACTIVITY_LIBRARY_SPEC, CAMERAS_SPEC, CASELOAD_SPEC, CHILDREN_SPEC,
  CHILD_ACTIVITIES_SPEC, GOALS_SPEC, GUARDIANS_SPEC, MEASUREMENTS_SPEC,
  NPS_SURVEYS_SPEC, PACKAGES_SPEC, PLANS_SPEC, ROOMS_SPEC, SERVICES_SPEC,
  SITE_CONTACT_SPEC, SITE_FAQ_SPEC, SITE_TEXTS_SPEC,
  SITE_PROGRAMS_SPEC, SITE_REVIEWS_SPEC, SITE_SECTIONS_SPEC, SITE_SERVICES_SPEC,
  THERAPISTS_SPEC,
  WORKING_HOURS_SPEC,
} from './core/resource/resource-spec';
import {
  APPOINTMENTS_SPEC, ENROLMENTS_SPEC, INVOICES_SPEC, REPORTS_SPEC, REQUESTS_SPEC,
  SESSIONS_SPEC,
} from './core/ops/day-spec';
import { DayScreen } from './features/day/day-screen';
import { ResourceScreen } from './features/resource/resource-screen';
import { Satisfaction } from './features/satisfaction/satisfaction';
import { SiteEditor } from './features/site-editor/site-editor';
import { TeamScreen } from './features/team/team-screen';
import { TherapistServices } from './features/therapist-services/therapist-services';
import { resourceScreen, tabsByPrefix } from './core/ops/tab-titles';
import { CHILD_TABS } from './features/child/child-tabs';
import { GUARDIAN_TABS } from './features/guardian/guardian-tabs';
import { ENROLMENT_TABS } from './features/enrolment/enrolment-tabs';

/**
 * Where a retired route sends its visitors.
 *
 * The old addresses stay alive because links to them exist outside this
 * build: in notifications already written, in messages, in bookmarks on a
 * reception desk. Each one lands on the screen that absorbed it, on the
 * right tab or view (docs/UX-CURRENT-TO-TARGET.md section 3).
 */
function movedTo(path: string, query: Record<string, string>) {
  return () => inject(Router).createUrlTree([path], { queryParams: query });
}

/**
 * Every screen declares the permission it needs. The guard keeps one from
 * rendering that the server would refuse to fill - it is not the refusal
 * itself, which happens in a policy underneath the query.
 *
 * The screens split into two kinds, driven by two descriptions:
 *
 *   ResourceScreen, on the fourteen CRUD resources - rows that are created
 *   and edited and archived.
 *   DayScreen, on the five centre-indexed reads - rows that MOVE, through
 *   the state machines in the schema and never by editing a status column.
 *
 * Two screens from the static designs are absent: leads and communications
 * have no table, so they have no route. A menu entry to nothing is worse
 * than no entry. Enrolment applications now have a table (0018) and are the
 * first candidate to return.
 */
export const routes: Routes = [
  {
    path: 'login',
    canActivate: [opsGuestGuard],
    data: { titleKey: 'login.title' },
    loadComponent: () => import('./features/login/login').then((m) => m.Login),
  },
  {
    path: '',
    canActivate: [opsAuthGuard],
    loadComponent: () => import('./layout/shell/shell').then((m) => m.Shell),
    children: [
      {
        path: 'profile',
        // No navKey: opened from the account menu in the top bar, not the
        // side menu. No permissionGuard: every signed-in account has one.
        data: { titleKey: 'profile.title' },
        loadComponent: () => import('./features/profile/account-dialog').then(m => m.AccountRoute),
      },
      { path: 'favorites', canActivate: [permissionGuard], data: { navKey: 'favorites', titleKey: 'nav.favorites', permission: 'PORTAL.VIEW' }, loadComponent: () => import('./features/favorites/favorites').then(m => m.Favorites) },
      {path: 'communications',canActivate:[permissionGuard],data:{navKey:'communications',titleKey:'nav.communications',permission:'PORTAL.VIEW'},loadComponent:()=>import('@hbh/shared/ui/family-messages').then(m=>m.FamilyMessages)},
      {
        // What needs doing. Derived from the state of rows the other screens
        // already list - no table, no write; see core/tasks.
        path: 'tasks',
        canActivate: [permissionGuard],
        data: { navKey: 'tasks', titleKey: 'nav.tasks', permission: 'PORTAL.VIEW' },
        loadComponent: () =>
          import('./features/tasks/tasks').then((m) => m.Tasks),
      },
      {
        // What happened, addressed to this person. This screen was called
        // "inbox", which promised a to-do list it never was; the log kept
        // its behaviour and lost the name.
        path: 'notifications',
        canActivate: [permissionGuard],
        data: { navKey: 'notifications', titleKey: 'nav.notifications', permission: 'PORTAL.VIEW' },
        loadComponent: () =>
          import('./features/inbox/inbox').then((m) => m.Inbox),
      },
      { path: 'inbox', redirectTo: 'notifications', pathMatch: 'full' },
      {
        path: 'dashboard',
        canActivate: [permissionGuard],
        data: { navKey: 'dashboard', titleKey: 'nav.dashboard', permission: 'PORTAL.VIEW' },
        loadComponent: () =>
          import('./features/dashboard/dashboard').then((m) => m.Dashboard),
      },

      // ---- built on the CRUD resources ----
      {
        // Guardians have their own screen now (UX-3): the list here, and a
        // page per guardian below. The children screen lists children only.
        path: 'guardians',
        canActivate: [permissionGuard],
        component: ResourceScreen,
        data: resourceScreen({
          navKey: 'guardians', titleKey: 'nav.guardians',
          permission: 'GUARDIAN.MANAGE',
          specs: [GUARDIANS_SPEC],
        }),
      },
      {
        // One guardian: the family behind the children, their applications,
        // their appointments, their money, their messages
        // (docs/UX-DETAIL-PAGES.md section 2).
        path: 'guardians/:guardianId',
        canActivate: [permissionGuard],
        // Tabs in the address bar: each is its own place to a bookmark and
        // to a screen reader, so the announcer names them (HBH-039).
        data: {
          navKey: 'guardians', titleKey: 'guardian.title', permission: 'GUARDIAN.MANAGE',
          tabTitles: tabsByPrefix('guardian.tab.', GUARDIAN_TABS),
        },
        loadComponent: () =>
          import('./features/guardian/guardian-detail').then((m) => m.GuardianDetail),
      },
      {
        path: 'children',
        canActivate: [permissionGuard],
        component: ResourceScreen,
        data: resourceScreen({
          navKey: 'children', titleKey: 'nav.children',
          permission: 'CHILD.VIEW_ALL',
          specs: [CHILDREN_SPEC],
        }),
      },
      {
        // One child's file. The children list had no way through to anything
        // until now: rows were shown and clicking one did nothing, so a
        // receptionist with a parent on the phone opened five screens and
        // filtered each by hand.
        //
        // The identifier is in the path, unlike the parent portal where it
        // deliberately is not. Staff navigate BY child and the policy under
        // the query decides what they may see; a guardian editing the
        // address bar is a different threat and a different app.
        path: 'children/:childId',
        canActivate: [permissionGuard],
        // The tabs of this screen live in the address bar, so each of them is
        // its own place as far as the browser tab, a bookmark and a screen
        // reader are concerned. The announcer looks the `tab` parameter up in
        // this map; the component that draws the tabs is not asked, and must
        // not be (HBH-039). The map is built from the same list the screen
        // draws from, so a tab cannot be added and left unnamed (HBH-102).
        data: {
          navKey: 'children', titleKey: 'child.title', permission: 'CHILD.VIEW_ALL',
          tabTitles: tabsByPrefix('child.tab.', CHILD_TABS),
        },
        loadComponent: () =>
          import('./features/child/child-profile').then((m) => m.ChildProfile),
      },
      {
        // WRITING A REPORT, reached from the child whose report it is.
        //
        // The child is in the path and the report is not, because there is
        // no report yet: this route opens a blank one. Its sibling below
        // carries the id once the draft has been saved.
        //
        // REPORT.WRITE guards the screen, and decides nothing else -
        // hbh.create_report asks for the same permission AND for access to
        // this child, which a route guard cannot ask because it is a
        // question about the row (migration 0088).
        path: 'children/:childId/reports/new',
        canActivate: [permissionGuard],
        data: { navKey: 'children', titleKey: 'report.new', permission: 'REPORT.WRITE' },
        loadComponent: () =>
          import('./features/report-editor/report-editor').then((m) => m.ReportEditor),
      },
      {
        path: 'children/:childId/reports/:reportId',
        canActivate: [permissionGuard],
        data: { navKey: 'children', titleKey: 'report.edit', permission: 'REPORT.WRITE' },
        loadComponent: () =>
          import('./features/report-editor/report-editor').then((m) => m.ReportEditor),
      },
      {
        // The printed identity card. It leaves the building with the family,
        // so it carries no national identity number and no home address, and
        // it is dark ink on white because browsers do not print backgrounds.
        path: 'children/:childId/card',
        canActivate: [permissionGuard],
        data: { navKey: 'children', titleKey: 'card.title', permission: 'CHILD.VIEW_ALL' },
        loadComponent: () =>
          import('./features/child-card/child-card').then((m) => m.ChildCard),
      },
      {
        path: 'therapists',
        canActivate: [permissionGuard],
        component: ResourceScreen,
        data: resourceScreen({
          navKey: 'therapists', titleKey: 'nav.therapists',
          permission: 'STAFF.MANAGE',
          specs: [THERAPISTS_SPEC, WORKING_HOURS_SPEC, CASELOAD_SPEC],
          // The services matrix is a fourth tab of the same subject. It had
          // a route of its own only because the menu lit the wrong entry.
          extraTabs: [{
            key: 'services', titleKey: 'therapistServices.title',
            permission: 'STAFF.MANAGE', component: TherapistServices,
          }],
        }),
      },
      { path: 'therapist-services', redirectTo: movedTo('/therapists', { tab: 'services' }) },
      {
        path: 'rooms',
        canActivate: [permissionGuard],
        component: ResourceScreen,
        data: resourceScreen({
          navKey: 'rooms', titleKey: 'nav.rooms',
          permission: 'CATALOG.MANAGE',
          specs: [ROOMS_SPEC, CAMERAS_SPEC],
        }),
      },
      {
        // The clinician's own work: the plan, its goals, the measurements
        // that show movement, and the home programme built from them. Four
        // resources the service has always served and nothing ever called -
        // a therapist could not write a plan from any screen.
        path: 'plans',
        canActivate: [permissionGuard],
        component: ResourceScreen,
        data: resourceScreen({
          navKey: 'plans', titleKey: 'plans.plans',
          permission: 'PLAN.MANAGE',
          specs: [PLANS_SPEC, GOALS_SPEC, MEASUREMENTS_SPEC, CHILD_ACTIVITIES_SPEC],
        }),
      },
      {
        path: 'catalog',
        canActivate: [permissionGuard],
        component: ResourceScreen,
        data: resourceScreen({
          navKey: 'catalog', titleKey: 'nav.catalog',
          permission: 'CATALOG.MANAGE',
          // The satisfaction surveys left for /satisfaction, beside the
          // answers they collect: one subject, one screen.
          specs: [SERVICES_SPEC, PACKAGES_SPEC, ACTIVITY_LIBRARY_SPEC],
        }),
      },
      {
        // The public site's words, on one screen with four tabs.
        //
        // ONE ROUTE, not four. Contact, questions, team and testimonials are
        // one job done in one sitting - somebody who opens this is editing
        // "the website", not "the FAQ table" - and four entries in the menu
        // for four small lists is a menu nobody reads.
        //
        // The guard checks SITE.EDIT, which is what decides whether the menu
        // draws this at all. It decides nothing else: publishing needs
        // SITE.PUBLISH and the database refuses it, whatever this screen
        // shows. Hiding a control is not a control.
        path: 'site',
        canActivate: [permissionGuard],
        component: ResourceScreen,
        data: resourceScreen({
          navKey: 'site', titleKey: 'nav.site',
          permission: 'SITE.EDIT',
          // The team's three tabs are gone from here. A qualification means
          // nothing apart from whose it is, so they now live inside the
          // member on /site/team - see TeamScreen. The resources themselves
          // are unchanged; this is one less place to hold a join in your
          // head.
          specs: [SITE_CONTACT_SPEC, SITE_SERVICES_SPEC, SITE_PROGRAMS_SPEC,
                  SITE_FAQ_SPEC, SITE_REVIEWS_SPEC,
                  SITE_SECTIONS_SPEC],
          // The team on the site, as master and detail - an eighth tab of
          // "the website", which is the job somebody opening this is doing.
          extraTabs: [{key:'site-texts', titleKey:'siteEditor.title', permission:'SITE.EDIT', component:SiteEditor}, {
            key: 'team', titleKey: 'site.team',
            permission: 'SITE.EDIT', component: TeamScreen,
          }],
        }),
      },
      {
        path: 'site/team',
        canActivate: [permissionGuard],
        component: TeamScreen,
        data: { navKey: 'site-team', titleKey: 'nav.teamProfiles', permission: 'SITE.EDIT' },
      },

      // ---- the centre-indexed reads, and the verbs that change them ----
      //
      // These five arrived together with the eleven writes behind them, and
      // they are the reason this console does anything. All five run through
      // one screen: the columns and the verbs are descriptions in day-spec.
      {
        // Reception's diary AND the clinician's own day: one screen, two
        // permissions on the route. `?view=mine` narrows it to the signed-in
        // therapist (what /my-day was); the verbs stay filtered one by one
        // by their own permission, as they always were.
        path: 'appointments',
        canActivate: [permissionGuard],
        component: DayScreen,
        data: {
          navKey: 'appointments', titleKey: 'nav.appointments',
          permission: 'APPOINTMENT.BOOK', altPermission: 'SESSION.START',
          spec: APPOINTMENTS_SPEC,
        },
      },
      {
        // THE CLINICIAN'S DAY, and the reason it exists is a broken flow
        // rather than a wish for another screen.
        //
        // "Start session" is an action on an APPOINTMENT - a session row
        // does not exist until it starts - so it lives in
        // APPOINTMENTS_SPEC, and /appointments requires APPOINTMENT.BOOK.
        // THERAPIST holds SESSION.START and does NOT hold APPOINTMENT.BOOK,
        // so the one person the action is for could not reach any screen
        // that offers it. The permission was real and unreachable.
        //
        // Same spec, same DayScreen, same endpoint, same state machine:
        // nothing is copied. What differs is the permission on the ROUTE,
        // which is the thing that was wrong. DayScreen already filters
        // every action by its own permission (day-screen.ts), so booking
        // and status changes stay invisible here without being restated -
        // a therapist sees exactly one verb, and it is the one they hold.
        // Retired as a route: it is the same screen with `mine=1`, and now
        // it is the same screen with `?view=mine`. The heading and the
        // empty-state text that were route data are chosen by the view.
        path: 'my-day',
        redirectTo: movedTo('/appointments', { view: 'mine' }),
      },
      {
        path: 'sessions',
        canActivate: [permissionGuard],
        component: DayScreen,
        data: {
          navKey: 'sessions', titleKey: 'nav.sessions',
          permission: 'SESSION.START', spec: SESSIONS_SPEC,
        },
      },
      {
        path: 'reports',
        canActivate: [permissionGuard],
        component: DayScreen,
        data: {
          navKey: 'reports', titleKey: 'nav.reports',
          permission: 'REPORT.VIEW', spec: REPORTS_SPEC,
        },
      },
      {
        path: 'billing',
        canActivate: [permissionGuard],
        component: DayScreen,
        data: {
          navKey: 'billing', titleKey: 'nav.billing',
          permission: 'BILLING.VIEW', spec: INVOICES_SPEC,
        },
      },
      {
        path: 'requests',
        canActivate: [permissionGuard],
        component: DayScreen,
        data: {
          navKey: 'requests', titleKey: 'nav.requests',
          permission: 'REQUEST.MANAGE', spec: REQUESTS_SPEC,
        },
      },
      {
        // One application, worked on in one place: header, next step, tabs,
        // and the list's own action dialogs opened from here
        // (docs/UX-DETAIL-PAGES.md section 1). The list stays the queue.
        path: 'enrolments/:applicationId',
        canActivate: [permissionGuard],
        data: {
          navKey: 'enrolments', titleKey: 'enrolment.title', permission: 'ENROLMENT.MANAGE',
          tabTitles: tabsByPrefix('enrolment.tab.', ENROLMENT_TABS),
        },
        loadComponent: () =>
          import('./features/enrolment/enrolment-detail').then((m) => m.EnrolmentDetail),
      },
      {
        // The screen the static designs called "leads". It had no route
        // until now because it had no table; migration 0018 gave it one.
        path: 'enrolments',
        canActivate: [permissionGuard],
        component: DayScreen,
        data: {
          navKey: 'enrolments', titleKey: 'nav.enrolments',
          permission: 'ENROLMENT.MANAGE', spec: ENROLMENTS_SPEC,
        },
      },

      {
        // Editing a therapist's own profile, and publishing it. Eight write
        // endpoints had nothing calling them: the only way to write a
        // biography was curl.
        path: 'therapists/:therapistId/profile',
        // NO permission guard, and that is the point rather than an omission.
        //
        // Who may open this is a question about the ROW - "your own profile,
        // or you manage staff" - and a route guard can only ask a question
        // about the person. Gating it on STAFF.MANAGE, which is what it had
        // at first, locked out the therapist: THERAPIST does not hold that
        // permission, so the one person who can record the consent could not
        // reach the screen that records it. The feature was unreachable by
        // the only person it needs.
        //
        // The same mistake the service made by putting these columns on the
        // general resource, one layer up. The service decides; this route
        // only requires a signed-in member of staff, which the parent route
        // already does.
        data: { navKey: 'therapists', titleKey: 'tprofile.title' },
        loadComponent: () => import('./features/therapist-profile/therapist-profile')
          .then((m) => m.TherapistProfileEditor),
      },
      {
        // Watching a session that is happening right now. Live only: nothing
        // is ever recorded, so there is no clip to open afterwards and no
        // seek bar on the player.
        path: 'sessions/:sessionId/live',
        canActivate: [permissionGuard],
        data: { navKey: 'sessions', titleKey: 'live.title', permission: 'LIVE.VIEW' },
        loadComponent: () => import('./features/live/live-view').then((m) => m.LiveView),
      },
      {
        // User administration: accounts, roles, staff records and papers,
        // plus the "which screen needs which permission" table it started
        // as. The screen creates users and assigns roles, so it is guarded
        // by the permission those writes need rather than by the one every
        // account holds (OQ-19). The database refuses the writes regardless.
        path: 'users',
        canActivate: [permissionGuard],
        data: { navKey: 'users', titleKey: 'nav.users', permission: 'USER.MANAGE' },
        loadComponent: () => import('./features/access/access').then((m) => m.Access),
      },
      { path: 'access', redirectTo: 'users', pathMatch: 'full' },
      {
        // The surveys and what the families answered, on one screen: the
        // survey definitions as a resource tab, the results as a component
        // tab. The guard names NPS.MANAGE, which is what the database asks
        // of both (it used to say CATALOG.MANAGE - a second answer to the
        // same question).
        path: 'satisfaction',
        canActivate: [permissionGuard],
        component: ResourceScreen,
        data: resourceScreen({
          navKey: 'satisfaction', titleKey: 'nav.satisfaction', permission: 'NPS.MANAGE',
          specs: [NPS_SURVEYS_SPEC],
          extraTabs: [{
            key: 'results', titleKey: 'satisfaction.results',
            permission: 'NPS.MANAGE', component: Satisfaction,
          }],
        }),
      },
      {
        // What the service has been doing: one row per finished request,
        // three views over it. The only screen here about the system rather
        // than about a child.
        path: 'ops-log',
        canActivate: [permissionGuard],
        data: { navKey: 'opslog', titleKey: 'nav.opslog', permission: 'OPS.VIEW' },
        loadComponent: () => import('./features/ops-log/ops-log').then((m) => m.OpsLog),
      },
      {
        // Read only, because nothing else is possible: no endpoint reads or
        // writes sys_params or the centre row. What is here comes from /me.
        path: 'settings',
        canActivate: [permissionGuard],
        // SETTINGS.MANAGE: the permission hbh.set_center_param asks for. The
        // guard used to name CATALOG.MANAGE, a different right that happened
        // to belong to the same role.
        data: { navKey: 'settings', titleKey: 'nav.settings', permission: 'SETTINGS.MANAGE' },
        loadComponent: () =>
          import('./features/settings/settings').then((m) => m.Settings),
      },
      {
        path: 'denied',
        data: { titleKey: 'denied.title' },
        loadComponent: () => import('./features/denied/denied').then((m) => m.Denied),
      },
      { path: '', pathMatch: 'full', redirectTo: '/dashboard' },
    ],
  },
  { path: '**', redirectTo: '/dashboard' },
];
