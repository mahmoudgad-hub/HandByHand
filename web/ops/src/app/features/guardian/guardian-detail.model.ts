import { Row } from '../../core/api/ops-api';

/**
 * The guardian page's derived facts, as pure functions over rows the
 * console already reads. No rule lives here: which applications are the
 * family's is decided by the two keys the schema itself uses (the converted
 * guardian id, and the canonical mobile both tables store), and the
 * timeline is the rows' own stamps.
 */

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

/**
 * The applications that belong to this guardian, out of a page of the
 * queue. Two keys, either matches: the id written at conversion, or the
 * mobile the family typed - both canonicalised by the same trigger, so the
 * strings compare exactly.
 */
export function applicationsOf(guardian: Row, applications: readonly Row[]): readonly Row[] {
  const id = num(guardian, 'guardian_id');
  const mobile = text(guardian, 'mobile');
  return applications.filter((row) =>
    (id && num(row, 'converted_guardian_id') === id)
    || (mobile !== '' && text(row, 'parent_mobile') === mobile));
}

/** The family's requests, out of a page: the request names its guardian. */
export function requestsOf(guardianId: number, requests: readonly Row[]): readonly Row[] {
  return requests.filter((row) => Number((row['guardian'] as Row | undefined)?.['guardian_id']) === guardianId);
}

const OPEN_APPLICATION = new Set(['NEW', 'CONTACTED', 'ASSESSMENT_BOOKED']);

export function openApplications(applications: readonly Row[]): readonly Row[] {
  return applications.filter((row) => OPEN_APPLICATION.has(text(row, 'status')));
}

export interface ChildAppointment {
  readonly childId: number;
  readonly childName: string;
  readonly row: Row;
}

const LIVE = new Set(['BOOKED', 'CONFIRMED', 'CHECKED_IN']);

/** The soonest live appointment across the family's children, or null. */
export function nextAppointment(all: readonly ChildAppointment[], nowIso: string): ChildAppointment | null {
  return [...all]
    .filter((item) => text(item.row, 'starts_at') >= nowIso && LIVE.has(text(item.row, 'status')))
    .sort((a, b) => text(a.row, 'starts_at').localeCompare(text(b.row, 'starts_at')))[0] ?? null;
}

export interface ActivityEvent {
  readonly at: string;
  readonly key: string;
  readonly detail?: string;
  readonly link?: readonly (string | number)[];
}

/** The family's history from the stamps the rows carry. Nothing invented. */
export function activityFor(
  guardian: Row, children: readonly Row[], applications: readonly Row[], requests: readonly Row[],
): readonly ActivityEvent[] {
  const out: ActivityEvent[] = [];
  const created = text(guardian, 'created_at');
  if (created) {
    out.push({ at: created, key: 'guardian.event.created' });
  }
  for (const child of children) {
    const at = text(child, 'created_at');
    if (at) {
      out.push({ at, key: 'guardian.event.childCreated', detail: text(child, 'full_name_ar'), link: ['/children', num(child, 'child_id')] });
    }
  }
  for (const app of applications) {
    const id = num(app, 'application_id');
    const link = ['/enrolments', id];
    const submitted = text(app, 'submitted_at');
    if (submitted) {
      out.push({ at: submitted, key: 'guardian.event.applied', detail: text(app, 'child_name_ar'), link });
    }
    const contacted = text(app, 'contacted_at');
    if (contacted) {
      out.push({ at: contacted, key: 'guardian.event.contacted', detail: text(app, 'child_name_ar'), link });
    }
    const decided = text(app, 'decided_at');
    if (decided) {
      const status = text(app, 'status');
      out.push({
        at: decided,
        key: status === 'ENROLLED' ? 'guardian.event.converted' : 'guardian.event.decided',
        detail: text(app, 'child_name_ar'), link,
      });
    }
  }
  for (const request of requests) {
    const createdAt = text(request, 'created_at');
    if (createdAt) {
      out.push({ at: createdAt, key: 'guardian.event.requested', detail: `kind.request.${text(request, 'kind_code')}`, link: ['/requests'] });
    }
    const decidedAt = text(request, 'decided_at');
    if (decidedAt) {
      out.push({ at: decidedAt, key: 'guardian.event.requestDecided', detail: `status.request.${text(request, 'status')}`, link: ['/requests'] });
    }
  }
  return out.sort((a, b) => b.at.localeCompare(a.at));
}
