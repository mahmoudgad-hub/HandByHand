import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';

import { AuthApi } from './auth-api';
import { authInterceptor } from './auth.interceptor';
import { FixtureAuthApi } from './fixture-auth-api';

/**
 * WHERE THE TOKEN IS ALLOWED TO GO.
 *
 * The interceptor used to decide by exclusion: attach the bearer token to
 * everything except a URL starting `assets/`. That reads as one rule and is
 * really two - "the API gets the token" and "and so does anything nobody
 * thought of". A font host, an analytics beacon, a map tile, a help page,
 * any absolute URL a future screen reaches for: each one would have carried
 * a guardian's session token to a third party, and nothing in the screen
 * that added it would have looked wrong.
 *
 * The list below is the whole surface the portal asks for, measured rather
 * than assumed: every call resolves to `${apiBaseUrl}/api/v1/...`, and the
 * translation bundle is the only request that is not the API at all.
 *
 * So the rule is stated the other way round - the API, and nothing else -
 * and the third case is the one that matters, because it is the one no
 * deny-list can be written in advance for.
 */
describe('authInterceptor: where the token goes', () => {
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
    // A live session, put there the way a reload would find it. Without a
    // token the interceptor attaches nothing to anything, and all three
    // assertions below would pass while proving nothing at all.
    sessionStorage.setItem('hbh.portal.session', JSON.stringify({
      token: 'a-token',
      expiresAt: new Date(Date.now() + 3_600_000).toISOString(),
    }));

    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        { provide: AuthApi, useClass: FixtureAuthApi },
        { provide: HBH_CONFIG, useValue: DEFAULT_HBH_CONFIG },
        provideHttpClient(withInterceptors([authInterceptor])),
        provideHttpClientTesting(),
      ],
    });
    http = TestBed.inject(HttpClient);
    mock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    mock.verify();
    sessionStorage.removeItem('hbh.portal.session');
  });

  // The control. A suite that only proves where the token is withheld stays
  // green the day somebody withholds it everywhere.
  it('carries the token to the service', () => {
    expect(bearerFor('/api/v1/me/children')).toBe('Bearer a-token');
  });

  it('keeps it out of the translation bundle, which is a static file', () => {
    expect(bearerFor('assets/i18n/ar.json')).toBeNull();
  });

  it('keeps it off any host that is not the service', () => {
    expect(bearerFor('https://fonts.example.com/family.css')).toBeNull();
  });
});
