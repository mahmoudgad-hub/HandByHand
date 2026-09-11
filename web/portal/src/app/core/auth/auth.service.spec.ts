import { TestBed, fakeAsync, tick } from '@angular/core/testing';
import { provideRouter } from '@angular/router';

import { AuthApi } from './auth-api';
import { AuthService } from './auth.service';
import { FixtureAuthApi } from './fixture-auth-api';

/**
 * The refusal mapping is the part of sign-in a parent actually meets. It reads
 * the service's codes and nothing else - never a sentence the server wrote,
 * because a server's own words about why it said no describe its internals.
 */
describe('AuthService.readRefusal', () => {
  let auth: AuthService;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        { provide: AuthApi, useClass: FixtureAuthApi },
        AuthService,
      ],
    });
    auth = TestBed.inject(AuthService);
  });

  it('reads the code and the attempts left out of the service body', () => {
    const refusal = auth.readRefusal({
      status: 401,
      error: { error: { code: 'WRONG_CODE', fields: { attempts_left: 3 } } },
    });

    expect(refusal.failure).toBe('WRONG_CODE');
    expect(refusal.attemptsLeft).toBe(3);
  });

  it('reports a lock, which no retry can clear', () => {
    const refusal = auth.readRefusal({
      status: 423,
      error: { error: { code: 'TOO_MANY_ATTEMPTS' } },
    });

    expect(refusal.failure).toBe('TOO_MANY_ATTEMPTS');
    expect(refusal.attemptsLeft).toBeNull();
  });

  /**
   * A code this portal has not been taught must not be shown as one it has.
   * UNKNOWN reaches a generic message; guessing would put the wrong sentence
   * under the boxes.
   */
  it('calls an unfamiliar code unknown rather than guessing', () => {
    const refusal = auth.readRefusal({
      status: 401,
      error: { error: { code: 'SOMETHING_NEW' } },
    });

    expect(refusal.failure).toBe('UNKNOWN');
  });

  it('survives an error that carries no body at all', () => {
    expect(auth.readRefusal(new Error('network down')).failure).toBe('UNKNOWN');
    expect(auth.readRefusal(undefined).failure).toBe('UNKNOWN');
  });

  /**
   * fakeAsync because the number is only remembered once the request comes
   * back - the fixture answers after a delay, exactly as a network would.
   */
  it('masks the mobile without ever showing the middle digits', fakeAsync(() => {
    auth.requestOtp('01001234567').subscribe();
    tick(500);

    expect(auth.maskedMobile()).toBe('010 **** 4567');
    expect(auth.maskedMobile()).not.toContain('0123');
  }));

  it('forgets the number when the code is abandoned', fakeAsync(() => {
    auth.requestOtp('01001234567').subscribe();
    tick(500);
    auth.abandonChallenge();

    expect(auth.maskedMobile()).toBe('');
    expect(auth.pendingChallenge()).toBeNull();
  }));
});
