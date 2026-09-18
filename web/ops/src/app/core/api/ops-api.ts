import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';

/**
 * The fourteen resources the service exposes with the same six verbs.
 *
 * The uniformity is the point: `POST /rooms` and `POST /therapists` differ
 * only in the noun, so one generic client covers all of them and every screen
 * gets create, edit, archive and restore without fourteen hand-written
 * clients drifting apart.
 *
 * Names are the service's, verbatim. Renaming them here would put a
 * translation table between the console and its own API, and the first thing
 * to rot would be the table.
 */
export type OpsResource =
  | 'services'
  | 'rooms'
  | 'cameras'
  | 'activity-library'
  | 'service-packages'
  | 'therapists'
  | 'working-hours'
  | 'caseload'
  | 'children'
  | 'guardians'
  | 'plans'
  | 'goals'
  | 'child-activities'
  | 'measurements'
  | 'nps-surveys'
  | 'site-contact'
  | 'site-faq'
  | 'site-texts'
  | 'site-team'
  | 'site-reviews'
  | 'site-services'
  | 'site-programs'
  | 'site-sections'
  | 'site-team-facts'
  | 'site-team-media'
  | 'site-team-specialties'
  | 'site-team-certificates';

/**
 * A row exactly as the service sends it: database column names, dates as
 * days ("2020-03-15"), instants as UTC, money as exact decimal strings.
 *
 * Deliberately untyped per resource. Fourteen interfaces mirroring fourteen
 * tables would be a second copy of the schema, and the schema is not this
 * layer's to restate - it changes in a migration and this file would not
 * notice. Screens narrow what they read; nothing here pretends to know.
 */
export type Row = Readonly<Record<string, unknown>>;

/**
 * One page of a list, with what the whole filter matches beside it.
 * `total` is the count for the filter, not for this page - a screen that
 * shows only `rows.length` cannot say "200 of 900" and so cannot tell
 * anyone that they are not seeing everything.
 */
/** What POST /site-media answers with: a path to store, not bytes to keep. */
export interface UploadResult {
  readonly path: string;
  readonly mime_type: string;
  readonly size_bytes: number;
}

export interface Page {
  readonly rows: readonly Row[];
  readonly total: number;
  readonly limit: number;
  readonly offset: number;
}

export interface ListQuery {
  /** Include archived rows. Only an administrator's token gets them. */
  readonly archived?: boolean;
  readonly q?: string;
  readonly page?: number;
  readonly [key: string]: string | number | boolean | undefined;
}

/**
 * Every call the ops console makes.
 *
 * Two things this client will not do:
 *
 *   It never sends `center_id`. The service derives it from the caller, and
 *   sending it is a 400 - correctly, because a client that can name a centre
 *   can try to name someone else's.
 *
 *   It never sends `active_flg`, and it has no `delete`. Archiving has its
 *   own path, and there is no hard delete anywhere in this system: a child's
 *   clinical record is not destroyed without a documented compliance action.
 */
@Injectable({ providedIn: 'root' })
export class OpsApi {
  chatContacts(): Observable<readonly Row[]> {
    return this.http.get<{rows:Row[]}>(this.base+'/chat-contacts').pipe(map(response=>response.rows));
  }

  private readonly http = inject(HttpClient);
  private readonly base = `${inject(HBH_CONFIG).apiBaseUrl}/api/v1`;

  /**
   * A list endpoint does not answer with an array. It answers with an object
   * carrying one named array - `{"children": [...]}`, `{"services": [...]}` -
   * so the shape stays extensible without breaking clients.
   *
   * The key is unwrapped by finding the one array in the object rather than
   * by a table of resource-to-key names. A table would be a second copy of
   * the service's naming convention, and the day a name is spelled with an
   * underscore where the path has a hyphen, the table is what would be wrong.
   */
  list(resource: OpsResource, query: ListQuery = {}): Observable<Page> {
    return this.http
      .get<Record<string, unknown>>(`${this.base}/${resource}`, {
        params: this.params(query),
      })
      .pipe(map((body) => {
        const rows = this.unwrap(body);
        return {
          rows,
          // `total` is what the whole filter matches, not what this page
          // holds. Without it a list of 200 on a centre with 900 children
          // looks complete, and the screen lies without ever erroring.
          total: typeof body?.['total'] === 'number' ? body['total'] as number : rows.length,
          limit: typeof body?.['limit'] === 'number' ? body['limit'] as number : rows.length,
          offset: typeof body?.['offset'] === 'number' ? body['offset'] as number : 0,
        };
      }));
  }

  get(resource: OpsResource, id: number): Observable<Row> {
    return this.http.get<Row>(`${this.base}/${resource}/${id}`);
  }

  create(resource: OpsResource, body: Row): Observable<Row> {
    return this.http.post<Row>(`${this.base}/${resource}`, body);
  }

  /**
   * Putting a child on a therapist's caseload, and taking them off (HBH-103).
   *
   * These exist BESIDE create/archive rather than through them because
   * `caseload` has two doors and only one of them carries the rules. The
   * generic POST /caseload inserts the row; hbh.assign_therapist behind this
   * pair returns the live row when the assignment already exists, moves the
   * primary (which nothing in the schema enforces - uix_caseload_live is
   * keyed on therapist, child and service, so two primaries for one service
   * is a state the generic door can reach and this one cannot), and reads
   * the permission before it reads the row.
   *
   * Two doors into one rule means the weaker one decides, so the screen goes
   * through this one and nothing in this console posts to the other.
   *
   * 200 and not 201 on purpose: the service answers "the state you asked for
   * holds", which is also true of a second click on the same button.
   */
  assignCaseload(
    childId: number, therapistId: number, serviceId: number, isPrimary: boolean,
  ): Observable<{ caseload_id: number }> {
    return this.http.post<{ caseload_id: number }>(
      `${this.base}/children/${childId}/caseload`,
      { therapist_id: therapistId, service_id: serviceId, is_primary: isPrimary });
  }

  /** `ended` says whether this call is what ended it, not whether it is ended. */
  endCaseload(childId: number, caseloadId: number): Observable<{ ended: boolean }> {
    return this.http.delete<{ ended: boolean }>(
      `${this.base}/children/${childId}/caseload/${caseloadId}`);
  }

  update(resource: OpsResource, id: number, body: Row): Observable<Row> {
    return this.http.patch<Row>(`${this.base}/${resource}/${id}`, body);
  }

  /**
   * Soft archive. The service answers 204 and the row stays, with active_flg
   * false and a stamp. `restore` is the other half, and its existence is why
   * this is safe to offer from a screen.
   */
  archive(resource: OpsResource, id: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/${resource}/${id}`);
  }

  restore(resource: OpsResource, id: number): Observable<void> {
    return this.http.post<void>(`${this.base}/${resource}/${id}/restore`, {});
  }

  /**
   * Uploads one photograph or introduction film for the public site.
   *
   * The answer carries the PATH to store, never the bytes - the file is on
   * the centre's own disk and served from the same origin as the page, and
   * the database holds a path exactly as it always has for photo_path.
   *
   * No Content-Type is set: the browser must write the multipart boundary
   * itself, and setting the header by hand omits it and produces a body the
   * service cannot parse.
   */
  upload(file: File): Observable<UploadResult> {
    const form = new FormData();
    form.append('file', file);
    return this.http.post<UploadResult>(`${this.base}/site-media`, form);
  }

  /**
   * Pulls the one array out of a list response. An empty object or a shape
   * with no array yields an empty list rather than throwing: a screen that
   * says "nothing here" is recoverable, and one that crashes is not.
   */
  private unwrap(body: Record<string, unknown>): readonly Row[] {
    for (const value of Object.values(body ?? {})) {
      if (Array.isArray(value)) {
        return value as readonly Row[];
      }
    }
    return [];
  }

  private params(query: ListQuery): HttpParams {
    let params = new HttpParams();
    for (const [key, value] of Object.entries(query)) {
      if (value !== undefined && value !== null && value !== '') {
        params = params.set(key, String(value));
      }
    }
    return params;
  }
}
