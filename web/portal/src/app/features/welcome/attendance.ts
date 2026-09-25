import { Child } from '../../core/models/portal.models';

/** What the attendance ring on a child card shows, when it shows. */
export interface AttendanceView {
  /** 0..100, rounded. */
  readonly percent: number;
  readonly attended: number;
  /** Attended plus missed - the sessions that actually took place or were missed. */
  readonly total: number;
}

/**
 * The ring, or null when there is nothing honest to put in it.
 *
 * Two cases draw nothing, and they are not the same case:
 *   - null: the service sent no counts. The card used to answer this - and
 *     every other case - with a permanent dash and "غير متاحة حاليًا", which
 *     reads as a feature that is briefly down and was in fact a feature
 *     that did not exist.
 *   - zero of zero: nothing has happened yet this month. Early in a month
 *     that is the normal state, and 0% would accuse a child of missing
 *     sessions that were never held.
 *
 * Only the ARITHMETIC lives here. Which appointments count as attended or
 * missed is decided in hbh.child_attendance_month, and this function has no
 * opinion about statuses at all - it divides two numbers it was given.
 */
export function attendanceView(counts: Child['attendanceMonth']): AttendanceView | null {
  if (!counts) {
    return null;
  }
  const total = counts.attended + counts.missed;
  if (total <= 0) {
    return null;
  }
  return {
    percent: Math.round((counts.attended / total) * 100),
    attended: counts.attended,
    total,
  };
}
