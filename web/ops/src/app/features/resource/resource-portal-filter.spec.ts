import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, convertToParamMap, provideRouter } from '@angular/router';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { CHILDREN_SPEC, GUARDIANS_SPEC } from '../../core/resource/resource-spec';
import { ResourceScreen } from './resource-screen';

/**
 * "Show only the families who cannot sign in" (HBH-101).
 *
 * THE FILTER IS A QUESTION FOR THE SERVICE, NOT A PASS OVER THIS PAGE. The
 * list is paged, so filtering the rows already in the browser would search
 * the twenty children on screen and quietly ignore the rest - on a screen
 * whose entire purpose is finding the family nobody noticed. That is why
 * this went back to the service as `?without_portal_account=true` and why
 * the first test below asserts the PARAMETER rather than the row count.
 *
 * The service computes the flag behind the filter from the same expression
 * it computes the badge from (store/portal.go), under the caller's own
 * identity, so the filter cannot show a family the policy would hide and
 * cannot disagree with the badge beside it.
 */
describe('The "families without an account" filter', () => {
  let http: HttpTestingController;

  const mount = (spec = CHILDREN_SPEC, can: (p: string) => boolean = () => true) => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(), provideHttpClientTesting(), provideRouter([]),
        { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, apiBaseUrl: '' } },
        { provide: OpsAuthService, useValue: { can } },
        {
          provide: ActivatedRoute, useValue: {
            snapshot: { queryParamMap: convertToParamMap({}), data: { specs: [spec] } },
          },
        },
      ],
    });
    http = TestBed.inject(HttpTestingController);
    const fixture = TestBed.createComponent(ResourceScreen);
    fixture.detectChanges();
    return fixture;
  };

  const answer = (resource: string, rows: unknown[], total = rows.length) =>
    http.expectOne((r) => r.url === `/api/v1/${resource}`)
      .flush({ [resource]: rows, total, limit: 20, offset: 0 });

  const asked = (resource: string) => {
    const request = http.expectOne((r) => r.url === `/api/v1/${resource}`);
    const url = request.request.urlWithParams;
    request.flush({ [resource]: [], total: 0, limit: 20, offset: 0 });
    return url;
  };

  const child = (id: number, hasAccount: boolean) => ({
    child_id: id, full_name_ar: 'طفل', child_no: `CH-${id}`, birth_date: '2020-03-07',
    gender: 'M', status: 'ACTIVE', active_flg: true, family_has_portal_account: hasAccount,
  });

  afterEach(() => http.verify());

  it('asks the SERVICE for them, rather than sifting the page it was given', () => {
    const fixture = mount();
    answer('children', [child(1, false), child(2, true)]);
    fixture.detectChanges();

    (fixture.componentInstance as unknown as { toggleWithoutAccount(): void })
      .toggleWithoutAccount();
    expect(asked('children')).toContain('without_portal_account=true');
  });

  it('asks nothing extra while it is off', () => {
    mount();
    expect(asked('children')).not.toContain('without_portal_account');
  });

  it('stops asking when it is turned off again', () => {
    const fixture = mount();
    answer('children', []);
    const screen = fixture.componentInstance as unknown as { toggleWithoutAccount(): void };
    screen.toggleWithoutAccount();
    asked('children');
    screen.toggleWithoutAccount();
    expect(asked('children')).not.toContain('without_portal_account');
  });

  /**
   * Page 4 of a wide list is nowhere in a narrow one, and an empty table
   * there reads as "there are none" - which is the opposite of what this
   * filter is for. Same reason toggleArchived resets the page.
   */
  it('returns to the first page, because a narrower list has fewer', () => {
    const fixture = mount();
    answer('children', [child(1, true)], 200);
    const screen = fixture.componentInstance as unknown as {
      toggleWithoutAccount(): void; goToPage(page: number): void;
    };
    screen.goToPage(4);
    expect(asked('children')).toContain('page=4');
    screen.toggleWithoutAccount();
    expect(asked('children')).not.toContain('page=4');
  });

  it('is offered on the children list', () => {
    const fixture = mount();
    answer('children', [child(1, false)]);
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('[data-test="without-account"]')).not.toBeNull();
  });

  /**
   * And nowhere else. The flag is computed on a child row; offering the
   * switch on another resource would send a parameter the service ignores
   * and draw a control that does nothing - which reads as "there are none".
   */
  it('is not offered on a list the service cannot answer it for', () => {
    const fixture = mount(GUARDIANS_SPEC);
    answer('guardians', []);
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('[data-test="without-account"]')).toBeNull();
  });
});
