import { Routes } from '@angular/router';

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
import { TeamScreen } from './features/team/team-screen';

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
      {path: 'communications',canActivate:[permissionGuard],data:{navKey:'communications',titleKey:'nav.communications',permission:'REQUEST.MANAGE'},loadComponent:()=>import('@hbh/shared/ui/family-messages').then(m=>m.FamilyMessages)},
      {
        path: 'inbox',
        canActivate: [permissionGuard],
        data: { navKey: 'inbox', titleKey: 'nav.inbox', permission: 'PORTAL.VIEW' },
        loadComponent: () =>
          import('./features/inbox/inbox').then((m) => m.Inbox),
      },
      {
        path: 'dashboard',
        canActivate: [permissionGuard],
        data: { navKey: 'dashboard', titleKey: 'nav.dashboard', permission: 'PORTAL.VIEW' },
        loadComponent: () =>
          import('./features/dashboard/dashboard').then((m) => m.Dashboard),
      },

      // ---- built on the CRUD resources ----
      {
        path: 'children',
        canActivate: [permissionGuard],
        component: ResourceScreen,
        data: {
          navKey: 'children', titleKey: 'nav.children',
          permission: 'CHILD.VIEW_ALL',
          specs: [GUARDIANS_SPEC, CHILDREN_SPEC],
        },
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
        data: { navKey: 'children', titleKey: 'child.title', permission: 'CHILD.VIEW_ALL' },
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
        data: {
          navKey: 'therapists', titleKey: 'nav.therapists',
          permission: 'STAFF.MANAGE',
          specs: [THERAPISTS_SPEC, WORKING_HOURS_SPEC, CASELOAD_SPEC],
        },
      },
      {
        path: 'rooms',
        canActivate: [permissionGuard],
        component: ResourceScreen,
        data: {
          navKey: 'rooms', titleKey: 'nav.rooms',
          permission: 'CATALOG.MANAGE',
          specs: [ROOMS_SPEC, CAMERAS_SPEC],
        },
      },
      {
        // The clinician's own work: the plan, its goals, the measurements
        // that show movement, and the home programme built from them. Four
        // resources the service has always served and nothing ever called -
        // a therapist could not write a plan from any screen.
        path: 'plans',
        canActivate: [permissionGuard],
        component: ResourceScreen,
        data: {
          navKey: 'plans', titleKey: 'plans.plans',
          permission: 'PLAN.MANAGE',
          specs: [PLANS_SPEC, GOALS_SPEC, MEASUREMENTS_SPEC, CHILD_ACTIVITIES_SPEC],
        },
      },
      {
        path: 'catalog',
        canActivate: [permissionGuard],
        component: ResourceScreen,
        data: {
          navKey: 'catalog', titleKey: 'nav.catalog',
          permission: 'CATALOG.MANAGE',
          specs: [SERVICES_SPEC, PACKAGES_SPEC, ACTIVITY_LIBRARY_SPEC, NPS_SURVEYS_SPEC],
        },
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
        data: {
          navKey: 'site', titleKey: 'nav.site',
          permission: 'SITE.EDIT',
          // The team's three tabs are gone from here. A qualification means
          // nothing apart from whose it is, so they now live inside the
          // member on /site/team - see TeamScreen. The resources themselves
          // are unchanged; this is one less place to hold a join in your
          // head.
          specs: [SITE_CONTACT_SPEC, SITE_SERVICES_SPEC, SITE_PROGRAMS_SPEC,
                  SITE_FAQ_SPEC, SITE_REVIEWS_SPEC, SITE_TEXTS_SPEC,
                  SITE_SECTIONS_SPEC],
        },
      },
      {
        // The team, as master and detail rather than three flat lists.
        path: 'site/team',
        canActivate: [permissionGuard],
        component: TeamScreen,
        data: {
          navKey: 'team', titleKey: 'site.team',
          permission: 'SITE.EDIT',
        },
      },

      // ---- the centre-indexed reads, and the verbs that change them ----
      //
      // These five arrived together with the eleven writes behind them, and
      // they are the reason this console does anything. All five run through
      // one screen: the columns and the verbs are descriptions in day-spec.
      {
        path: 'appointments',
        canActivate: [permissionGuard],
        component: DayScreen,
        data: {
          navKey: 'appointments', titleKey: 'nav.appointments',
          permission: 'APPOINTMENT.BOOK', spec: APPOINTMENTS_SPEC,
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
        path: 'my-day',
        canActivate: [permissionGuard],
        component: DayScreen,
        data: {
          navKey: 'my-day', titleKey: 'nav.myDay', subKey: 'myDay.sub',
          // An empty PERSONAL day says something different from an empty
          // centre day. "لا مواعيد في هذا اليوم" on this route reads as
          // "the centre is closed", when what is true is that this
          // clinician has nothing booked and a colleague may be busy.
          emptyKey: 'myDay.empty', emptyNoteKey: 'myDay.emptyNote',
          permission: 'SESSION.START', spec: APPOINTMENTS_SPEC,
        },
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
        // Which services each therapist practises. Without a row here no
        // appointment can be booked at all - validate_slot answers
        // THERAPIST_SERVICE_MISMATCH - and nothing in this console could
        // write the table until the endpoint arrived.
        path: 'therapist-services',
        canActivate: [permissionGuard],
        data: {
          navKey: 'therapists', titleKey: 'therapistServices.title',
          permission: 'STAFF.MANAGE',
        },
        loadComponent: () => import('./features/therapist-services/therapist-services')
          .then((m) => m.TherapistServices),
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
        // Which screen needs which permission, and whether you hold it.
        // NOT user administration: users, roles and permissions are five
        // tables with no endpoint of any kind. Requested.
        path: 'access',
        canActivate: [permissionGuard],
        data: { navKey: 'access', titleKey: 'access.title', permission: 'PORTAL.VIEW' },
        loadComponent: () => import('./features/access/access').then((m) => m.Access),
      },
      {
        // What the families answered. The centre could create surveys on the
        // catalogue screen long before it could read a single reply, so it was
        // asking a question it could not hear the answer to.
        path: 'satisfaction',
        canActivate: [permissionGuard],
        data: { navKey: 'satisfaction', titleKey: 'nav.satisfaction', permission: 'CATALOG.MANAGE' },
        loadComponent: () => import('./features/satisfaction/satisfaction').then((m) => m.Satisfaction),
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
        data: { navKey: 'settings', titleKey: 'nav.settings', permission: 'CATALOG.MANAGE' },
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
