import { Pipe, PipeTransform, inject } from '@angular/core';

import { I18nService } from '../i18n/i18n.service';
import { FormatService } from './format.service';

/**
 * "٦ سنوات" from a date of birth.
 *
 * Two things happen here that must not happen in a template. The age is
 * derived from the birth date rather than read from a stored number, and the
 * phrase is chosen by plural category - Arabic says "سنة واحدة" at one,
 * "سنتان" at two and "{n} سنوات" from three, and a single string prints
 * "١ سنوات" for a one-year-old.
 */
@Pipe({ name: 'hbhAge', pure: false })
export class HbhAgePipe implements PipeTransform {
  private readonly format = inject(FormatService);
  private readonly i18n = inject(I18nService);

  transform(birthDate: string | Date | null | undefined): string {
    if (!birthDate) {
      return '';
    }
    return this.i18n.plural('child.age', this.format.ageYears(birthDate));
  }
}

/**
 * A counted phrase, in the form the language actually uses.
 *
 * `{{ goals.length | hbhPlural: 'progress.goalCount' }}` reads
 * "هدف واحد" · "هدفان" · "٣ أهداف" · "١١ هدفًا" - which one is decided by
 * `Intl.PluralRules`, not by the template and not by a component.
 */
@Pipe({ name: 'hbhPlural', pure: false })
export class HbhPluralPipe implements PipeTransform {
  private readonly i18n = inject(I18nService);

  transform(
    count: number | null | undefined,
    baseKey: string,
    params?: Readonly<Record<string, string | number>>,
  ): string {
    return this.i18n.plural(baseKey, count ?? 0, params);
  }
}

/** "الأربعاء، ٢ سبتمبر ٢٠٢٦" from a UTC instant. */
@Pipe({ name: 'hbhDate' })
export class HbhDatePipe implements PipeTransform {
  private readonly format = inject(FormatService);
  transform(utc: string | Date | null | undefined): string {
    return utc ? this.format.fullDate(utc) : '';
  }
}

/** "٢ سبتمبر" from a UTC instant. */
@Pipe({ name: 'hbhShortDate' })
export class HbhShortDatePipe implements PipeTransform {
  private readonly format = inject(FormatService);
  transform(utc: string | Date | null | undefined): string {
    return utc ? this.format.shortDate(utc) : '';
  }
}

/** "4:30 م" from a UTC instant. Render inside dir="ltr". */
@Pipe({ name: 'hbhTime' })
export class HbhTimePipe implements PipeTransform {
  private readonly format = inject(FormatService);
  transform(utc: string | Date | null | undefined): string {
    return utc ? this.format.time(utc) : '';
  }
}

/** "1,750 ج.م" - currency comes from the centre, never from the component. */
@Pipe({ name: 'hbhMoney' })
export class HbhMoneyPipe implements PipeTransform {
  private readonly format = inject(FormatService);
  transform(amount: number | null | undefined, currency?: string): string {
    return amount === null || amount === undefined
      ? '' : this.format.money(amount, currency);
  }
}

/** Latin digits: counters, ratios, measurements. */
@Pipe({ name: 'hbhNum' })
export class HbhNumberPipe implements PipeTransform {
  private readonly format = inject(FormatService);
  transform(value: number | null | undefined): string {
    return value === null || value === undefined ? '' : this.format.number(value);
  }
}

/** Arabic-Indic digits: ages and counts inside Arabic prose. */
@Pipe({ name: 'hbhCount' })
export class HbhCountPipe implements PipeTransform {
  private readonly format = inject(FormatService);
  transform(value: number | null | undefined): string {
    return value === null || value === undefined ? '' : this.format.count(value);
  }
}
