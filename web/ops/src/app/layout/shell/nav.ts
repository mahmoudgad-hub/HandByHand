import { IconName } from '@hbh/shared/icon/icon';

/**
 * The console's menu, and the permission each entry needs.
 *
 * The permission codes are the server's own, from the RBAC seed. They are
 * named here only to decide what to draw - `GET /me` returns the caller's
 * list and the shell keeps the entries that match. There is no copy of who
 * holds what: that mapping stays in the database, where it is enforced.
 *
 */
export interface NavEntry {
  readonly key: string;
  readonly path: string;
  readonly icon: IconName;
  readonly labelKey: string;
  /** The server permission this screen needs. */
  readonly permission: string;
}

export const OPS_NAV: readonly NavEntry[] = [
  {
    // Everybody who signs in has an inbox, so it is gated on the permission
    // every account holds rather than on a new one. A notification is
    // addressed to a person by user_id; there is no view of somebody
    // else's to protect with a separate right.
    key: 'inbox', path: '/inbox', icon: 'ic-bell',
    labelKey: 'nav.inbox', permission: 'PORTAL.VIEW',
  },
  {
    key: 'dashboard', path: '/dashboard', icon: 'ic-grid',
    labelKey: 'nav.dashboard', permission: 'PORTAL.VIEW',
  },
  {
    key: 'children', path: '/children', icon: 'ic-users',
    labelKey: 'nav.children', permission: 'CHILD.VIEW_ALL',
  },
  {
    key: 'appointments', path: '/appointments', icon: 'ic-calendar',
    labelKey: 'nav.appointments', permission: 'APPOINTMENT.BOOK',
  },
  {
    // Above /sessions on purpose: this is where a clinician's day starts,
    // and /sessions is where it is once it is already running.
    key: 'my-day', path: '/my-day', icon: 'ic-play',
    labelKey: 'nav.myDay', permission: 'SESSION.START',
  },
  {
    key: 'sessions', path: '/sessions', icon: 'ic-activity',
    labelKey: 'nav.sessions', permission: 'SESSION.START',
  },
  {
    key: 'therapists', path: '/therapists', icon: 'ic-user-check',
    labelKey: 'nav.therapists', permission: 'STAFF.MANAGE',
  },
  {
    key: 'therapist-services', path: '/therapist-services', icon: 'ic-puzzle',
    labelKey: 'therapistServices.title', permission: 'STAFF.MANAGE',
  },
  {
    key: 'rooms', path: '/rooms', icon: 'ic-video',
    labelKey: 'nav.rooms', permission: 'CATALOG.MANAGE',
  },
  {
    key: 'plans', path: '/plans', icon: 'ic-target',
    labelKey: 'plans.plans', permission: 'PLAN.MANAGE',
  },
  {
    key: 'reports', path: '/reports', icon: 'ic-file',
    labelKey: 'nav.reports', permission: 'REPORT.VIEW',
  },
  {
    key: 'billing', path: '/billing', icon: 'ic-card',
    labelKey: 'nav.billing', permission: 'BILLING.VIEW',
  },
  {
    key: 'requests', path: '/requests', icon: 'ic-chat',
    labelKey: 'nav.requests', permission: 'REQUEST.MANAGE',
  },
  {key:'communications',path:'/communications',icon:'ic-chat',labelKey:'nav.communications',permission:'REQUEST.MANAGE'},
  {
    // Families who have never been here. This is the entry the note below
    // called "leads": it stayed out of the menu while it had no table, and
    // migration 0018 gave it one.
    key: 'enrolments', path: '/enrolments', icon: 'ic-user-plus',
    labelKey: 'nav.enrolments', permission: 'ENROLMENT.MANAGE',
  },
  {
    key: 'catalog', path: '/catalog', icon: 'ic-tag',
    labelKey: 'nav.catalog', permission: 'CATALOG.MANAGE',
  },
  {
    key: 'satisfaction', path: '/satisfaction', icon: 'ic-star',
    labelKey: 'nav.satisfaction', permission: 'CATALOG.MANAGE',
  },
  {
    // The public site's content. SITE.EDIT and not SITE.PUBLISH: this
    // decides whether the entry is DRAWN, and somebody who may draft but not
    // publish still needs the screen. The publishing gate is in the
    // database, where it cannot be got round by a URL.
    key: 'site', path: '/site', icon: 'ic-globe',
    labelKey: 'nav.site', permission: 'SITE.EDIT',
  },
  {
    // The team has its own entry because it is its own job: a person, their
    // qualifications, their certificates, their photograph and their
    // introduction film are edited together and nothing else on the site
    // screen is. It was three tabs among eight, and the qualifications tab
    // was a list of claims with a member_id where a name should be.
    key: 'team', path: '/site/team', icon: 'ic-users',
    labelKey: 'site.team', permission: 'SITE.EDIT',
  },
  {
    key: 'opslog', path: '/ops-log', icon: 'ic-db',
    labelKey: 'nav.opslog', permission: 'OPS.VIEW',
  },
  {
    key: 'access', path: '/access', icon: 'ic-shield',
    labelKey: 'access.title', permission: 'PORTAL.VIEW',
  },
  {
    key: 'settings', path: '/settings', icon: 'ic-sliders',
    labelKey: 'nav.settings', permission: 'CATALOG.MANAGE',
  },
];
