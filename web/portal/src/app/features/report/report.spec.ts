import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, convertToParamMap, provideRouter } from '@angular/router';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { FixturePortalApi } from '../../core/api/fixture-portal-api';
import { PortalApi } from '../../core/api/portal-api';
import { ChildContextService } from '../../core/auth/child-context.service';
import { Report } from './report';

/**
 * Printing a report (#23). The dialog cannot be tested; what can is that the
 * button asks for it, and that the printed page carries what the screen's
 * chrome would otherwise have said: whose report this is.
 */
describe('Report print', () => {
  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(), provideHttpClientTesting(), provideRouter([]),
        { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, useFixtures: true } },
        { provide: PortalApi, useClass: FixturePortalApi },
        { provide: ChildContextService, useValue: { selected: () => ({ fullName: 'يوسف أحمد' }) } },
        { provide: ActivatedRoute, useValue: { snapshot: { paramMap: convertToParamMap({ reportId: '71' }) } } },
      ],
    });
  });

  it('offers print / save as PDF, and names the child on the printed page', async () => {
    const fixture = TestBed.createComponent(Report);
    fixture.detectChanges();
    await fixture.whenStable();
    fixture.detectChanges();
    const root: HTMLElement = fixture.nativeElement;

    const print = spyOn(window, 'print');
    const button = root.querySelector('.rep__tools button') as HTMLButtonElement;
    expect(button).withContext('the print button').not.toBeNull();
    button.click();
    expect(print).toHaveBeenCalledTimes(1);

    expect(root.querySelector('.rep__printhead strong')?.textContent?.trim()).toBe('يوسف أحمد');
    // The button and the shell are not part of the document.
    expect(button.closest('.no-print')).not.toBeNull();
  });
});
