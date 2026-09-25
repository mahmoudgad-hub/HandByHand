import { attendanceView } from './attendance';

/**
 * The attendance ring on the welcome screen.
 *
 * Tested here rather than on a screen because the two cases that matter
 * most - nothing counted, and nothing happened yet - are the ones real
 * dev data rarely produces on the day somebody looks.
 */
describe('attendanceView', () => {
  it('shows the share of sessions attended', () => {
    expect(attendanceView({ attended: 3, missed: 1 }))
      .toEqual({ percent: 75, attended: 3, total: 4 });
  });

  it('draws nothing when the service sent no counts', () => {
    // The old card answered this with a permanent dash and "unavailable".
    expect(attendanceView(null)).toBeNull();
  });

  it('draws nothing when no session has happened yet this month', () => {
    // 0% here would accuse a child of missing sessions nobody held.
    expect(attendanceView({ attended: 0, missed: 0 })).toBeNull();
  });

  it('is 100 with no misses, and 0 with no attendance', () => {
    expect(attendanceView({ attended: 5, missed: 0 })?.percent).toBe(100);
    expect(attendanceView({ attended: 0, missed: 2 })?.percent).toBe(0);
  });

  it('rounds rather than truncating', () => {
    // 2 of 3 is 66.67 - a family reading 66 would be told less than the truth.
    expect(attendanceView({ attended: 2, missed: 1 })?.percent).toBe(67);
  });
});
