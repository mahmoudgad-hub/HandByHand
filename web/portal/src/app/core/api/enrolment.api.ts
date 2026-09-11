import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';

/**
 * An application from a family the centre has never met.
 *
 * This is the ONLY call in the portal that carries no token, and the only one
 * that could not: the family has no account yet, which is the whole reason
 * the form exists. Everything else in this app goes through the interceptor
 * and would be refused without one.
 *
 * What that costs, and why the screen is written the way it is:
 *
 *   The centre must be named, because the server cannot derive it from a
 *   caller who has not identified themselves. It comes from config, not from
 *   the address bar - a code in a query string is a code somebody edits.
 *
 *   Nothing comes back but a reference number. There is no read path for an
 *   anonymous caller at all, so this endpoint cannot be turned into a way to
 *   ask whether a mobile number is already known to the centre.
 *
 *   A refusal says almost nothing, on purpose. See `submit` below.
 */
export interface EnrolmentApplication {
  readonly parent_name_ar: string;
  readonly parent_mobile: string;
  readonly parent_email?: string;
  readonly relationship_code: string;
  readonly address_ar?: string;
  readonly preferred_contact_time?: string;
  readonly child_name_ar: string;
  /** A day, "2021-05-20" - not an instant. A birth date has no clock. */
  readonly child_birth_date: string;
  readonly child_gender: string;
  readonly main_concern_ar?: string;
  readonly previous_therapy_ar?: string;
}

@Injectable({ providedIn: 'root' })
export class EnrolmentApi {
  private readonly http = inject(HttpClient);
  private readonly config = inject(HBH_CONFIG);

  /**
   * Sends the application. The answer is a reference number and nothing else.
   *
   * The refusals are deliberately uninformative and the screen must not try
   * to improve on them. The service answers 429 for one rate limit and 400
   * for everything else, without saying which - because "you have tried too
   * many times with this mobile" would tell a stranger that the number they
   * typed is known to this centre, and that is a fact about a family. The
   * centre sees the real reason in its own audit log.
   */
  submit(application: EnrolmentApplication): Observable<{ application_no: string }> {
    return this.http.post<{ application_no: string }>(
      `${this.config.apiBaseUrl}/api/v1/enrolments`,
      { ...application, center_code: this.config.centerCode },
    );
  }
}
