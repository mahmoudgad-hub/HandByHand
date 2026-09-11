import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { AuthApi, AuthSession, OtpChallenge } from './auth-api';

/** POST /api/v1/auth/otp/request, verbatim. */
interface OtpRequestResponse {
  /** "SENT", or "NOT_REGISTERED" when the number is on no child's file. */
  readonly status: string;
  readonly expires_in_seconds: number;
  readonly resend_in_seconds: number;
  readonly dev_code?: string;
}

/** POST /api/v1/auth/otp/verify, verbatim. */
interface OtpVerifyResponse {
  readonly token_type: string;
  readonly token: string;
  readonly expires_at: string;
}

/**
 * The wire shapes above are snake_case because that is what the service sends.
 * They are converted here, once, so nothing above this file has to know which
 * casing the transport happens to use.
 */
@Injectable()
export class HttpAuthApi extends AuthApi {
  private readonly http = inject(HttpClient);
  private readonly base = `${inject(HBH_CONFIG).apiBaseUrl}/api/v1/auth`;

  override requestOtp(mobile: string): Observable<OtpChallenge> {
    return this.http.post<OtpRequestResponse>(`${this.base}/otp/request`, { mobile })
      .pipe(map((body) => ({
        expiresInSeconds: body.expires_in_seconds,
        resendInSeconds: body.resend_in_seconds,
        // Named cases, then SENT for everything else - and that direction is
        // deliberate. Written the other way round, as a list of what counts
        // as sent, a status the service adds tomorrow would fall through to a
        // refusal and turn working sign-ins away. A new status reaching this
        // portal shows the code screen, which is what it did before; a screen
        // that says "check your messages" when it should have said something
        // better is a smaller failure than one that says "you do not exist".
        outcome: body.status === 'NOT_REGISTERED' ? 'NOT_REGISTERED'
          : body.status === 'ENROLMENT_PENDING' ? 'ENROLMENT_PENDING'
            : 'SENT',
        devCode: body.dev_code,
      })));
  }

  override verifyOtp(mobile: string, code: string): Observable<AuthSession> {
    return this.http.post<OtpVerifyResponse>(`${this.base}/otp/verify`, { mobile, code })
      .pipe(map((body) => ({
        token: body.token,
        expiresAt: body.expires_at,
      })));
  }

  override logout(): Observable<void> {
    return this.http.post<void>(`${this.base}/logout`, {});
  }
}
