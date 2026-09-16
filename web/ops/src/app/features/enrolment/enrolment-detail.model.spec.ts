import ar from '../../../assets/i18n/ar.json';
import { ENROLMENT_NEXT } from '../../core/ops/day-spec';
import {
  DEEP_LINK_ACTIONS, activityFor, deepLinkRequest, flagsFor, nextStepFor,
} from './enrolment-detail.model';

/**
 * The application page's derived facts, as pure functions.
 *
 * The next step is read off ENROLMENT_NEXT - the list screen's copy of the
 * schema's machine - so the first tests hold the page to that table rather
 * than to a second opinion. A deep link that names a transition the table
 * does not allow from the row's status must NOT open with that status
 * pre-selected; the third block is the reason this file exists.
 */
const BUNDLE = ar as Record<string, string>;

const NOW = new Date('2026-09-13T12:00:00Z');

function row(over: Record<string, unknown>): Record<string, unknown> {
  return {
    application_id: 116, application_no: 'ENR-2026-00116', status: 'NEW',
    parent_name_ar: 'منى سعيد', parent_mobile: '+201155667788',
    child_name_ar: 'عمر خالد', submitted_at: '2026-09-03T08:26:00Z',
    sibling_applications: 0, ...over,
  };
}

describe('nextStepFor', () => {
  it('follows ENROLMENT_NEXT: every pre-selected status is a legal transition from the row', () => {
    for (const status of ['NEW', 'CONTACTED']) {
      const step = nextStepFor(row({ status }));
      expect(step).withContext(status).not.toBeNull();
      const wanted = step!.prefill?.['status'];
      expect(wanted).withContext(status).toBeDefined();
      expect(ENROLMENT_NEXT[status]).withContext(`${status} -> ${wanted}`).toContain(wanted!);
    }
  });

  it('offers assessment scheduling after contact', () => {
    const step = nextStepFor(row({ status: 'CONTACTED' }));
    expect(step?.actionType).toBe('status');
    expect(step?.prefill).toEqual({ status: 'ASSESSMENT_BOOKED' });
  });

  it('asks for convert from ASSESSMENT_BOOKED, which the list offers there too', () => {
    const step = nextStepFor(row({ status: 'ASSESSMENT_BOOKED' }));
    expect(step?.actionType).toBe('convert');
  });

  it('links to the child once enrolled, and has no dialog', () => {
    const step = nextStepFor(row({ status: 'ENROLLED', converted_child_id: 651 }));
    expect(step?.actionType).toBeNull();
    expect(step?.link).toEqual(['/children', 651]);
  });

  it('has no step on a decided application', () => {
    expect(nextStepFor(row({ status: 'REJECTED' }))).toBeNull();
    expect(nextStepFor(row({ status: 'DUPLICATE' }))).toBeNull();
  });

  it('names only keys the bundle has, so nothing prints as a raw key', () => {
    for (const status of ['NEW', 'CONTACTED', 'ASSESSMENT_BOOKED', 'ENROLLED']) {
      const step = nextStepFor(row({ status, converted_child_id: 1 }))!;
      for (const key of [step.descriptionKey, step.ctaKey, step.roleKey]) {
        expect(BUNDLE[key]).withContext(key).toBeDefined();
      }
    }
  });
});

describe('deepLinkRequest', () => {
  it('opens the contact dialog from NEW with CONTACTED pre-selected', () => {
    expect(deepLinkRequest('contact', row({ status: 'NEW' })))
      .toEqual({ actionType: 'status', prefill: { status: 'CONTACTED' } });
  });

  it('drops a pre-selected status the machine does not allow from here, but still opens the dialog', () => {
    // Legacy booking links remain readable without selecting an unsupported booking.
    expect(deepLinkRequest('book-assessment', row({ status: 'NEW' }))).toEqual({ actionType: 'status' });
  });

  it('does not preselect assessment booking even from CONTACTED', () => {
    expect(deepLinkRequest('book-assessment', row({ status: 'CONTACTED' })))
      .toEqual({ actionType: 'status' });
  });

  it('refuses convert where the list refuses it', () => {
    expect(deepLinkRequest('convert', row({ status: 'NEW' }))).toBeNull();
    expect(deepLinkRequest('convert', row({ status: 'CONTACTED' }))?.actionType).toBe('convert');
  });

  it('opens nothing on a decided row or an unknown name', () => {
    expect(deepLinkRequest('contact', row({ status: 'ENROLLED' }))).toBeNull();
    expect(deepLinkRequest('drop-tables', row({ status: 'NEW' }))).toBeNull();
    expect(deepLinkRequest(null, row({}))).toBeNull();
  });

  it('every deep-link name maps to an action the list has', () => {
    for (const name of Object.keys(DEEP_LINK_ACTIONS)) {
      expect(['status', 'convert']).toContain(DEEP_LINK_ACTIONS[name].actionType);
    }
  });
});

describe('flagsFor', () => {
  it('marks a new application nobody rang for more than a day', () => {
    const keys = flagsFor(row({ status: 'NEW' }), NOW).map((f) => f.key);
    expect(keys).toContain('enrolment.flag.stale');
  });

  it('does not mark a fresh one', () => {
    const keys = flagsFor(row({ status: 'NEW', submitted_at: '2026-09-13T11:00:00Z' }), NOW).map((f) => f.key);
    expect(keys).not.toContain('enrolment.flag.stale');
  });

  it('marks contacted-but-not-booked after three days, and siblings, as display flags', () => {
    const keys = flagsFor(row({ status: 'CONTACTED', contacted_at: '2026-09-01T10:00:00Z', sibling_applications: 1 }), NOW)
      .map((f) => f.key);
    expect(keys).toContain('enrolment.flag.contactedNotBooked');
    expect(keys).toContain('enrolment.flag.siblings');
  });

  it('names only keys the bundle has', () => {
    const all = [
      ...flagsFor(row({ status: 'NEW' }), NOW),
      ...flagsFor(row({ status: 'CONTACTED', contacted_at: '2026-09-01T10:00:00Z', sibling_applications: 2 }), NOW),
      ...flagsFor(row({ status: 'ASSESSMENT_BOOKED' }), NOW),
    ];
    for (const flag of all) {
      expect(BUNDLE[flag.key]).withContext(flag.key).toBeDefined();
    }
  });
});

describe('activityFor', () => {
  it('lists the row\'s own stamps newest first and invents nothing', () => {
    const events = activityFor(row({
      status: 'ENROLLED', contacted_at: '2026-09-05T09:00:00Z', decided_at: '2026-09-10T09:00:00Z',
    }), []);
    expect(events.map((e) => e.key)).toEqual([
      'enrolment.event.converted', 'enrolment.event.contacted', 'enrolment.event.created',
    ]);
  });

  it('names the decision by the status it produced', () => {
    expect(activityFor(row({ status: 'REJECTED', decided_at: '2026-09-10T09:00:00Z' }), [])[0].key)
      .toBe('enrolment.event.rejected');
  });

  it('weaves the child\'s appointments in by their start', () => {
    const events = activityFor(row({ status: 'ENROLLED', decided_at: '2026-09-10T09:00:00Z' }), [
      { appointment_id: 1, starts_at: '2026-09-12T10:00:00Z', status: 'BOOKED', service: { name_ar: 'تخاطب' } },
    ]);
    expect(events[0].key).toBe('enrolment.event.appointment');
    expect(events[0].detail).toBe('تخاطب');
  });

  it('has nothing to say about a row with no stamps', () => {
    expect(activityFor({ status: 'NEW' }, [])).toEqual([]);
  });
});
