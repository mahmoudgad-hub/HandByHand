import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';

import { opsAuthInterceptor } from './ops-auth.interceptor';

/**
 * WHERE THE TOKEN IS ALLOWED TO GO. The console's copy of the portal suite,
 * and it is deliberately a copy rather than a shared helper: these are two
 * interceptors with two services behind them, and a helper that tested both
 * at once would go green the day one of them stopped calling it.
 *
 * The third case is the one that cannot be written as a deny-list - a host
 * nobody has added yet. The first is the control: a suite that only proves
 * where the token is withheld stays green the day it is withheld everywhere.
 */
describe('opsAuthInterceptor: where the token goes', () => {
  let http: HttpClient;
  let mock: HttpTestingController;

  const bearerFor = (url: string): string | null => {
    http.get(url).subscribe({ next: () => undefined, error: () => undefined });
    const req = mock.expectOne(url);
    const header = req.request.headers.get('Authorization');
    req.flush({});
    return header;
  };

  beforeEach(() => {
    // A live session, put there the way a reload would find it. With no token
    // the interceptor attaches nothing to anything and all three assertions
    // below would pass while proving nothing at all.
    sessionStorage.setItem('hbh.ops.session', JSON.stringify({
      token: 'a-token',
      expiresAt: new Date(Date.now() + 3_600_000).toISOString(),
    }));

    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        { provide: HBH_CONFIG, useValue: DEFAULT_HBH_CONFIG },
        provideHttpClient(withInterceptors([opsAuthInterceptor])),
        provideHttpClientTesting(),
      ],
    });
    http = TestBed.inject(HttpClient);
    mock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    mock.verify();
    sessionStorage.removeItem('hbh.ops.session');
  });

  it('carries the token to the service', () => {
    expect(bearerFor('/api/v1/children')).toBe('Bearer a-token');
  });

  it('keeps it out of the translation bundle, which is a static file', () => {
    expect(bearerFor('assets/i18n/ar.json')).toBeNull();
  });

  it('keeps it off any host that is not the service', () => {
    expect(bearerFor('https://fonts.example.com/family.css')).toBeNull();
  });
});
