import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import {
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '../config/app-config';
import { FormatService } from '../format/format.service';
import { I18nService } from './i18n.service';

/**
 * Arabic has six plural categories and this centre's children land in the
 * awkward ones every day. A single "{n} سنوات" string prints "١ سنوات" for a
 * one-year-old, which is the defect these guard.
 */
describe('I18nService.plural', () => {
  let i18n: I18nService;
  let http: HttpTestingController;

  const ages = {
    'child.age.zero': 'أقل من سنة',
    'child.age.one': 'سنة واحدة',
    'child.age.two': 'سنتان',
    'child.age.few': '{count} سنوات',
    'child.age.many': '{count} سنة',
    'child.age.other': '{count} سنة',
  };

  beforeEach(async () => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: HBH_CONFIG, useValue: DEFAULT_HBH_CONFIG },
        FormatService,
        I18nService,
      ],
    });
    i18n = TestBed.inject(I18nService);
    http = TestBed.inject(HttpTestingController);

    const loading = i18n.load('ar');
    http.expectOne('assets/i18n/ar.json').flush(ages);
    await loading;
  });

  afterEach(() => http.verify());

  it('says "سنة واحدة" for one, not "١ سنوات"', () => {
    expect(i18n.plural('child.age', 1)).toBe('سنة واحدة');
  });

  it('says "سنتان" for two', () => {
    expect(i18n.plural('child.age', 2)).toBe('سنتان');
  });

  it('uses the few form from three to ten, with Arabic-Indic digits', () => {
    expect(i18n.plural('child.age', 6)).toBe('٦ سنوات');
  });

  it('uses the many form above ten', () => {
    expect(i18n.plural('child.age', 11)).toBe('١١ سنة');
  });

  it('has something to say at zero', () => {
    expect(i18n.plural('child.age', 0)).toBe('أقل من سنة');
  });

  it('falls back to the other form when a category is missing', () => {
    // A bundle that only supplies `.other` must still work - that is what a
    // language with one plural will ship.
    expect(i18n.plural('child.age', 137)).toBe('١٣٧ سنة');
  });
});
