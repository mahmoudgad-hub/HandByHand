import { Pipe, PipeTransform, inject } from '@angular/core';

import { I18nService } from './i18n.service';

/**
 * `{{ 'home.title' | t }}`, and with placeholders
 * `{{ 'billing.due' | t: { amount: due } }}`.
 *
 * Impure because the bundle can be swapped at runtime when the language
 * changes. Every screen is OnPush, so this runs on the few cycles that a
 * real interaction triggers, not on a timer.
 */
@Pipe({ name: 't', pure: false })
export class TranslatePipe implements PipeTransform {
  private readonly i18n = inject(I18nService);

  transform(key: string, params?: Readonly<Record<string, string | number>>): string {
    return this.i18n.translate(key, params);
  }
}
