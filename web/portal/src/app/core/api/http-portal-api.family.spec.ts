import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { HttpPortalApi } from './http-portal-api';

/**
 * Who the family is, counted in requests (#16).
 *
 * The child guard (every reload of a child screen) and the profile asked
 * welcome() for the list of children and received, for each child, four
 * more requests they threw away. The test counts, because a lighter call
 * that quietly kept fetching would pass every screen test.
 */
describe('HttpPortalApi.family', () => {
  let api: HttpPortalApi;
  let http: HttpTestingController;
  const base = `${DEFAULT_HBH_CONFIG.apiBaseUrl}/api/v1`;
  const me = { user: { user_id: 1, full_name_ar: 'وليّ أمر', mobile: '+201000000000' } };
  const rows = [
    { child_id: 7, full_name_ar: 'يوسف', child_no: 'CH-7', birth_date: '2020-01-01', gender: 'M' },
    { child_id: 8, full_name_ar: 'ملك', child_no: 'CH-8', birth_date: '2021-01-01', gender: 'F' },
  ];

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(), provideHttpClientTesting(),
        { provide: HBH_CONFIG, useValue: DEFAULT_HBH_CONFIG },
        HttpPortalApi,
      ],
    });
    api = TestBed.inject(HttpPortalApi);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  it('asks two questions whatever the number of children', () => {
    let names: string[] = [];
    api.family().subscribe((family) => (names = family.children.map((c) => c.fullName)));
    http.expectOne(`${base}/me`).flush(me);
    http.expectOne(`${base}/children`).flush({ children: rows });
    // verify() in afterEach fails on any further request.
    expect(names).toEqual(['يوسف', 'ملك']);
  });

  it('does not claim a child has nothing booked when the diary was not asked', () => {
    let schedule: boolean[] = [];
    api.family().subscribe((family) => (schedule = family.children.map((c) => c.scheduleUnavailable)));
    http.expectOne(`${base}/me`).flush(me);
    http.expectOne(`${base}/children`).flush({ children: rows });
    expect(schedule).toEqual([true, true]);
  });

  it('is the lighter call: welcome() still asks four more per child', () => {
    // Pinned so the difference is on record, and so a change that folds the
    // welcome legs into one request shows up here as a number that moved.
    api.welcome().subscribe();
    http.expectOne(`${base}/me`).flush(me);
    http.expectOne(`${base}/children`).flush({ children: rows });
    const perChild = http.match(() => true);
    expect(perChild.length).toBe(8);
    perChild.forEach((req) => req.flush({}));
  });
});
