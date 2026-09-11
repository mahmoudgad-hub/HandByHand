import { Row } from '../../core/api/ops-api';
import { openAhead, runningNow, startable } from './day-summary';

/**
 * THE FIRST SPEC IN THE OPERATIONS CONSOLE.
 *
 * Not a milestone worth celebrating - the project has shipped for months
 * with `npm test` printing "TOTAL: 0 SUCCESS" and exiting 0, which is why
 * scripts/web.sh now refuses a project with no spec at all.
 *
 * It is here because of a specific gap: the centre's weekend is Friday and
 * Saturday, no therapist has working hours on either, and validate_slot
 * refuses a booking outside them. So on the day this panel was written the
 * live console could only ever render its empty state, and the branch that
 * actually matters - "who is next" - had nothing to render against. The
 * alternative was to give a therapist Friday hours in the database, which
 * is inventing a fact about the centre to make a screen testable.
 */
function appointment(
  id: number, status: string, starts: string, ends: string,
): Row {
  return {
    appointment_id: id,
    status,
    starts_at: starts,
    ends_at: ends,
  } as unknown as Row;
}

/** 2026-09-14 is a Monday, a working day for every therapist seeded. */
const NOON = Date.parse('2026-09-14T09:00:00Z');

describe('openAhead', () => {
  it('orders what is left by start time', () => {
    const rows = [
      appointment(2, 'BOOKED', '2026-09-14T12:00:00Z', '2026-09-14T13:00:00Z'),
      appointment(1, 'CONFIRMED', '2026-09-14T10:00:00Z', '2026-09-14T11:00:00Z'),
    ];
    expect(openAhead(rows, NOON).map((r) => r['appointment_id'])).toEqual([1, 2]);
  });

  it('drops what has already finished', () => {
    const rows = [
      appointment(1, 'BOOKED', '2026-09-14T07:00:00Z', '2026-09-14T08:00:00Z'),
      appointment(2, 'BOOKED', '2026-09-14T10:00:00Z', '2026-09-14T11:00:00Z'),
    ];
    expect(openAhead(rows, NOON).map((r) => r['appointment_id'])).toEqual([2]);
  });

  it('keeps an appointment that has started but not ended', () => {
    // The cut is on ends_at. Cutting on starts_at would blank the panel
    // during the very session it is describing.
    const rows = [
      appointment(1, 'CHECKED_IN', '2026-09-14T08:30:00Z', '2026-09-14T09:30:00Z'),
    ];
    expect(openAhead(rows, NOON).length).toBe(1);
  });

  it('drops cancelled, no-show and completed rows', () => {
    // Today's history, not today's work. A cancelled row under "next"
    // sends somebody to a room for an appointment nobody is coming to.
    const rows = ['CANCELLED', 'NO_SHOW', 'COMPLETED'].map(
      (status, i) => appointment(
        i, status, '2026-09-14T12:00:00Z', '2026-09-14T13:00:00Z'));
    expect(openAhead(rows, NOON)).toEqual([]);
  });

  it('keeps a row whose end time cannot be read', () => {
    // NaN >= now is false, so the obvious comparison would have hidden a
    // real appointment because one field was malformed - silently.
    const rows = [appointment(1, 'BOOKED', '2026-09-14T12:00:00Z', '')];
    expect(openAhead(rows, NOON).length).toBe(1);
  });

  it('does not reorder the caller\'s array', () => {
    // The rows come from a signal the template also reads. Sorting in
    // place would rearrange the list under whatever else is rendering it.
    const rows = [
      appointment(2, 'BOOKED', '2026-09-14T12:00:00Z', '2026-09-14T13:00:00Z'),
      appointment(1, 'BOOKED', '2026-09-14T10:00:00Z', '2026-09-14T11:00:00Z'),
    ];
    openAhead(rows, NOON);
    expect(rows.map((r) => r['appointment_id'])).toEqual([2, 1]);
  });
});

describe('runningNow', () => {
  it('finds the session the child is already in', () => {
    const rows = [
      appointment(1, 'BOOKED', '2026-09-14T10:00:00Z', '2026-09-14T11:00:00Z'),
      appointment(2, 'CHECKED_IN', '2026-09-14T08:30:00Z', '2026-09-14T09:30:00Z'),
    ];
    expect(runningNow(rows)?.['appointment_id']).toBe(2);
  });

  it('is null when nobody has checked in', () => {
    const rows = [
      appointment(1, 'CONFIRMED', '2026-09-14T10:00:00Z', '2026-09-14T11:00:00Z'),
    ];
    expect(runningNow(rows)).toBeNull();
  });
});

describe('startable', () => {
  function checkedIn(sessionId: number | null): Row {
    return {
      appointment_id: 1,
      status: 'CHECKED_IN',
      starts_at: '2026-09-14T10:00:00Z',
      ends_at: '2026-09-14T11:00:00Z',
      session_id: sessionId,
    } as unknown as Row;
  }

  it('offers the start once the child has checked in', () => {
    expect(startable(checkedIn(null))).toBe(true);
  });

  it('stops offering it once a session exists', () => {
    // The appointment STAYS CHECKED_IN while its session runs. Testing the
    // status alone left the button up, and a second press could only ever
    // return HB022 "this appointment already has a session".
    expect(startable(checkedIn(338))).toBe(false);
  });

  it('does not offer it before the child arrives', () => {
    // A session starts from CHECKED_IN and from nothing else. Offering it
    // at BOOKED or CONFIRMED produces NOT_CHECKED_IN every time.
    for (const status of ['BOOKED', 'CONFIRMED', 'COMPLETED', 'CANCELLED']) {
      const row = { ...checkedIn(null), status } as unknown as Row;
      expect(startable(row)).withContext(status).toBe(false);
    }
  });

  it('is false for no row at all', () => {
    expect(startable(null)).toBe(false);
  });
});
