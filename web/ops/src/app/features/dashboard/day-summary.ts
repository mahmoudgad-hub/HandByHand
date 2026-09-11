import { Row } from '../../core/api/ops-api';

/**
 * "What is left of my day", as two functions rather than two computeds.
 *
 * They are here and not inside Dashboard because THE BRANCH THEY DECIDE
 * CANNOT BE PRODUCED ON EVERY DAY OF THE WEEK. The centre's weekend is
 * Friday and Saturday, therapist_working_hours carries no row for either,
 * and validate_slot refuses a booking outside them - correctly. So on a
 * Friday the only state the live console can show is the empty one, and
 * "next appointment" renders against nothing.
 *
 * Booking one anyway would have meant giving the therapist Friday hours,
 * which is inventing a fact about the centre to make a screen testable.
 * These take a clock instead.
 */

/** The statuses that still mean somebody is expected. */
const OPEN = ['BOOKED', 'CONFIRMED', 'CHECKED_IN'];

/**
 * Today's appointments that have not finished yet, earliest first.
 *
 * CANCELLED, NO_SHOW and COMPLETED are today's history, not today's work.
 * Putting a cancelled row under "next" sends somebody to a room for an
 * appointment nobody is coming to.
 *
 * The cut is on `ends_at`, not `starts_at`: an appointment that began ten
 * minutes ago is the one happening now, and dropping it the moment its
 * start time passed would blank the panel during the session it describes.
 */
export function openAhead(rows: readonly Row[], now: number): readonly Row[] {
  return rows
    .filter((row) => OPEN.includes(String(row['status'])))
    .filter((row) => {
      const ends = new Date(String(row['ends_at'])).getTime();
      // A row whose end we cannot read is kept. It is a real appointment
      // with an unreadable field; hiding it loses the appointment, and the
      // comparison below would drop it silently (NaN >= now is false).
      return Number.isNaN(ends) || ends >= now;
    })
    .slice()
    .sort((a, b) => String(a['starts_at']).localeCompare(String(b['starts_at'])));
}

/**
 * The session already running, if there is one.
 *
 * CHECKED_IN means the child is in the building. That row also sorts first
 * under `openAhead`, so without this the panel would head it "next" while
 * the appointment is happening - and somebody reading "next at 10:00" at
 * 10:20 assumes they are early rather than late.
 */
export function runningNow(rows: readonly Row[]): Row | null {
  return rows.find((row) => String(row['status']) === 'CHECKED_IN') ?? null;
}

/**
 * Whether a session may be started from this row - everything except the
 * permission, which only a policy can answer.
 *
 * BOTH CONDITIONS ARE THE SCHEMA'S. A session starts from CHECKED_IN and
 * from nothing else (0005_scheduling.up.sql), and only once: the
 * appointment STAYS CHECKED_IN while its session runs, so the status test
 * alone leaves the button on screen afterwards and a second press can only
 * ever return HB022 "this appointment already has a session".
 *
 * Copied from day-spec's `start` action on purpose. The dashboard is a
 * SHORTCUT to that operation, and a shortcut offered under conditions of
 * its own is a second, quieter rule about when a session may begin.
 */
export function startable(row: Row | null | undefined): boolean {
  return !!row
    && String(row['status']) === 'CHECKED_IN'
    && row['session_id'] == null;
}
