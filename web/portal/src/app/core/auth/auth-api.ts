import { Observable } from 'rxjs';

import { Utc } from '../models/portal.models';

/**
 * What asking for a code actually produced.
 *
 * THREE OUTCOMES, NOT A BOOLEAN. This was `registered: boolean`, which was
 * enough while the service answered two ways. It now answers three, and a
 * family whose enrolment application is still on the centre's desk was
 * falling into "registered" - so the portal sent them to the six code boxes
 * to wait for an SMS nobody was going to send. The same dead end the
 * NOT_REGISTERED work removed, reached by a different door.
 *
 *   SENT               a code is on its way
 *   NOT_REGISTERED     this number is on no child's file
 *   ENROLMENT_PENDING  they applied; the centre has not decided yet
 *
 * A REJECTED application is deliberately NOT one of these - the service
 * answers NOT_REGISTERED for it, because "the centre looked at you and said
 * no" is not something a sign-in screen tells whoever types a number. Adding
 * a fourth case here would reopen exactly what that hides.
 */
export type OtpOutcome = 'SENT' | 'NOT_REGISTERED' | 'ENROLMENT_PENDING';

/**
 * The answer to asking for a code.
 *
 * Note what is absent: no challenge id, and no echo of the number. Verifying
 * takes the mobile again, and the portal keeps it in memory for that one
 * purpose - it is never stored and never sent anywhere else.
 */
export interface OtpChallenge {
  readonly expiresInSeconds: number;
  readonly resendInSeconds: number;

  /**
   * Whether the number is on a child's file.
   *
   * This used to be unanswerable on purpose - the service replied the same
   * way to every well-formed number so nobody could ask it "does this family
   * attend your children's centre?". The owner changed that on 2026-09-05:
   * the old behaviour sent a parent with no file to a code screen to wait for
   * an SMS that would never arrive, and said nothing about why. The reasoning
   * on both sides is written out in full at `otpRequestOut` in
   * api/internal/http/auth_handlers.go; this field is that decision arriving.
   *
   * False is not an error. The request was well formed and the service
   * answered it - there is simply nobody to send a code to.
   */
  readonly outcome: OtpOutcome;

  /** Present only while the service is running with OTP echo, outside production. */
  readonly devCode?: string;
}

export interface AuthSession {
  readonly token: string;
  readonly expiresAt: Utc;
}

/**
 * Why a code was refused. These are the service's own codes, passed through
 * unchanged so the screen can say something useful; the Arabic wording for
 * each lives in the translation bundle.
 */
export type OtpFailure =
  | 'WRONG_CODE'
  | 'EXPIRED'
  | 'NO_PENDING_CODE'
  | 'TOO_MANY_ATTEMPTS'
  | 'USER_LOCKED'
  | 'RATE_LIMITED'
  | 'UNKNOWN';

export interface OtpRefusal {
  readonly failure: OtpFailure;
  /** How many guesses remain, when the service chose to say. */
  readonly attemptsLeft: number | null;
}

/**
 * Sign-in is a one-time code to a phone already on the child's file. There is
 * no password anywhere in this portal, so there is no password to leak.
 *
 * Both calls are POSTs with a body. A phone number or a code in a query
 * string would land in access logs and browser history, and neither belongs
 * there.
 */
export abstract class AuthApi {
  abstract requestOtp(mobile: string): Observable<OtpChallenge>;

  abstract verifyOtp(mobile: string, code: string): Observable<AuthSession>;

  /** Ends the session on the server, not only in this tab. */
  abstract logout(): Observable<void>;
}
