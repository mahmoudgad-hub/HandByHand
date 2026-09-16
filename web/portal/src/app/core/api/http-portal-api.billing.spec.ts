import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { BillingOverview } from '../models/portal.models';
import { HttpPortalApi } from './http-portal-api';

/**
 * The billing requests, counted (#15). The screen-level merge is tested in
 * features/billing; this proves the other half - that a retry of one
 * section does not quietly fetch the other two anyway, which would pass
 * every screen test and change nothing a family waits for.
 */
describe('HttpPortalApi.billing sections', () => {
  let api: HttpPortalApi;
  let http: HttpTestingController;
  const base = `${DEFAULT_HBH_CONFIG.apiBaseUrl}/api/v1`;

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

  /**
   * Answers the children list with two children, then answers everything
   * else that was asked with an empty list, and returns what was asked.
   */
  function answer(): string[] {
    http.expectOne(`${base}/children`).flush({ children: [{ child_id: 7 }, { child_id: 8 }] });
    const rest = http.match(() => true);
    for (const req of rest) {
      req.flush(req.request.url.endsWith('/balance')
        ? { currency_code: 'EGP', open_invoice_count: 0, outstanding_amt: '0' }
        : { invoices: [], packages: [] });
    }
    return rest.map((req) => req.request.url.replace(base, '')).sort();
  }

  it('fetches all three sections for every child on first load', () => {
    api.billing().subscribe();
    expect(answer()).toEqual([
      '/children/7/balance', '/children/7/invoices', '/children/7/packages',
      '/children/8/balance', '/children/8/invoices', '/children/8/packages',
    ]);
  });

  it('fetches only the invoices when only the invoices are retried', () => {
    let result: BillingOverview | undefined;
    api.billing(new Set(['invoices'])).subscribe((overview) => (result = overview));
    expect(answer()).toEqual(['/children/7/invoices', '/children/8/invoices']);
    // And the section it fetched says it arrived.
    expect(result?.invoicesUnavailable).toBeFalse();
  });
});
