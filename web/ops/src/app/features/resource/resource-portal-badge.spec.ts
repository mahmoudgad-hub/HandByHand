import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, convertToParamMap, provideRouter } from '@angular/router';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { CHILDREN_SPEC } from '../../core/resource/resource-spec';
import { ResourceScreen } from './resource-screen';

/**
 * "This family cannot sign in" in the children list (HBH-084).
 *
 * The card's first criterion is that the badge is READ from the computed
 * flag and not inferred by the screen, and these tests are written to fail
 * if anybody ever replaces it with a guess - a missing mobile, an empty
 * guardian list, a zero count. The console cannot see hbh.users; only the
 * service can answer this, and it answers it under the caller's identity.
 *
 * THE THIRD CASE IS THE ONE THAT MATTERS. A row with no flag at all is a
 * build talking to a service that does not compute it - "unknown", not "no
 * account" - and drawing a warning there would send a centre off creating
 * accounts for families that already have them, on every child at once.
 */
describe('The family-has-no-account badge', () => {
  let http: HttpTestingController;

  const mount = (rows: readonly Record<string, unknown>[]) => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(), provideHttpClientTesting(), provideRouter([]),
        { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, apiBaseUrl: '' } },
        { provide: OpsAuthService, useValue: { can: () => true } },
        {
          provide: ActivatedRoute, useValue: {
            snapshot: { queryParamMap: convertToParamMap({}), data: { specs: [CHILDREN_SPEC] } },
          },
        },
      ],
    });
    http = TestBed.inject(HttpTestingController);
    const fixture = TestBed.createComponent(ResourceScreen);
    fixture.detectChanges();
    http.expectOne((r) => r.url === '/api/v1/children')
      .flush({ children: rows, total: rows.length, limit: 20, offset: 0 });
    fixture.detectChanges();
    return fixture;
  };

  const child = (id: number, flag: unknown) => {
    const row: Record<string, unknown> = {
      child_id: id, full_name_ar: 'طفل', child_no: `CH-${id}`,
      birth_date: '2020-03-07', gender: 'M', status: 'ACTIVE', active_flg: true,
    };
    if (flag !== undefined) {
      row['family_has_portal_account'] = flag;
    }
    return row;
  };

  const badges = (fixture: ReturnType<typeof mount>) =>
    Array.from(fixture.nativeElement.querySelectorAll('tbody .hbh-badge--warn'));

  afterEach(() => http.verify());

  it('marks the family the service says has no account', () => {
    const fixture = mount([child(1, false)]);
    expect(badges(fixture).length).toBe(1);
  });

  it('says nothing about a family that has one', () => {
    const fixture = mount([child(1, true)]);
    expect(badges(fixture).length).toBe(0);
  });

  it('says nothing when the service did not answer the question', () => {
    // No flag on the row at all. Silence is the only honest drawing: the
    // screen does not know, and a warning here would be invented.
    const fixture = mount([child(1, undefined)]);
    expect(badges(fixture).length).toBe(0);
  });

  it('does not read a family with no mobile as a family with no account', () => {
    // The inference somebody would reach for if the flag were ever dropped.
    // The row says the family HAS an account; the absent mobile must not
    // overrule it.
    const fixture = mount([{ ...child(1, true), mobile: '', guardians: [] }]);
    expect(badges(fixture).length).toBe(0);
  });

  it('marks only the rows that carry the flag as false', () => {
    const fixture = mount([child(1, false), child(2, true), child(3, false)]);
    expect(badges(fixture).length).toBe(2);
  });
});
