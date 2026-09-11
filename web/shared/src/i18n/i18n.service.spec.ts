import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import {
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '../config/app-config';
import { I18nService } from './i18n.service';

describe('I18nService', () => {
  let i18n: I18nService;
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: HBH_CONFIG, useValue: DEFAULT_HBH_CONFIG },
        I18nService,
      ],
    });
    i18n = TestBed.inject(I18nService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  async function loadBundle(bundle: Record<string, string>): Promise<void> {
    const loading = i18n.load('ar');
    http.expectOne('assets/i18n/ar.json').flush(bundle);
    await loading;
  }

  it('fills placeholders by name', async () => {
    await loadBundle({ 'child.age': '{years} سنوات' });

    expect(i18n.translate('child.age', { years: 6 })).toBe('6 سنوات');
  });

  /**
   * A gap in the bundle has to be visible. Returning an empty string would
   * leave a blank the eye slides past, and the missing string would ship.
   */
  it('returns the key itself when the bundle has no entry', async () => {
    await loadBundle({});

    expect(i18n.translate('nothing.here')).toBe('nothing.here');
  });

  it('leaves a placeholder in place when no value was supplied', async () => {
    await loadBundle({ 'greet': 'أهلاً {name}' });

    expect(i18n.translate('greet', { other: 'x' })).toBe('أهلاً {name}');
  });

  it('joins a list with the separator from the bundle', async () => {
    await loadBundle({ 'format.listSeparator': '، ' });

    expect(i18n.list(['تخاطب', 'علاج وظيفي'])).toBe('تخاطب، علاج وظيفي');
  });
});
