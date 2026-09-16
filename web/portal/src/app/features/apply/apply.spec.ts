import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import ar from '../../../assets/i18n/ar.json';
import { EnrolmentApi } from '../../core/api/enrolment.api';
import { Apply } from './apply';

/**
 * The child's birth date on the enrolment form (#18).
 *
 * This form had already been fixed once - three named parts instead of
 * <input type="date">, whose order is the browser's - and a redesign put the
 * native input back while leaving the fix's code behind unused. Nothing
 * failed: the field was valid, the form submitted, and 7 March could arrive
 * as 3 July. This test is what stops the third time.
 */
describe('Apply birth date', () => {
  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(), provideHttpClientTesting(), provideRouter([]),
        { provide: HBH_CONFIG, useValue: DEFAULT_HBH_CONFIG },
        { provide: EnrolmentApi, useValue: {} },
      ],
    });
  });

  it('is day, month by name and year - never a browser date box', () => {
    const fixture = TestBed.createComponent(Apply);
    fixture.detectChanges();
    const root: HTMLElement = fixture.nativeElement;
    expect(root.querySelector('input[type=date]')).toBeNull();

    const [day, month, year] = Array.from(
      root.querySelectorAll('.hbh-dateparts select')) as HTMLSelectElement[];
    expect(day.id).toBe('a-child_birth_date');   // the label still points at it
    // The month box carries names, so 3 and 7 cannot trade places.
    expect(Array.from(month.options).some((o) => /[^\d\s]/.test(o.text) && o.value === '3')).toBeTrue();

    for (const [box, value] of [[day, '7'], [month, '3'], [year, '2021']] as [HTMLSelectElement, string][]) {
      box.value = value;
      box.dispatchEvent(new Event('change'));
    }
    fixture.detectChanges();
    expect((fixture.componentInstance as unknown as { value(f: string): string })
      .value('child_birth_date')).toBe('2021-03-07');
  });

  it('has words for the three boxes in the portal bundle', () => {
    // The component is shared, its words were only in the console's bundle,
    // and the form showed "field.day" to families on the first try.
    for (const key of ['field.day', 'field.month', 'field.year']) {
      expect((ar as Record<string, string>)[key]).withContext(key).toBeDefined();
    }
  });
});
