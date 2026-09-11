import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { Row } from './ops-api';

/**
 * The therapist's own profile: what they write about themselves, and the
 * consent that lets it out of the building.
 *
 * WHY THESE ARE NOT THE GENERIC CRUD RESOURCE. The profile columns sit on
 * hbh.therapists, but editing them through /therapists/{id} would need
 * STAFF.MANAGE - so a therapist could not write their own biography - and
 * granting them that would hand over `status`, `user_id` and `branch_id` too,
 * because RLS grants ROWS and not COLUMNS. The columns therefore have their
 * own function, which names them.
 *
 * THE CONSENT IS THE POINT OF THE WHOLE FILE. This profile goes out to
 * families, about a named person, so publishing needs that person's own
 * recorded agreement. An administrator holding every permission in the schema
 * is still refused NOT_YOUR_CONSENT when they try to give it on someone
 * else's behalf - which is what makes the record mean anything.
 */
export interface ProfileEdit {
  readonly bio_ar?: string;
  readonly practice_since_year?: number;
  readonly age_from_mon?: number;
  readonly age_to_mon?: number;
  /**
   * Fields to EMPTY, named explicitly.
   *
   * Absent and empty are different requests: a field left out keeps its
   * value. Without this, a screen that edits only the biography would wipe
   * an age range it never showed - the classic partial-update defect, and
   * the reason the service made the distinction rather than guessing.
   */
  readonly clear?: readonly string[];
}

@Injectable({ providedIn: 'root' })
export class TherapistProfileApi {
  private readonly http = inject(HttpClient);
  private readonly base = `${inject(HBH_CONFIG).apiBaseUrl}/api/v1`;

  patchProfile(therapistId: number, edit: ProfileEdit): Observable<void> {
    return this.http.patch<void>(`${this.base}/therapists/${therapistId}/profile`, edit);
  }

  // ---- languages ----

  languages(therapistId: number): Observable<readonly Row[]> {
    return this.list(`${this.base}/therapists/${therapistId}/languages`);
  }

  /**
   * Adds or updates one language. PUT, not POST, because the pair
   * (therapist, language) IS the key - sending the same language again is an
   * edit and not a duplicate.
   *
   * At most one native language, enforced by a partial index: a second one is
   * refused with 400 rather than quietly accepted.
   *
   * `runs_sessions` is separate from the level on purpose. "Reads English"
   * and "can run a whole session in English" are different facts, and in a
   * speech centre the second is a clinical matching criterion.
   */
  putLanguage(
    therapistId: number, langCode: string, levelCode: string,
    isNative: boolean, runsSessions: boolean,
  ): Observable<void> {
    return this.http.put<void>(`${this.base}/therapists/${therapistId}/languages`, {
      lang_code: langCode,
      level_code: levelCode,
      is_native: isNative,
      runs_sessions: runsSessions,
    });
  }

  removeLanguage(therapistId: number, langCode: string): Observable<void> {
    return this.http.delete<void>(
      `${this.base}/therapists/${therapistId}/languages/${langCode}`);
  }

  // ---- certificates ----

  certificates(therapistId: number): Observable<readonly Row[]> {
    return this.list(`${this.base}/therapists/${therapistId}/certificates`);
  }

  addCertificate(therapistId: number, body: Row): Observable<{ certificate_id: number }> {
    return this.http.post<{ certificate_id: number }>(
      `${this.base}/therapists/${therapistId}/certificates`, body);
  }

  /**
   * Publishes or unpublishes the SCAN of a certificate - and nothing else.
   *
   * Its own endpoint rather than a field on the general edit, and that is
   * load-bearing: an Egyptian certificate scan usually carries a national
   * identity number, a date of birth and a signature. If this rode along with
   * a general save, somebody correcting a spelling would publish an identity
   * document without reading the line beside it.
   *
   * Publishing a scan that does not exist is refused by a constraint, so the
   * flag cannot sit true on an empty row waiting to mean something the day a
   * file is uploaded.
   */
  setImagePublic(certificateId: number, isPublic: boolean): Observable<void> {
    return this.http.patch<void>(
      `${this.base}/certificates/${certificateId}/image`, { is_image_public: isPublic });
  }

  // ---- consent and publication ----

  /**
   * The therapist agreeing that their profile may be published.
   *
   * Refused with 403 NOT_YOUR_CONSENT for anybody else - including an
   * administrator who holds every permission there is. That refusal is the
   * feature: a consent somebody else can give is not a consent.
   */
  giveConsent(therapistId: number): Observable<void> {
    return this.http.post<void>(`${this.base}/therapists/${therapistId}/consent`, {});
  }

  /**
   * Withdrawing it. The profile comes DOWN in the same statement - a consent
   * that is withdrawn while the page stays published would be no consent at
   * all - and republishing needs a fresh one.
   */
  withdrawConsent(therapistId: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/therapists/${therapistId}/consent`);
  }

  /**
   * Publishing. Refused with 409 CONSENT_REQUIRED when the therapist has not
   * agreed - NOT 403, because the caller usually does hold the permission and
   * what is missing is somebody else's decision. A screen that said "you do
   * not have permission" would send the manager to the wrong person.
   */
  publish(therapistId: number): Observable<void> {
    return this.http.post<void>(`${this.base}/therapists/${therapistId}/publish`, {});
  }

  private list(url: string): Observable<readonly Row[]> {
    return this.http.get<Record<string, unknown>>(url).pipe(map((body) => {
      for (const value of Object.values(body ?? {})) {
        if (Array.isArray(value)) {
          return value as readonly Row[];
        }
      }
      return [];
    }));
  }
}
