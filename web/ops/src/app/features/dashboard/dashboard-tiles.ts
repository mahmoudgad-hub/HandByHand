import { IconName } from '@hbh/shared/icon/icon';
import { DayQuery, DayResource } from '../../core/ops/day-api';

/**
 * One figure on the dashboard, and where it comes from.
 *
 * Every tile is a real count from the service, obtained the cheap way: the
 * list endpoints answer with `total` for the whole filter, so asking with
 * `limit=1` returns one row and the number. No endpoint sums anything, and
 * this screen does not page through a list to add up its own totals - a
 * figure assembled from the first page of a longer list is a figure that is
 * wrong exactly when it matters.
 *
 * WHAT IS NOT HERE, AND WHY:
 *
 *   Revenue, and outstanding money across the centre. The static design asks
 *   for both. No endpoint sums money, and adding up a page of invoices would
 *   give a number that is right on a quiet centre and quietly wrong on a busy
 *   one. Requested; not invented.
 *
 *   Room occupancy and staff alerts. Same: there is no read behind either.
 *
 * EVERY TILE IS A LINK. A count somebody cannot act on is decoration; this
 * one opens the screen already filtered to the rows it counted.
 */
/**
 * The icon box's tint, from the shared palette's `.hbh-t--*` pairs.
 *
 * It groups rather than decorates: blue and green for the day as it stands,
 * amber and purple for what is waiting on somebody, red for money owed, navy
 * for the centre's standing figures. Nothing here is a status colour - a
 * status belongs to a row, and the tint of a tile that always looks the same
 * cannot carry one.
 */
export type Tone = 'blue' | 'green' | 'amber' | 'purple' | 'navy' | 'red';

export interface Tile {
  readonly key: string;
  readonly labelKey: string;
  readonly icon: IconName;
  /** The icon box's tint. Grouping, not decoration - see the template. */
  readonly tone: Tone;
  /** Drawn only for an account the server granted this. */
  readonly permission: string;
  readonly resource: DayResource | 'children';
  readonly query: DayQuery;
  /** Where the number leads, filtered the same way it was counted. */
  readonly link: readonly string[];
  readonly linkQuery?: Record<string, string>;
  /** Emphasised when non-zero: these are the ones somebody must act on. */
  readonly wantsAction?: boolean;
}

export const DASHBOARD_TILES: readonly Tile[] = [
  // ---- today ----
  {
    key: 'appointmentsToday', labelKey: 'dash.appointmentsToday', icon: 'ic-calendar', tone: 'blue',
    permission: 'APPOINTMENT.BOOK', resource: 'appointments', query: {},
    link: ['/appointments'],
  },
  {
    key: 'checkedIn', labelKey: 'dash.checkedIn', icon: 'ic-user-check', tone: 'green',
    permission: 'APPOINTMENT.BOOK', resource: 'appointments', query: { status: 'CHECKED_IN' },
    link: ['/appointments'], linkQuery: { status: 'CHECKED_IN' },
  },
  {
    key: 'liveSessions', labelKey: 'dash.liveSessions', icon: 'ic-activity', tone: 'amber',
    permission: 'SESSION.START', resource: 'sessions', query: { status: 'IN_PROGRESS' },
    link: ['/sessions'], linkQuery: { status: 'IN_PROGRESS' },
  },

  // ---- waiting for somebody ----
  //
  // These four are TASKS, and they open the task inbox filtered to their
  // kind rather than the raw list: the inbox shows the same rows with the
  // action each one needs, which is what a person clicking "new requests"
  // came for. The count is still the list endpoint's own `total`.
  {
    key: 'newEnrolments', labelKey: 'dash.newEnrolments', icon: 'ic-user-plus', tone: 'purple',
    permission: 'ENROLMENT.MANAGE', resource: 'enrolments', query: { status: 'NEW' },
    link: ['/tasks'], linkQuery: { type: 'ENROLMENT_TRIAGE' }, wantsAction: true,
  },
  {
    key: 'newRequests', labelKey: 'dash.newRequests', icon: 'ic-chat', tone: 'purple',
    permission: 'REQUEST.MANAGE', resource: 'requests', query: { status: 'NEW' },
    link: ['/tasks'], linkQuery: { type: 'REQUEST_DECIDE' }, wantsAction: true,
  },
  {
    key: 'draftReports', labelKey: 'dash.draftReports', icon: 'ic-file', tone: 'amber',
    permission: 'REPORT.VIEW', resource: 'reports', query: { status: 'DRAFT' },
    link: ['/tasks'], linkQuery: { type: 'REPORT_FINISH' }, wantsAction: true,
  },
  {
    key: 'unpaidInvoices', labelKey: 'dash.unpaidInvoices', icon: 'ic-money', tone: 'red',
    // ISSUED only. PARTIALLY_PAID would need a second call and the two cannot
    // be added without asking twice; the screen counts what one filter counts
    // rather than implying a sum it did not make. The task inbox lists the
    // OVERDUE ones, which is the subset somebody has to chase.
    permission: 'BILLING.VIEW', resource: 'invoices', query: { status: 'ISSUED' },
    link: ['/tasks'], linkQuery: { type: 'INVOICE_OVERDUE' }, wantsAction: true,
  },

  // ---- the centre ----
  {
    key: 'activeChildren', labelKey: 'dash.activeChildren', icon: 'ic-users', tone: 'navy',
    permission: 'CHILD.VIEW_ALL', resource: 'children', query: {},
    link: ['/children'],
  },
];
