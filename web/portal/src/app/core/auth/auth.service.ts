import { Injectable, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { UserAvatars } from '@hbh/shared/ui/user-avatar';
import { Observable, tap } from 'rxjs';

import { AuthApi, AuthSession, OtpChallenge, OtpFailure, OtpRefusal } from './auth-api';

const TOKEN_KEY = 'hbh.portal.session';

/**
 * Holds the session for this tab and nothing else.
 *
 * sessionStorage, not localStorage: a guardian's session should not outlive
 * the tab on a shared or family device. The token is opaque to the portal -
 * it is attached to requests and never parsed, because every claim inside it
 * is the server's business and trusting one here would be a check that a
 * client could edit.
 *
 * The mobile number lives in a signal for as long as a code is outstanding,
 * because verifying takes it again. It is never written to storage, never put
 * in a URL, and cleared the moment sign-in ends either way.
 *
 * It fails closed. No token means no identity, which means the guard sends
 * the visitor to sign-in - never a partly rendered screen.
 */
@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly api = inject(AuthApi);
  private readonly router = inject(Router);
  private readonly avatars = inject(UserAvatars);

  private readonly session = signal<AuthSession | null>(this.restore());
  private readonly challenge = signal<OtpChallenge | null>(null);
  private readonly mobile = signal<string | null>(null);

  readonly isSignedIn = computed(() => this.session() !== null);
  readonly pendingChallenge = this.challenge.asReadonly();

  /**
   * The number with its middle hidden, for the "we sent it to..." line.
   * Masked here rather than by the server, which deliberately echoes nothing
   * back - so the digits never leave this device a second time.
   */
  readonly maskedMobile = computed(() => {
    const current = this.mobile();
    if (!current || current.length < 4) {
      return '';
    }
    const tail = current.slice(-4);
    const head = current.slice(0, 3);
    return `${head} **** ${tail}`;
  });

  get token(): string | null {
    return this.session()?.token ?? null;
  }

  /**
   * The last code the service echoed, with the moment it stops being valid.
   *
   * Development only, and it exists to close a dead end. Asking again for a
   * number that already has a code outstanding answers SENT with NO
   * `dev_code` - correctly, because no new code was issued and the old one is
   * still the live one. But the screen draws its shortcut from that field, so
   * the button vanished and the only working code was one nobody had seen.
   * Pressing "resend", or going back and returning, was enough to reach it.
   *
   * Kept in a plain field rather than a signal: nothing renders from it
   * directly - the screen reads the challenge, which is where it is merged
   * back in.
   */
  private echoed: { mobile: string; code: string; until: number } | null = null;

  requestOtp(mobile: string): Observable<OtpChallenge> {
    return this.api.requestOtp(mobile).pipe(
      tap((challenge) => {
        // A number with no file leaves NOTHING outstanding. Storing a
        // challenge for it would let /otp be reached - by the back button, or
        // by typing the address - and put six boxes in front of somebody with
        // no code coming, which is the dead end this change exists to remove.
        // The sign-in screen reads `outcome` off the returned value and says
        // what to do instead. An application still under review leaves the
        // same nothing outstanding: there is no code coming for it either.
        if (challenge.outcome !== 'SENT') {
          this.challenge.set(null);
          this.mobile.set(null);
          return;
        }

        const now = Date.now();
        if (challenge.devCode) {
          this.echoed = {
            mobile,
            code: challenge.devCode,
            until: now + challenge.expiresInSeconds * 1000,
          };
        }
        // The guard is the expiry, and it is what makes carrying the code
        // over honest. An absent `dev_code` does not only mean "the old one
        // still stands" - the request may have been refused outright, for a
        // number the centre does not know or for one that is locked. What
        // cannot be argued with is the clock: past its own lifetime the code
        // is dead whatever the reason, and showing it then would send
        // somebody to type a code that cannot work.
        const live = this.echoed?.mobile === mobile && this.echoed.until > now
          ? this.echoed.code
          : undefined;
        this.challenge.set(live ? { ...challenge, devCode: live } : challenge);
        this.mobile.set(mobile);
      }),
    );
  }

  verifyOtp(code: string): Observable<AuthSession> {
    const mobile = this.mobile();
    if (!mobile) {
      throw new Error('verifyOtp called with no code outstanding');
    }
    return this.api.verifyOtp(mobile, code).pipe(
      tap((session) => this.adopt(session)),
    );
  }

  /** Drops an outstanding code, so the sign-in screen starts clean. */
  abandonChallenge(): void {
    this.challenge.set(null);
    this.mobile.set(null);
    // `echoed` deliberately survives this. Both "change the number" AND
    // "resend the code" route through here, and the resend case is the very
    // one the echo exists for: clearing it would drop the only copy of a code
    // the service will not send twice, which is the dead end again. What
    // stops it surfacing against a different number is the mobile match in
    // requestOtp, not clearing it here.
  }

  /**
   * Clears the tab, tells the server, then routes to sign-in. Local state is
   * cleared first on purpose: if the network call fails, this device is still
   * signed out.
   */
  signOut(): void {
    this.avatars.reset(null);
    this.session.set(null);
    this.abandonChallenge();
    sessionStorage.removeItem(TOKEN_KEY);
    this.api.logout().subscribe({
      error: () => undefined,
      complete: () => undefined,
    });
    void this.router.navigate(['/login']);
  }

  /** Called by the interceptor when the server rejects the token. */
  sessionExpired(): void {
    this.avatars.reset(null);
    this.session.set(null);
    sessionStorage.removeItem(TOKEN_KEY);
    void this.router.navigate(['/login'], { queryParams: { reason: 'expired' } });
  }

  /**
   * Reads the service's refusal into the two things a screen needs to know:
   * which message to show, and whether there are guesses left.
   *
   * It reads codes, never sentences. The service answers with a code exactly
   * so that the Arabic wording can live in one place - the translation bundle
   * - and change without a release on either side.
   */
  readRefusal(error: unknown): OtpRefusal {
    const shaped = error as {
      status?: number;
      error?: { error?: { code?: string; fields?: { attempts_left?: number } } };
    };
    const body = shaped?.error?.error;
    const attemptsLeft = typeof body?.fields?.attempts_left === 'number'
      ? body.fields.attempts_left
      : null;

    const known: readonly OtpFailure[] = [
      'WRONG_CODE', 'EXPIRED', 'NO_PENDING_CODE',
      'TOO_MANY_ATTEMPTS', 'USER_LOCKED', 'RATE_LIMITED',
    ];
    const code = body?.code as OtpFailure | undefined;
    const failure: OtpFailure = code && known.includes(code) ? code : 'UNKNOWN';

    return { failure, attemptsLeft };
  }

  private adopt(session: AuthSession): void {
    this.session.set(session);
    this.abandonChallenge();
    try {
      sessionStorage.setItem(TOKEN_KEY, JSON.stringify(session));
    } catch {
      // A browser with storage blocked still works; the session simply does
      // not survive a reload. Losing it is the safe direction to fail.
    }
  }

  private restore(): AuthSession | null {
    try {
      const raw = sessionStorage.getItem(TOKEN_KEY);
      if (!raw) {
        return null;
      }
      const session = JSON.parse(raw) as AuthSession;
      // An expiry the client can read is a courtesy, not a control: it saves
      // a round trip on an obviously dead token. The server decides.
      if (!session.token || new Date(session.expiresAt).getTime() <= Date.now()) {
        sessionStorage.removeItem(TOKEN_KEY);
        return null;
      }
      return session;
    } catch {
      return null;
    }
  }
}
