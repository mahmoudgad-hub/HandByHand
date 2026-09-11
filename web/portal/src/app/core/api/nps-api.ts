import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';

/**
 * The satisfaction question, if there is one right now.
 *
 * `null` IS A NORMAL ANSWER, not a 404. Having nothing to ask is the usual
 * case - a survey has a cooldown and a trigger - and a screen that treated it
 * as an error would record a failure on every page load.
 *
 * The question TEXT comes from the database rather than from a translation
 * file, and that is not an exception to the rule that keeps Arabic out of the
 * code: an error code is a fixed vocabulary this app words, while the
 * question is content the CENTRE writes and changes without a release. A
 * question compiled into Angular cannot be changed by whoever owns it.
 */
export interface DueSurvey {
  readonly survey_id: number;
  readonly question_ar: string;
  readonly followup_question_ar?: string;
  readonly context_kind?: string;
  readonly context_id?: number;
}

@Injectable({ providedIn: 'root' })
export class NpsApi {
  private readonly http = inject(HttpClient);
  private readonly base = `${inject(HBH_CONFIG).apiBaseUrl}/api/v1/nps`;

  due(): Observable<{ survey: DueSurvey | null }> {
    return this.http.get<{ survey: DueSurvey | null }>(`${this.base}/due`);
  }

  /**
   * 0..10. Outside that the service refuses with HB093.
   *
   * THE CONTEXT IS SENT ONLY AS A COMPLETE PAIR. `nps_responses` carries
   * `CHECK ((context_kind IS NULL) = (context_id IS NULL))` - a kind with no
   * id is not a partial answer to the database, it is an illegal row - and
   * `/nps/due` hands out exactly that: the seeded survey comes back with
   * `context_kind: "SESSION_COMPLETED"` and no id at all. Echoing what was
   * given back made every single answer fail with a 400, on a dialog that
   * closes either way, so the parent saw a question, answered it, watched it
   * accept, and nothing was ever written.
   *
   * Dropping the half pair stores the answer with no context, which is legal
   * and true: this client was not told which session it was about. The
   * service side of it is reported separately - the fix there is for `due` to
   * return both halves or neither.
   */
  respond(
    surveyId: number, score: number, commentAr = '',
    contextKind?: string, contextId?: number,
  ): Observable<void> {
    const hasContext = !!contextKind && contextId !== undefined && contextId !== null;
    return this.http.post<void>(`${this.base}/${surveyId}/response`, {
      score,
      comment_ar: commentAr,
      context_kind: hasContext ? contextKind : undefined,
      context_id: hasContext ? contextId : undefined,
    });
  }

  /**
   * Not a nicety. The cooldown starts when SOMETHING is recorded, and a
   * window that was closed records nothing - so a client that shows the
   * question and ignores the dismissal turns one question into a question on
   * every screen, forever.
   */
  skip(surveyId: number): Observable<void> {
    return this.http.post<void>(`${this.base}/${surveyId}/skip`, {});
  }
}
