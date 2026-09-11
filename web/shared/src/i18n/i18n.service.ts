import { Injectable, computed, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';

import { HBH_CONFIG } from '../config/app-config';
import { FormatService } from '../format/format.service';

/** A flat key/value bundle: "screen.thing" -> the string a parent reads. */
export type Bundle = Readonly<Record<string, string>>;

export type Lang = 'ar' | 'en';

/**
 * No user-facing string is written inside a template. Templates name a key,
 * this service resolves it from a bundle under assets/i18n. Arabic is the
 * first language, English is a later layer over the same keys.
 *
 * A missing key returns the key itself rather than an empty string: a gap in
 * the bundle then shows up on screen instead of leaving a blank the eye
 * slides past.
 */
@Injectable({ providedIn: 'root' })
export class I18nService {
  private readonly http = inject(HttpClient);
  private readonly config = inject(HBH_CONFIG);
  private readonly format = inject(FormatService);

  private readonly bundle = signal<Bundle>({});
  private readonly lang = signal<Lang>('ar');

  readonly currentLang = this.lang.asReadonly();
  readonly direction = computed<'rtl' | 'ltr'>(() =>
    this.lang() === 'ar' ? 'rtl' : this.config.direction);

  /**
   * Called once before the first screen renders; nothing paints untranslated.
   *
   * Arabic is loaded UNDERNEATH any other language, and the requested one is
   * laid over it. That makes a second bundle addable a screen at a time: a
   * key it has not reached yet falls through to Arabic, which is a word
   * somebody can read, instead of printing "billing.addLineNote" - and a raw
   * key on screen is the failure this project has already shipped twice.
   *
   * Arabic is also the only language this centre needs today. The mechanism
   * exists so that adding another is translation work and not engineering
   * work, and so that a partial translation is safe to ship.
   */
  async load(lang: Lang): Promise<void> {
    const base = await firstValueFrom(this.http.get<Bundle>('assets/i18n/ar.json'));
    const bundle = lang === 'ar'
      ? base
      : { ...base, ...await firstValueFrom(this.http.get<Bundle>(`assets/i18n/${lang}.json`)) };

    this.bundle.set(bundle);
    this.lang.set(lang);
    document.documentElement.lang = lang;
    document.documentElement.dir = this.direction();
  }

  /**
   * Resolve a key. `params` fills `{name}` placeholders; a value that is not
   * supplied is left in place, so the missing piece is visible in testing.
   */
  translate(key: string, params?: Readonly<Record<string, string | number>>): string {
    const template = this.bundle()[key];
    if (template === undefined) {
      return key;
    }
    if (!params) {
      return template;
    }
    return template.replace(/\{(\w+)\}/g, (whole, name: string) =>
      Object.prototype.hasOwnProperty.call(params, name) ? String(params[name]) : whole);
  }

  /**
   * Resolve a counted phrase.
   *
   * Arabic does not have one plural. It has six categories, and a centre for
   * children hits the awkward ones every day: a one-year-old, a two-year-old,
   * three to ten years, then eleven and up - each takes a different form. A
   * single "{count} سنوات" string prints "١ سنوات", which is simply wrong.
   *
   * `Intl.PluralRules` knows the categories for whatever locale is configured,
   * so the bundle carries `child.age.one`, `.two`, `.few`, `.many` and the
   * code picks between them without knowing any grammar itself. A language
   * with one plural just supplies `.other` and nothing here changes.
   */
  plural(
    baseKey: string,
    count: number,
    params?: Readonly<Record<string, string | number>>,
  ): string {
    const category = new Intl.PluralRules(this.locale()).select(count);
    const key = this.bundle()[`${baseKey}.${category}`] !== undefined
      ? `${baseKey}.${category}`
      : `${baseKey}.other`;
    // The category is chosen from the real number; the digits printed are
    // Arabic-Indic, because these phrases sit inside Arabic prose. A caller
    // that needs another shape passes its own `count` in params.
    return this.translate(key, { count: this.format.count(count), ...params });
  }

  /**
   * Join values for display. The separator is a translated string, because
   * Arabic uses its own comma and a template must not carry punctuation the
   * next language would get wrong.
   */
  list(items: readonly string[]): string {
    return items.join(this.translate('format.listSeparator'));
  }

  private locale(): string {
    return this.lang() === 'ar' ? this.config.locale : this.lang();
  }
}
