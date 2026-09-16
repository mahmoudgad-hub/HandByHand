import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { Row } from './ops-api';

/**
 * Everything one child's file is made of.
 *
 * These are the child-scoped reads - the shape the parent portal was built
 * on - and they are exactly right here too: this screen IS about one child,
 * so indexing by the child is not a workaround.
 *
 * WHAT THE STATIC DESIGN ASKS FOR AND THIS CANNOT ANSWER:
 *
 *   The guardian and their phone number. There is no way to ask "who are
 *   this child's guardians". `GET /guardians` is the generic CRUD list and
 *   ignores a `child_id` parameter - verified against the running service,
 *   it returned every guardian in the centre.
 *
 *   The primary therapist. Same reason: caseload is a CRUD list with no
 *   filter, so asking for it would mean fetching every caseload row in the
 *   centre and picking through them - and on a paged list the child might
 *   simply not be on the page, which is the kind of screen that shows
 *   nothing and looks like an answer.
 *
 *   The diagnosis. There is no such column on hbh.children at all.
 *
 * All three are requested. The screen leaves the space out rather than
 * filling it with a lookup that would be wrong on page two.
 */
export interface Balance {
  readonly currency_code: string;
  readonly open_invoice_count: number;
  readonly outstanding_amt: string;
  readonly invoiced_amt: string;
  readonly paid_amt: string;
}

@Injectable({ providedIn: 'root' })
export class ChildApi {
  private readonly http = inject(HttpClient);
  private readonly base = `${inject(HBH_CONFIG).apiBaseUrl}/api/v1`;

  child(childId: number): Observable<Row> {
    return this.http.get<Row>(`${this.base}/children/${childId}`);
  }

  /**
   * This child's guardians, in the service's TOTAL order:
   * is_primary_flg, then created_at, then guardian_id.
   *
   * Never the generic /guardians list filtered here - that endpoint ignores
   * a child filter and returns every guardian in the centre, so choosing from
   * it would put another family's telephone number on a child's emergency
   * card. And the order is the service's rather than this client's, because a
   * printed card must give the same number every time it is run: a partial
   * order lets the engine choose between equals.
   */
  guardians(childId: number): Observable<readonly Row[]> {
    return this.http
      .get<Record<string, unknown>>(`${this.base}/children/${childId}/guardians`)
      .pipe(map((body) => {
        for (const value of Object.values(body ?? {})) {
          if (Array.isArray(value)) {
            return value as readonly Row[];
          }
        }
        return [];
      }));
  }

  balance(childId: number): Observable<Balance> {
    return this.http.get<Balance>(`${this.base}/children/${childId}/balance`);
  }

  /**
   * Record a consent for a guardian, about this child.
   *
   * The schema will not let live viewing be switched on without one - see
   * trg_live_flag_needs_consent - and until this call existed the only way to
   * satisfy that rule was to write to the database by hand. A control that can
   * only be operated at the console is a control that gets bypassed there.
   *
   * hbh.grant_consent decides who may (GUARDIAN.MANAGE), raises the live-view
   * flag itself, and files a consent_events row. Nothing of that is repeated
   * here.
   */
  grantConsent(guardianId: number, consentType: string, childId: number): Observable<unknown> {
    return this.http.post(`${this.base}/guardians/${guardianId}/consent`,
      { consent_type: consentType, child_id: childId });
  }

  /**
   * Take it back. The database drops the permission that leaned on it in the
   * same statement - a withdrawal that left the flag standing would be a
   * withdrawal in name only.
   */
  withdrawConsent(guardianId: number, consentType: string, childId: number): Observable<unknown> {
    return this.http.request('delete', `${this.base}/guardians/${guardianId}/consent`,
      { body: { consent_type: consentType, child_id: childId } });
  }

  /**
   * Send one clinical note to the family.
   *
   * The service decides whether the caller may: hbh.publish_session_note wants
   * NOTE.PUBLISH and refuses anybody else, so this carries no check of its own.
   * A screen that tested the permission itself would be a second copy of that
   * rule, and the weaker copy would be this one.
   */
  publishNote(noteId: number): Observable<void> {
    return this.http.post<void>(`${this.base}/notes/${noteId}/publish`, {});
  }

  /**
   * Report authoring.
   *
   * Three calls and no rules. Who may write one, whose child it may be
   * about, whether a draft may still change and whether it carries enough
   * to publish are all answered by hbh.create_report, hbh.update_report and
   * hbh.publish_report - see migration 0088. A check here would be a second
   * copy, and C1 is the reminder of which copy ends up deciding.
   *
   * Note what createReport does NOT send: no centre, no author, no report
   * number, no status. The function derives all four. There is nothing on
   * this table to impersonate - authorship is created_by, from the session.
   */
  createReport(input: {
    child_id: number; title_ar: string; period_start: string; period_end: string;
    plan_id?: number | null; summary_ar?: string | null;
  }): Observable<{ report_id: number; version: string }> {
    return this.http.post<{ report_id: number; version: string }>(`${this.base}/reports`, input);
  }

  /**
   * Edits a draft. Any field left out is left alone.
   *
   * expected_version is the version this editor opened, sent back
   * exactly as the service gave it. A colleague's save in between is
   * refused as REPORT_CHANGED rather than overwritten (migration 0141),
   * and the answer carries the new version for the next save.
   */
  updateReport(reportId: number, patch: {
    expected_version: string | null;
    title_ar?: string; summary_ar?: string;
    period_start?: string; period_end?: string; plan_id?: number | null;
  }): Observable<{ version: string }> {
    return this.http.patch<{ version: string }>(`${this.base}/reports/${reportId}`, patch);
  }

  report(reportId: number): Observable<Row> {
    return this.http.get<Row>(`${this.base}/reports/${reportId}`);
  }

  publishReport(reportId: number): Observable<void> {
    return this.http.post<void>(`${this.base}/reports/${reportId}/publish`, {});
  }

  /**
   * One of the child's lists. The response wraps its rows in a named key and
   * the key is found as the one array in the object - the same unwrap the
   * other two clients use, and for the same reason.
   */
  list(childId: number, part: ChildPart): Observable<readonly Row[]> {
    return this.http
      .get<Record<string, unknown>>(`${this.base}/children/${childId}/${part}`)
      .pipe(map((body) => {
        for (const value of Object.values(body ?? {})) {
          if (Array.isArray(value)) {
            return value as readonly Row[];
          }
        }
        return [];
      }));
  }
}

export type ChildPart =
  | 'appointments'
  | 'sessions'
  | 'activity-log'
  | 'guardians'
  | 'plans'
  | 'reports'
  | 'notes'
  | 'invoices'
  | 'packages';
