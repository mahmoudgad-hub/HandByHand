import { Injectable } from '@angular/core';
import { Observable, delay, of, throwError } from 'rxjs';

import { AuthApi, AuthSession, OtpChallenge } from './auth-api';

/**
 * Sign-in without a server. It accepts any correctly shaped code so the flow
 * can be walked end to end, and it refuses two specific codes so both failure
 * paths on screen are exercised code and not branches nobody has ever run.
 *
 * It proves nothing about identity. The real check is hbh.request_otp and
 * hbh.verify_otp behind the Go service, and this file is deleted the day the
 * portal is pointed at it.
 */
@Injectable()
export class FixtureAuthApi extends AuthApi {
  private readonly latencyMs = 320;

  /** Rejected as a wrong code, so the retry path is reachable. */
  private readonly wrongCode = '000000';
  /** Rejected as a locked account, so the dead-end path is reachable. */
  private readonly lockedCode = '111111';

  override requestOtp(): Observable<OtpChallenge> {
    return of<OtpChallenge>({
      expiresInSeconds: 15 * 60,
      resendInSeconds: 47,
      outcome: 'SENT' as const,
    }).pipe(delay(this.latencyMs));
  }

  override verifyOtp(mobile: string, code: string): Observable<AuthSession> {
    // Shaped exactly like the service's refusals, down to the error body, so
    // the screen's mapping is real code rather than a branch that only runs
    // in production.
    if (code === this.wrongCode) {
      return throwError(() => ({
        status: 401,
        error: { error: { code: 'WRONG_CODE', fields: { attempts_left: 3 } } },
      })).pipe(delay(this.latencyMs));
    }
    if (code === this.lockedCode) {
      return throwError(() => ({
        status: 423,
        error: { error: { code: 'TOO_MANY_ATTEMPTS' } },
      })).pipe(delay(this.latencyMs));
    }
    return of<AuthSession>({
      token: 'fixture-session-token',
      expiresAt: new Date(Date.now() + 8 * 60 * 60 * 1000).toISOString(),
    }).pipe(delay(this.latencyMs));
  }

  override logout(): Observable<void> {
    return of(undefined as void).pipe(delay(80));
  }
}
