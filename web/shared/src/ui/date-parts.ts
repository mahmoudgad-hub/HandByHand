import {
  ChangeDetectionStrategy, Component, computed, inject, input, output, signal,
} from '@angular/core';

import { FormatService } from '../format/format.service';
import { I18nService } from '../i18n/i18n.service';

/**
 * A date as three named parts: day, month BY NAME, year.
 *
 * `<input type="date">` takes its format from the BROWSER, not from the page.
 * A receptionist on an English Chrome typing into an Arabic form sees
 * `mm/dd/yyyy`, and 7 March goes in as 3 July - silently, with nothing to
 * catch it, on a value the file is then built on. A named month cannot be
 * read in the wrong order.
 *
 * SHARED RATHER THAN COPIED, and that is the point of it existing. The
 * portal's enrolment form solved this months ago and the console did not,
 * because the answer lived in one screen instead of one component. Two more
 * screens needed it the day this was written.
 *
 * The value in and out is always `YYYY-MM-DD` - the string the service sends
 * and accepts. Only what a person touches is different. Empty until all three
 * are chosen: a half-built date sent onward is refused as malformed, which
 * says nothing about which of the three is still missing.
 *
 * NOT for filters. A wrong day in a filter shows a wrong list, which is seen
 * and corrected in a second, and the native calendar is genuinely better for
 * "jump to a day". This is for a date that gets STORED.
 */
@Component({
  selector: 'hbh-date-parts',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="hbh-dateparts">
      <select [id]="fieldId()" [value]="part('d')"
              [attr.aria-label]="i18n.translate('field.day')"
              (change)="setPart('d', $any($event.target).value)">
        <option value="">{{ i18n.translate('field.day') }}</option>
        @for (d of days; track d) { <option [value]="d">{{ d }}</option> }
      </select>
      <select [value]="part('m')"
              [attr.aria-label]="i18n.translate('field.month')"
              (change)="setPart('m', $any($event.target).value)">
        <option value="">{{ i18n.translate('field.month') }}</option>
        @for (name of months; track name; let i = $index) {
          <option [value]="i + 1">{{ name }}</option>
        }
      </select>
      <select [value]="part('y')"
              [attr.aria-label]="i18n.translate('field.year')"
              (change)="setPart('y', $any($event.target).value)">
        <option value="">{{ i18n.translate('field.year') }}</option>
        @for (y of years; track y) { <option [value]="y">{{ y }}</option> }
      </select>
    </div>
  `,
  styles: [`
    /* Equal columns rather than natural widths: a month name is far longer
       than a day number, and letting them size themselves puts one wide box
       beside two narrow ones, which reads as a mistake. */
    .hbh-dateparts { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; }
  `],
})
export class DateParts {
  protected readonly i18n = inject(I18nService);
  private readonly format = inject(FormatService);

  /** `YYYY-MM-DD`, or empty. */
  readonly value = input<string>('');
  /** For the <label for="..."> of whichever field this stands in for. */
  readonly fieldId = input<string>('');
  readonly valueChange = output<string>();

  protected readonly months = this.format.monthNames();
  protected readonly days = Array.from({ length: 31 }, (_, i) => i + 1);

  /**
   * Wide enough for a grandparent at one end and a plan ending a few years
   * out at the other. One range for every date: a per-use range would be a
   * second thing to keep in step with the first.
   */
  protected readonly years = computed(() => {
    const now = new Date().getUTCFullYear();
    const out: number[] = [];
    for (let y = now + 5; y >= 1920; y--) {
      out.push(y);
    }
    return out;
  })();

  /**
   * The three parts as chosen so far - INCLUDING a half-filled date.
   *
   * This is held here and not derived from `value()`, and the difference is
   * the whole component working or not. Two of the three are not a date, so
   * nothing can be emitted for them; if the parts were read back out of the
   * emitted value, the first pick would be echoed as empty and the second
   * would find nothing to join. A date could never be completed.
   *
   * It LOOKED fine in a browser, which is why this is worth spelling out: a
   * <select> keeps whatever the person picked, and Angular does not touch it
   * while the bound value stays '' - so the boxes held the choices and
   * nothing rendered them. The first re-render for any other reason would
   * have emptied all three in front of somebody mid-form. A unit test found
   * it; clicking through the screen did not.
   */
  private readonly chosen = signal<{ y: string; m: string; d: string }>(
    { y: '', m: '', d: '' });

  /**
   * The value the parent holds wins whenever it actually holds one.
   *
   * So a form opened on an existing row shows that row's date, and a form
   * reset to empty clears these boxes rather than keeping the last person's
   * half-typed answer.
   */
  private readonly fromInput = computed(() => {
    const parts = (this.value() ?? '').split('-');
    if (parts.length !== 3 || !parts[0]) {
      return null;
    }
    return {
      y: String(Number(parts[0]) || ''),
      m: String(Number(parts[1]) || ''),
      d: String(Number(parts[2]) || ''),
    };
  });

  protected part(which: 'y' | 'm' | 'd'): string {
    return (this.fromInput() ?? this.chosen())[which];
  }

  protected setPart(which: 'y' | 'm' | 'd', raw: string): void {
    const current = this.fromInput() ?? this.chosen();
    const next = { ...current, [which]: raw };
    this.chosen.set(next);
    this.valueChange.emit(
      next.y && next.m && next.d
        ? `${next.y}-${String(Number(next.m)).padStart(2, '0')}-${String(Number(next.d)).padStart(2, '0')}`
        : '');
  }
}
