import { Row } from '../../core/api/ops-api';
import { ENROLMENT_NEXT } from '../../core/ops/day-spec';

/**
 * The application detail's derived facts - the next step, the flags, the
 * timeline - as pure functions over the row the service returns.
 *
 * NONE OF THIS IS A RULE. The next step is read off ENROLMENT_NEXT, the
 * copy of the schema's state machine that the list screen already uses;
 * the flags are display thresholds ("contacted three days ago and nothing
 * since"); the timeline is the row's own timestamps in order. Nothing here
 * is written back, and the dialogs these open re-check everything.
 */

export interface NextStep {
  /** i18n key of what is required now. */
  readonly descriptionKey: string;
  /** i18n key of the button. */
  readonly ctaKey: string;
  /** The action key in ENROLMENTS_SPEC that performs it, or null for a link. */
  readonly actionType: 'status' | 'convert' | null;
  readonly prefill?: Readonly<Record<string, string>>;
  /** Where a link-step goes. */
  readonly link?: readonly (string | number)[];
  /** The permission the step needs - drawn by, enforced elsewhere. */
  readonly permission: string;
  /** i18n key of who is expected to do it. A label, read off the permission. */
  readonly roleKey: string;
}

export function nextStepFor(row: Row): NextStep | null {
  const status = text(row, 'status');
  switch (status) {
    case 'NEW':
      return {
        descriptionKey: 'enrolment.next.NEW', ctaKey: 'enrolment.next.NEW.cta',
        actionType: 'status', prefill: { status: 'CONTACTED' },
        permission: 'ENROLMENT.MANAGE', roleKey: 'enrolment.role.reception',
      };
    case 'CONTACTED':
      return {
        descriptionKey: 'enrolment.next.CONTACTED', ctaKey: 'enrolment.next.CONTACTED.cta',
        actionType: 'status', prefill: { status: 'ASSESSMENT_BOOKED' },
        permission: 'ENROLMENT.MANAGE', roleKey: 'enrolment.role.reception',
      };
    case 'ASSESSMENT_BOOKED':
      return {
        descriptionKey: 'enrolment.next.ASSESSMENT_BOOKED', ctaKey: 'enrolment.next.ASSESSMENT_BOOKED.cta',
        actionType: 'convert',
        permission: 'ENROLMENT.MANAGE', roleKey: 'enrolment.role.reception',
      };
    case 'ENROLLED': {
      const childId = num(row, 'converted_child_id');
      return {
        descriptionKey: 'enrolment.next.ENROLLED', ctaKey: 'enrolment.next.ENROLLED.cta',
        actionType: null, link: childId ? ['/children', childId] : undefined,
        permission: 'CHILD.VIEW_ALL', roleKey: 'enrolment.role.any',
      };
    }
    default:
      return null;
  }
}

/** The action keys a deep link may name, and what each opens. Validated against the row's status. */
export const DEEP_LINK_ACTIONS: Readonly<Record<string, { actionType: 'status' | 'convert'; prefill?: Readonly<Record<string, string>> }>> = {
  'contact': { actionType: 'status', prefill: { status: 'CONTACTED' } },
  // Keep old links readable, but never preselect an unsupported booking.
  'book-assessment': { actionType: 'status' },
  'decide': { actionType: 'status' },
  'convert': { actionType: 'convert' },
};

/**
 * Whether a deep-linked action is legal for the row's status, by the same
 * table the dialog's select is built from. A pre-selected status that the
 * machine does not allow from here is dropped, not offered.
 */
export function deepLinkRequest(param: string | null, row: Row): { actionType: 'status' | 'convert'; prefill?: Readonly<Record<string, string>> } | null {
  if (!param) {
    return null;
  }
  const entry = DEEP_LINK_ACTIONS[param];
  if (!entry) {
    return null;
  }
  const legal = ENROLMENT_NEXT[text(row, 'status')] ?? [];
  if (entry.actionType === 'convert') {
    return ['CONTACTED', 'ASSESSMENT_BOOKED'].includes(text(row, 'status')) ? entry : null;
  }
  if (!legal.length) {
    return null;
  }
  const wanted = entry.prefill?.['status'];
  return wanted && !legal.includes(wanted) ? { actionType: 'status' } : entry;
}

export interface Flag {
  readonly key: string;
  readonly tone: 'warn' | 'info';
}

const HOUR = 60 * 60 * 1000;

/** Display flags. Thresholds are for the eye; nothing reads them back. */
export function flagsFor(row: Row, now: Date): readonly Flag[] {
  const out: Flag[] = [];
  const status = text(row, 'status');
  const submitted = text(row, 'submitted_at');
  const contacted = text(row, 'contacted_at');
  if (status === 'NEW' && olderThan(submitted, 24, now)) {
    out.push({ key: 'enrolment.flag.stale', tone: 'warn' });
  }
  if (status === 'CONTACTED' && olderThan(contacted || submitted, 72, now)) {
    out.push({ key: 'enrolment.flag.contactedNotBooked', tone: 'warn' });
  }
  if (status === 'ASSESSMENT_BOOKED' && !num(row, 'converted_child_id')) {
    out.push({ key: 'enrolment.flag.awaitingConversion', tone: 'info' });
  }
  if (num(row, 'sibling_applications') > 0) {
    out.push({ key: 'enrolment.flag.siblings', tone: 'info' });
  }
  if (status !== 'ENROLLED' && status !== 'REJECTED' && status !== 'DUPLICATE') {
    out.push({ key: 'enrolment.flag.noSpecialist', tone: 'info' });
  }
  return out;
}

export interface ActivityEvent {
  readonly at: string;
  readonly key: string;
  readonly detail?: string;
  /** A status badge beside the event, when it names one. */
  readonly status?: string;
}

/**
 * The application's history, from the timestamps the row carries and the
 * appointments of the child it became. No event is invented: a step the
 * schema does not stamp (who was assigned, when the assessment was run)
 * is simply not here.
 */
export function activityFor(row: Row, appointments: readonly Row[]): readonly ActivityEvent[] {
  const out: ActivityEvent[] = [];
  const status = text(row, 'status');
  const submitted = text(row, 'submitted_at');
  if (submitted) {
    out.push({ at: submitted, key: 'enrolment.event.created', detail: text(row, 'source_code') ? `source.${text(row, 'source_code')}` : undefined });
  }
  const contacted = text(row, 'contacted_at');
  if (contacted) {
    out.push({ at: contacted, key: 'enrolment.event.contacted', detail: text(row, 'contact_note_ar') || undefined, status: 'CONTACTED' });
  }
  const decided = text(row, 'decided_at');
  if (decided) {
    const key = status === 'ENROLLED' ? 'enrolment.event.converted'
      : status === 'REJECTED' ? 'enrolment.event.rejected'
      : status === 'DUPLICATE' ? 'enrolment.event.duplicate'
      : 'enrolment.event.decided';
    out.push({ at: decided, key, detail: text(row, 'decision_note_ar') || undefined, status });
  }
  for (const appointment of appointments) {
    const at = text(appointment, 'starts_at');
    if (at) {
      out.push({
        at, key: 'enrolment.event.appointment',
        detail: ref(appointment, 'service', 'name_ar') || undefined,
        status: text(appointment, 'status'),
      });
    }
  }
  return out.sort((a, b) => b.at.localeCompare(a.at));
}

// ---- readers ----

export function text(row: Row, key: string): string {
  const value = row[key];
  return value == null ? '' : String(value);
}

export function num(row: Row, key: string): number {
  const value = Number(row[key]);
  return Number.isFinite(value) ? value : 0;
}

export function ref(row: Row, object: string, key: string): string {
  const nested = row[object];
  return nested && typeof nested === 'object' ? text(nested as Row, key) : '';
}

function olderThan(iso: string, hours: number, now: Date): boolean {
  const at = Date.parse(iso);
  return Number.isFinite(at) && now.getTime() - at > hours * HOUR;
}
