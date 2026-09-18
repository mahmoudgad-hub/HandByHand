import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, convertToParamMap, provideRouter } from '@angular/router';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { CASELOAD_SPEC } from '../../core/resource/resource-spec';
import { ResourceScreen } from './resource-screen';

/**
 * Which of the two doors into `caseload` this screen goes through (HBH-103).
 *
 * There are two, and the policy guards both, so this is not a hole - it is
 * the older problem underneath a hole: TWO DOORS INTO ONE RULE MEANS THE
 * WEAKER ONE DECIDES. The generic POST /caseload from registerCRUD inserts
 * the row and nothing else. hbh.assign_therapist, behind
 * POST /children/{id}/caseload, carries three behaviours the insert does
 * not:
 *
 *   it returns the LIVE ROW when the assignment already exists, instead of
 *   colliding on the double click a busy desk produces;
 *   it MOVES the primary - demote then promote, two statements, because one
 *   row may not be updated twice in a statement;
 *   and it reads the permission before it reads the row.
 *
 * The middle one is the one with teeth: nothing in the schema stops a child
 * having two primaries for one service - uix_caseload_live is keyed on
 * (therapist, child, service) - so the generic door can leave a state the
 * function would never produce, and no constraint says a word.
 *
 * These tests assert the URL, which is the whole point. A test that checked
 * "a row was created" would pass on either door.
 */
describe('Assigning a child to a therapist', () => {
  let http: HttpTestingController;

  const mount = () => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(), provideHttpClientTesting(), provideRouter([]),
        { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, apiBaseUrl: '' } },
        { provide: OpsAuthService, useValue: { can: () => true } },
        {
          provide: ActivatedRoute, useValue: {
            snapshot: { queryParamMap: convertToParamMap({}), data: { specs: [CASELOAD_SPEC] } },
          },
        },
      ],
    });
    http = TestBed.inject(HttpTestingController);
    const fixture = TestBed.createComponent(ResourceScreen);
    fixture.detectChanges();
    http.expectOne((r) => r.url === '/api/v1/caseload')
      .flush({ caseload: [row()], total: 1, limit: 20, offset: 0 });
    settleRefs();
    fixture.detectChanges();
    return fixture;
  };

  const row = () => ({
    caseload_id: 5, therapist_id: 3, child_id: 7, service_id: 2,
    is_primary_flg: false, active_flg: true,
  });

  type Screen = {
    startCreate(): void;
    save(): void;
    archive(row: Record<string, unknown>): void;
    canEditRow(row: Record<string, unknown>): boolean;
    controls(): Record<string, { setValue(value: string): void }>;
  };

  const screenOf = (fixture: ReturnType<typeof mount>) =>
    fixture.componentInstance as unknown as Screen;

  /**
   * The reference lists behind the three pickers, answered and dismissed.
   *
   * They are read whenever the list reloads, they are not what any of this
   * is about, and leaving them open would fail verify() for a reason that
   * has nothing to do with the door being tested.
   */
  const settleRefs = () => {
    for (const ref of ['therapists', 'children', 'services']) {
      for (const request of http.match((r) => r.url === `/api/v1/${ref}`)) {
        request.flush({ [ref]: [], total: 0, limit: 100, offset: 0 });
      }
    }
  };

  afterEach(() => { settleRefs(); http.verify(); });

  it('goes through the function, not the bare insert', () => {
    const fixture = mount();
    const screen = screenOf(fixture);
    screen.startCreate();
    fixture.detectChanges();
    const controls = screen.controls();
    controls['therapist_id'].setValue('3');
    controls['child_id'].setValue('7');
    controls['service_id'].setValue('2');
    screen.save();

    // The child is in the PATH, which is what makes this the other route.
    const sent = http.expectOne('/api/v1/children/7/caseload');
    expect(sent.request.method).toBe('POST');
    expect(sent.request.body).toEqual({ therapist_id: 3, service_id: 2, is_primary: false });
    sent.flush({ caseload_id: 9 });
    http.expectOne((r) => r.url === '/api/v1/caseload')
      .flush({ caseload: [], total: 0, limit: 20, offset: 0 });
  });

  it('never posts to the generic collection', () => {
    const fixture = mount();
    const screen = screenOf(fixture);
    screen.startCreate();
    fixture.detectChanges();
    const controls = screen.controls();
    controls['therapist_id'].setValue('3');
    controls['child_id'].setValue('7');
    controls['service_id'].setValue('2');
    screen.save();
    http.expectNone((r) => r.url === '/api/v1/caseload' && r.method === 'POST');
    http.expectOne('/api/v1/children/7/caseload').flush({ caseload_id: 9 });
    http.expectOne((r) => r.url === '/api/v1/caseload')
      .flush({ caseload: [], total: 0, limit: 20, offset: 0 });
  });

  it('carries "make this one the primary" through, because only this door moves it', () => {
    const fixture = mount();
    const screen = screenOf(fixture);
    screen.startCreate();
    fixture.detectChanges();
    const controls = screen.controls();
    controls['therapist_id'].setValue('3');
    controls['child_id'].setValue('7');
    controls['service_id'].setValue('2');
    controls['is_primary_flg'].setValue('true');
    screen.save();
    const sent = http.expectOne('/api/v1/children/7/caseload');
    expect(sent.request.body).toEqual({ therapist_id: 3, service_id: 2, is_primary: true });
    sent.flush({ caseload_id: 9 });
    http.expectOne((r) => r.url === '/api/v1/caseload')
      .flush({ caseload: [], total: 0, limit: 20, offset: 0 });
  });

  it('ends an assignment through the same pair of routes', () => {
    const fixture = mount();
    screenOf(fixture).archive(row());
    const sent = http.expectOne('/api/v1/children/7/caseload/5');
    expect(sent.request.method).toBe('DELETE');
    sent.flush({ ended: true });
    http.expectOne((r) => r.url === '/api/v1/caseload')
      .flush({ caseload: [], total: 0, limit: 20, offset: 0 });
  });

  /**
   * A caseload row IS its three columns - uix_caseload_live is keyed on
   * them - so "edit" here means "this was a different assignment all along".
   * PATCHing one of the three through the generic door would move the row
   * without any of the function's rules, which is the same defect as the
   * insert, only quieter. End it and assign again.
   */
  it('offers no edit, because changing any of the three is a different assignment', () => {
    const fixture = mount();
    expect(screenOf(fixture).canEditRow(row())).toBeFalse();
  });
});
