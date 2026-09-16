import ar from '../../../assets/i18n/ar.json';
import { activityFor, applicationsOf, nextAppointment, openApplications, requestsOf } from './guardian-detail.model';

/**
 * The guardian page's derived facts. The service has no "applications of a
 * guardian" read, so the page filters a page of the queue by the two keys
 * the schema keeps - the id stamped at conversion and the canonical mobile.
 * These tests hold that filter to exactly those two keys and nothing
 * looser (a name match would attach a stranger's application).
 */
const BUNDLE = ar as Record<string, string>;

const GUARDIAN = { guardian_id: 9, full_name_ar: 'منى سعيد', mobile: '+201155667788', created_at: '2026-09-01T09:00:00Z' };

describe('applicationsOf', () => {
  it('keeps the application converted to this guardian, and the one typed with the same mobile', () => {
    const rows = applicationsOf(GUARDIAN, [
      { application_id: 1, converted_guardian_id: 9, parent_mobile: '+20100' },
      { application_id: 2, parent_mobile: '+201155667788' },
      { application_id: 3, parent_mobile: '+20199', parent_name_ar: 'منى سعيد' },
    ]);
    expect(rows.map((r) => r['application_id'])).toEqual([1, 2]);
  });

  it('never matches on an empty mobile', () => {
    expect(applicationsOf({ guardian_id: 9, mobile: '' }, [{ application_id: 1, parent_mobile: '' }])).toEqual([]);
  });
});

describe('requestsOf and openApplications', () => {
  it('keeps the requests that name the guardian', () => {
    expect(requestsOf(9, [{ request_id: 1, guardian: { guardian_id: 9 } }, { request_id: 2, guardian: { guardian_id: 8 } }, { request_id: 3 }])
      .map((r) => r['request_id'])).toEqual([1]);
  });

  it('counts only the three open statuses', () => {
    expect(openApplications([{ status: 'NEW' }, { status: 'CONTACTED' }, { status: 'ASSESSMENT_BOOKED' }, { status: 'ENROLLED' }, { status: 'REJECTED' }]).length).toBe(3);
  });
});

describe('nextAppointment', () => {
  it('is the soonest live appointment after now, across children', () => {
    const now = '2026-09-13T12:00:00Z';
    const next = nextAppointment([
      { childId: 1, childName: 'أ', row: { starts_at: '2026-09-14T10:00:00Z', status: 'BOOKED' } },
      { childId: 2, childName: 'ب', row: { starts_at: '2026-09-13T13:00:00Z', status: 'CONFIRMED' } },
      { childId: 2, childName: 'ب', row: { starts_at: '2026-09-13T12:30:00Z', status: 'CANCELLED' } },
      { childId: 1, childName: 'أ', row: { starts_at: '2026-09-12T10:00:00Z', status: 'BOOKED' } },
    ], now);
    expect(next?.childName).toBe('ب');
    expect(next?.row['starts_at']).toBe('2026-09-13T13:00:00Z');
  });

  it('is null when nothing is ahead', () => {
    expect(nextAppointment([], '2026-09-13T12:00:00Z')).toBeNull();
  });
});

describe('activityFor', () => {
  it('orders the family\'s stamps newest first, links each to its row, and invents nothing', () => {
    const events = activityFor(GUARDIAN,
      [{ child_id: 5, full_name_ar: 'عمر', created_at: '2026-09-10T09:00:00Z' }],
      [{ application_id: 1, child_name_ar: 'عمر', submitted_at: '2026-09-03T08:00:00Z', decided_at: '2026-09-10T08:59:00Z', status: 'ENROLLED' }],
      [{ request_id: 7, kind_code: 'CALLBACK', status: 'NEW', created_at: '2026-09-11T08:00:00Z' }]);
    expect(events.map((e) => e.key)).toEqual([
      'guardian.event.requested', 'guardian.event.childCreated', 'guardian.event.converted',
      'guardian.event.applied', 'guardian.event.created',
    ]);
    expect(events[1].link).toEqual(['/children', 5]);
    expect(events[2].link).toEqual(['/enrolments', 1]);
    for (const event of events) {
      expect(BUNDLE[event.key]).withContext(event.key).toBeDefined();
    }
  });

  it('is empty for a guardian with no stamps and no family', () => {
    expect(activityFor({ guardian_id: 1 }, [], [], [])).toEqual([]);
  });
});
