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

/**
 * What signing out leaves behind on the device (SEC-016 P3).
 *
 * The selected child's identifier is written to sessionStorage so a reload
 * does not throw a guardian back to the picker mid-task. It grants nothing -
 * the child is fetched again and the server re-checks the guardian's link on
 * every request, so a stale or tampered value resolves to nothing.
 *
 * IT STILL MUST NOT SURVIVE SIGNING OUT. Same tab, second guardian: the key
 * from the first one was still there. Nothing could be read with it, but
 * "reads as somebody else's leftover" is what a person on a shared device is
 * entitled not to find - and a value that outlives the session it belonged
 * to is the shape of the defect, whether or not this one has teeth.
 */
describe('AuthService.signOut and the device', () => {
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

  const keys = () => ({
    token: sessionStorage.getItem('hbh.portal.session'),
    child: sessionStorage.getItem('hbh.portal.child'),
  });

  it('takes the selected child with the token', () => {
    sessionStorage.setItem('hbh.portal.session', 'a-token');
    sessionStorage.setItem('hbh.portal.child', 'child-uuid');
    // The control: both are there before, so "null after" says something.
    expect(keys().token).not.toBeNull();
    expect(keys().child).not.toBeNull();

    auth.signOut();

    expect(keys().token).toBeNull();
    expect(keys().child).toBeNull();
  });

  it('takes it on an expired session too, which is the same device', () => {
    sessionStorage.setItem('hbh.portal.session', 'a-token');
    sessionStorage.setItem('hbh.portal.child', 'child-uuid');

    auth.sessionExpired();

    expect(keys().token).toBeNull();
    expect(keys().child).toBeNull();
  });
});

/**
 * The masked number answers ONE question - "is that the number you meant?" -
 * and it can only answer it with the part that tells two numbers apart.
 *
 * It used to take the first three characters of what the service was given,
 * and the service is given the canonical international form. So every
 * Egyptian parent was shown `+20 **** 3838`: a prefix that every Egyptian
 * number has, hiding the operator prefix (010/011/012/015) that is the one
 * thing distinguishing them. The template's own comment said no country code
 * should appear there; the code had stopped agreeing with it.
 *
 * The root is the one CLAUDE.md already names for the database: a value
 * normalised on the way in blinds every read of it that still expects the
 * form the user typed. There it made comparisons match zero rows. Here it
 * blinded a display - quieter, because nothing returns empty and nobody
 * greps a screen.
 */
describe('AuthService.maskedMobile', () => {
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

  it('masks the number as the parent writes it, not as the service stores it', fakeAsync(() => {
    auth.requestOtp('+201225283838', '01225283838').subscribe();
    tick(400);

    expect(auth.maskedMobile()).toBe('012 **** 3838');
  }));

  it('keeps the last four, so the digits a parent checks are the ones shown', fakeAsync(() => {
    auth.requestOtp('+201095006478', '01095006478').subscribe();
    tick(400);

    expect(auth.maskedMobile()).toBe('010 **** 6478');
  }));

  it('works for a country with no trunk zero', fakeAsync(() => {
    // Kuwait: the table gives it an empty national prefix, so the national
    // form has no leading 0 and the meaningful head is simply its first three.
    auth.requestOtp('+96551234567', '51234567').subscribe();
    tick(400);

    expect(auth.maskedMobile()).toBe('512 **** 4567');
  }));

  it('is empty before a number is outstanding, and empty again after', fakeAsync(() => {
    expect(auth.maskedMobile()).toBe('');

    auth.requestOtp('+201225283838', '01225283838').subscribe();
    tick(400);
    expect(auth.maskedMobile()).not.toBe('');

    auth.abandonChallenge();
    expect(auth.maskedMobile()).toBe('');
  }));
});
