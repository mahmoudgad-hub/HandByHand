import { ComponentFixture, TestBed } from '@angular/core/testing';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '../config/app-config';
import { I18nService } from '../i18n/i18n.service';
import { DateParts } from './date-parts';

/**
 * A stand-in for the translator.
 *
 * The real one fetches its bundle over HTTP, and wiring that in would make
 * these tests depend on a network stub to answer a question about date
 * arithmetic. The component uses it for the three aria-labels and nothing
 * else, so returning the key is enough - and it keeps the assertions below
 * about the VALUE that leaves the component rather than the words on it.
 */
class StubI18n {
  translate(key: string): string {
    return key;
  }
}

/**
 * The defect this component exists for, held down.
 *
 * `<input type="date">` takes its format from the BROWSER, not the page. A
 * receptionist on an English Chrome typing into an Arabic form saw
 * `mm/dd/yyyy`, and 7 March was stored as 3 July - silently, on the value a
 * child's age and every plan after it is derived from.
 *
 * TESTED ONCE, HERE. Three screens use this component and none of them test
 * it: a copy per consumer would be the same duplication the component was
 * extracted to remove, and the day they disagreed the weakest would be the
 * one deciding.
 *
 * What is NOT tested here is the rendering - that the middle box says
 * "مارس". That is FormatService.monthNames, which has its own spec. These
 * are about the value that leaves the component, because that is the value
 * that reaches the database.
 */
describe('DateParts', () => {
  let fixture: ComponentFixture<DateParts>;
  let emitted: string[];

  /** The three <select>s, in the order the template lays them out. */
  const boxes = (): HTMLSelectElement[] =>
    Array.from(fixture.nativeElement.querySelectorAll('select'));

  const choose = (which: 'd' | 'm' | 'y', value: string): void => {
    const index = which === 'd' ? 0 : which === 'm' ? 1 : 2;
    const box = boxes()[index];
    box.value = value;
    box.dispatchEvent(new Event('change'));
    fixture.detectChanges();
  };

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [DateParts],
      providers: [
        { provide: HBH_CONFIG, useValue: DEFAULT_HBH_CONFIG },
        { provide: I18nService, useClass: StubI18n },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(DateParts);
    emitted = [];
    fixture.componentRef.setInput('value', '');
    fixture.componentInstance.valueChange.subscribe((v: string) => emitted.push(v));
    fixture.detectChanges();
  });

  it('draws three boxes, not a native date input', () => {
    expect(boxes().length).toBe(3);
    expect(fixture.nativeElement.querySelector('input[type="date"]')).toBeNull();
  });

  it('emits nothing usable until all three are chosen', () => {
    choose('d', '7');
    choose('m', '3');
    // Two of three. A half-built date on the wire is refused as malformed,
    // which says nothing about which part is still missing.
    expect(emitted.every((v) => v === '')).toBeTrue();
  });

  it('composes the ISO date once the year arrives', () => {
    // Deliberately the pair that the native control confuses: written
    // 07/03 it is 7 March here and 3 July in an American locale.
    fixture.componentRef.setInput('value', '');
    choose('d', '7');
    fixture.componentRef.setInput('value', emitted[emitted.length - 1]);
    choose('m', '3');
    fixture.componentRef.setInput('value', emitted[emitted.length - 1]);
    choose('y', '2020');

    expect(emitted[emitted.length - 1]).toBe('2020-03-07');
  });

  it('pads the month and day, because the service takes YYYY-MM-DD', () => {
    fixture.componentRef.setInput('value', '2020-11-20');
    fixture.detectChanges();
    choose('m', '3');
    expect(emitted[emitted.length - 1]).toBe('2020-03-20');
  });

  it('reads an existing value back into the three boxes', () => {
    fixture.componentRef.setInput('value', '2019-08-04');
    fixture.detectChanges();

    const [day, month, year] = boxes();
    expect(day.value).toBe('4');
    // The value is the month NUMBER; what the person reads is its name.
    expect(month.value).toBe('8');
    expect(year.value).toBe('2019');
  });

  it('shows nothing selected when there is no date yet', () => {
    fixture.componentRef.setInput('value', '');
    fixture.detectChanges();
    expect(boxes().map((b) => b.value)).toEqual(['', '', '']);
  });

  it('clears the value when a part is taken back out', () => {
    fixture.componentRef.setInput('value', '2020-03-07');
    fixture.detectChanges();
    choose('m', '');
    // Not "2020--07", and not the old date left standing: an incomplete
    // date is no date, and the caller has to be told so.
    expect(emitted[emitted.length - 1]).toBe('');
  });

  it('offers a year range wide enough for a birth date and a future plan', () => {
    const years = boxes()[2].options;
    const values = Array.from(years).map((o) => o.value).filter((v) => v !== '');
    const now = new Date().getUTCFullYear();

    expect(Number(values[0])).toBe(now + 5);
    expect(Number(values[values.length - 1])).toBe(1920);
  });
});
