import { IconName } from '@hbh/shared/icon/icon';

/**
 * The console's menu, and the permission each entry needs.
 *
 * The permission codes are the server's own, from the RBAC seed. They are
 * named here only to decide what to draw - `GET /me` returns the caller's
 * list and the shell keeps the entries that match. There is no copy of who
 * holds what: that mapping stays in the database, where it is enforced.
 *
 * GROUPED BY WHAT THE WORK IS ABOUT, not by table and not by status
 * (docs/UX-TARGET-INFORMATION-ARCHITECTURE.md). A status is a filter on a
 * screen, never an entry here; a screen that is one tab of another is not
 * an entry either. The three entries above the groups are the ones every
 * shift starts from: the numbers, what needs doing, what happened.
 */
export interface NavEntry {
  readonly key: string;
  readonly path: string;
  readonly icon: IconName;
  readonly labelKey: string;
  /** The server permission this screen needs. */
  readonly permission: string;
  /**
   * A second permission that also opens it. One screen, two audiences:
   * the diary is reception's by APPOINTMENT.BOOK and the clinician's own
   * day by SESSION.START. The route carries the same pair.
   */
  readonly altPermission?: string;
  /** Query parameters the entry opens with (a default view). */
  readonly query?: Readonly<Record<string, string>>;
  /** A live count drawn beside the label. */
  readonly badge?: 'tasks' | 'notifications';
  /** Drawn only for an account with a therapist profile ("my profile"). */
  readonly needsTherapist?: boolean;
}

export interface NavGroup {
  readonly key: string;
  /** Absent on the ungrouped entries at the top. */
  readonly labelKey?: string;
  readonly entries: readonly NavEntry[];
}

export const OPS_NAV_GROUPS: readonly NavGroup[] = [
  {
    key: 'top',
    entries: [
      { key: 'favorites', path: '/favorites', icon: 'ic-star', labelKey: 'nav.favorites', permission: 'PORTAL.VIEW' },
      {
        key: 'dashboard', path: '/dashboard', icon: 'ic-grid',
        labelKey: 'nav.dashboard', permission: 'PORTAL.VIEW',
      },
      {
        // What needs doing, derived from the state of rows everyone can
        // already see. Gated on the permission every account holds; the
        // list itself is narrowed by each task's own permission.
        key: 'tasks', path: '/tasks', icon: 'ic-check-circle',
        labelKey: 'nav.tasks', permission: 'PORTAL.VIEW', badge: 'tasks',
      },
      {
        // Everybody who signs in has a feed, so it is gated on the
        // permission every account holds rather than on a new one. A
        // notification is addressed to a person by user_id; there is no
        // view of somebody else's to protect with a separate right.
        key: 'notifications', path: '/notifications', icon: 'ic-bell',
        labelKey: 'nav.notifications', permission: 'PORTAL.VIEW', badge: 'notifications',
      },
    ],
  },
  {
    key: 'customers', labelKey: 'nav.group.customers',
    entries: [
      {
        key: 'enrolments', path: '/enrolments', icon: 'ic-user-plus',
        labelKey: 'nav.enrolments', permission: 'ENROLMENT.MANAGE',
      },
      {
        key: 'guardians', path: '/guardians', icon: 'ic-user',
        labelKey: 'nav.guardians', permission: 'GUARDIAN.MANAGE',
      },
      {
        key: 'children', path: '/children', icon: 'ic-users',
        labelKey: 'nav.children', permission: 'CHILD.VIEW_ALL',
      },
    ],
  },
  {
    key: 'operations', labelKey: 'nav.group.operations',
    entries: [
      {
        key: 'appointments', path: '/appointments', icon: 'ic-calendar',
        labelKey: 'nav.appointments', permission: 'APPOINTMENT.BOOK', altPermission: 'SESSION.START',
      },
      {
        key: 'sessions', path: '/sessions', icon: 'ic-activity',
        labelKey: 'nav.sessions', permission: 'SESSION.START',
      },
      {
        key: 'plans', path: '/plans', icon: 'ic-target',
        labelKey: 'plans.plans', permission: 'PLAN.MANAGE',
      },
      {
        key: 'reports', path: '/reports', icon: 'ic-file',
        labelKey: 'nav.reports', permission: 'REPORT.VIEW',
      },
    ],
  },
  {
    key: 'finance', labelKey: 'nav.group.finance',
    entries: [
      {
        key: 'billing', path: '/billing', icon: 'ic-card',
        labelKey: 'nav.billing', permission: 'BILLING.VIEW',
      },
    ],
  },
  {
    key: 'communication', labelKey: 'nav.group.communication',
    entries: [
      {
        key: 'requests', path: '/requests', icon: 'ic-help',
        labelKey: 'nav.requests', permission: 'REQUEST.MANAGE',
      },
      {
        key: 'communications', path: '/communications', icon: 'ic-chat',
        labelKey: 'nav.communications', permission: 'PORTAL.VIEW',
      },
    ],
  },
  {
    key: 'team', labelKey: 'nav.group.team',
    entries: [
      {
        key: 'therapists', path: '/therapists', icon: 'ic-user-check',
        labelKey: 'nav.therapists', permission: 'STAFF.MANAGE',
      },
      {
        key: 'site-team', path: '/site/team', icon: 'ic-file',
        labelKey: 'nav.teamProfiles', permission: 'SITE.EDIT',
      },
      {
        // The clinician's own public profile. The route has no permission
        // guard (the row decides whose it is); the entry is drawn only for
        // an account that has a profile to open.
        key: 'my-profile', path: '/therapists/me/profile', icon: 'ic-user',
        labelKey: 'nav.myProfile', permission: 'PORTAL.VIEW', needsTherapist: true,
      },
      {
        key: 'users', path: '/users', icon: 'ic-shield',
        labelKey: 'nav.users', permission: 'USER.MANAGE',
      },
    ],
  },
  {
    key: 'settings', labelKey: 'nav.group.settings',
    entries: [
      {
        key: 'catalog', path: '/catalog', icon: 'ic-tag',
        labelKey: 'nav.catalog', permission: 'CATALOG.MANAGE',
      },
      {
        key: 'rooms', path: '/rooms', icon: 'ic-video',
        labelKey: 'nav.rooms', permission: 'CATALOG.MANAGE',
      },
      {
        key: 'satisfaction', path: '/satisfaction', icon: 'ic-star',
        labelKey: 'nav.satisfaction', permission: 'NPS.MANAGE',
      },
      {
        // SITE.EDIT and not SITE.PUBLISH: this decides whether the entry is
        // DRAWN, and somebody who may draft but not publish still needs the
        // screen. The publishing gate is in the database.
        key: 'site', path: '/site', icon: 'ic-globe',
        labelKey: 'nav.site', permission: 'SITE.EDIT',
      },
      {
        key: 'settings', path: '/settings', icon: 'ic-sliders',
        labelKey: 'nav.settings', permission: 'SETTINGS.MANAGE',
      },
      {
        key: 'opslog', path: '/ops-log', icon: 'ic-db',
        labelKey: 'nav.opslog', permission: 'OPS.VIEW',
      },
    ],
  },
];

/**
 * The same entries, flat, for the screens that list "which screen needs
 * which permission" (features/access) and for the route/menu test.
 * "my-profile" is left out: it is a personal shortcut to a route the test
 * already exempts, not a screen with a permission of its own.
 */
export const OPS_NAV: readonly NavEntry[] = OPS_NAV_GROUPS
  .flatMap((group) => group.entries)
  .filter((entry) => !entry.needsTherapist);
