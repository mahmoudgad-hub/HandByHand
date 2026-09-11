import { Injectable, inject } from '@angular/core';

import { HBH_CONFIG } from '../config/app-config';

/**
 * Every instant the portal receives is UTC and is compared as UTC. This
 * service is the only place a UTC instant becomes a local string, and it
 * always names the time zone explicitly: reading a date without a zone is
 * exactly the defect that silently moved this project's clocks by two hours.
 *
 * Digit shape follows the design: Arabic-Indic in dates, Latin in clock
 * times, money and identifiers.
 */
@Injectable({ providedIn: 'root' })
export class FormatService {
  private readonly config = inject(HBH_CONFIG);
  private readonly dateCache = new Map<string, Intl.DateTimeFormat>();
  private readonly numberCache = new Map<string, Intl.NumberFormat>();

  /** "الأربعاء، ٢ سبتمبر ٢٠٢٦" */
  fullDate(utc: string | Date): string {
    return this.dateFormat('full', {
      weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
    }).format(this.instant(utc));
  }

  /** "٢ سبتمبر" - the short form used inside list rows. */
  shortDate(utc: string | Date): string {
    return this.dateFormat('short', { day: 'numeric', month: 'long' })
      .format(this.instant(utc));
  }

  /**
   * "١٥ مارس ٢٠٢٠" - a full date with no weekday.
   *
   * For a date whose year matters and whose weekday does not: a birth date on
   * a printed card, where `fullDate` would spend a line saying which day of
   * the week a child was born on.
   */
  dayMonthYear(utc: string | Date): string {
    return this.dateFormat('dmy', { day: 'numeric', month: 'long', year: 'numeric' })
      .format(this.instant(utc));
  }

  /** "٦" - the day number in a row's date box. */
  dayNumber(utc: string | Date): string {
    return this.dateFormat('day', { day: 'numeric' }).format(this.instant(utc));
  }

  /** "سبتمبر" - the month under the day number. */
  monthName(utc: string | Date): string {
    return this.dateFormat('month', { month: 'long' }).format(this.instant(utc));
  }

  /**
   * The twelve month names, in order, for a picker.
   *
   * A birth date typed into a native date input is read in the BROWSER.s
   * locale, not the page.s - so a parent on an English Chrome sees
   * mm/dd/yyyy inside an Arabic form and 7 March is stored as 3 July, with
   * nothing to catch it. A named month cannot be misread, and the age the
   * whole plan is built on is derived from this one value.
   *
   * Built from Intl rather than a list in the bundle: the names are the
   * ones this locale already uses everywhere else on screen.
   */
  monthNames(): readonly string[] {
    const format = this.dateFormat("monthPick", { month: "long" }, "latn");
    return Array.from({ length: 12 }, (unused, index) =>
      format.format(new Date(Date.UTC(2001, index, 15, 12))));
  }

  /** "4:30 م" - Latin digits, and rendered inside a dir="ltr" element. */
  time(utc: string | Date): string {
    return this.dateFormat('time', { hour: 'numeric', minute: '2-digit' },
      this.config.numberNumbering).format(this.instant(utc));
  }

  /**
   * Which greeting fits right now. Read from the centre's clock, not the
   * visitor's: a guardian travelling abroad should still be greeted by the
   * time of day at the centre their child attends.
   */
  partOfDay(now: Date = new Date()): 'morning' | 'afternoon' | 'evening' {
    const hour = Number(
      this.dateFormat('hour', { hour: '2-digit', hour12: false }, 'latn')
        .format(now)
        .replace(/\D/g, ''),
    );
    // Before dawn is still "good evening" in Arabic, not "good morning".
    // A three-way split that starts the morning at midnight greets someone
    // signing in at half past midnight with the wrong half of the day.
    if (hour < 5) {
      return 'evening';
    }
    if (hour < 12) {
      return 'morning';
    }
    return hour < 17 ? 'afternoon' : 'evening';
  }

  /**
   * Whole years since a birth date, counted in the centre's zone.
   *
   * Derived, never received: the service sends `birth_date` and no age, so
   * there is no stored number that quietly goes stale on the child's next
   * birthday.
   */
  ageYears(birthDate: string | Date, now: Date = new Date()): number {
    const born = this.parts(this.instant(birthDate));
    const today = this.parts(now);
    let age = today.year - born.year;
    const hadBirthday = today.month > born.month
      || (today.month === born.month && today.day >= born.day);
    if (!hadBirthday) {
      age -= 1;
    }
    return Math.max(0, age);
  }

  /** True when the instant falls on today's date in the centre's time zone. */
  isToday(utc: string | Date): boolean {
    return this.dayKey(this.instant(utc)) === this.dayKey(new Date());
  }

  /** True when the instant fell on yesterday in the centre's time zone. */
  isYesterday(utc: string | Date): boolean {
    const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);
    return this.dayKey(this.instant(utc)) === this.dayKey(yesterday);
  }

  /** "1,750 ج.م" - whole amounts carry no decimals, as the invoices do. */
  money(amount: number, currency = this.config.currency): string {
    const whole = Number.isInteger(amount);
    const key = `money:${currency}:${whole}`;
    let format = this.numberCache.get(key);
    if (!format) {
      format = new Intl.NumberFormat(this.numberLocale(), {
        style: 'currency',
        currency,
        minimumFractionDigits: whole ? 0 : 2,
        maximumFractionDigits: whole ? 0 : 2,
      });
      this.numberCache.set(key, format);
    }
    return format.format(amount);
  }

  /** "78%" - a share already expressed 0..100, not 0..1. */
  percent(value: number): string {
    return `${this.number(value)}%`;
  }

  /** Latin digits: counters, ratios, measurements. */
  number(value: number): string {
    return this.numberFormat(this.config.numberNumbering).format(value);
  }

  /** Arabic-Indic digits: ages and counts that sit inside Arabic prose. */
  count(value: number): string {
    return this.numberFormat(this.config.dateNumbering).format(value);
  }

  /**
   * "00:12:41" - elapsed time of a live session, counted from a UTC start.
   * Never negative: a clock that has not started yet reads zero.
   */
  elapsed(sinceUtc: string | Date, now: Date = new Date()): string {
    const seconds = Math.max(
      0, Math.floor((now.getTime() - this.instant(sinceUtc).getTime()) / 1000));
    const parts = [
      Math.floor(seconds / 3600),
      Math.floor((seconds % 3600) / 60),
      seconds % 60,
    ];
    return parts.map((n) => String(n).padStart(2, '0')).join(':');
  }

  /**
   * The day the centre's calendar is on, as "2026-09-03".
   *
   * Used to seed a day picker. `new Date().toISOString().slice(0,10)` would
   * be the day in UTC, which after 22:00 in Cairo is already tomorrow - the
   * diary would open on the wrong day every evening.
   */
  today(now: Date = new Date()): string {
    const { year, month, day } = this.parts(now);
    return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  }

  /**
   * A wall-clock time the centre typed - "2026-09-03T10:00" - as the UTC
   * instant the service stores.
   *
   * The browser's own parser is no use here: `new Date("2026-09-03T10:00")`
   * reads that string in the BROWSER's zone, and a receptionist on a laptop
   * still set to UTC would book every appointment two or three hours off
   * without one thing on screen looking wrong. So the offset is measured in
   * the CENTRE's zone.
   *
   * Measured twice. The first pass finds the offset at roughly the right
   * instant; the second re-measures at that instant, which is what makes the
   * hour around a daylight-saving change come out right instead of an hour
   * adrift. Egypt observes summer time again since 2023, so this is a live
   * case and not a theoretical one.
   */
  toUtc(wallLocal: string): string {
    if (!wallLocal) {
      return '';
    }
    // Padded to seconds and read as though the wall time were UTC. This is
    // not the answer - it is the starting guess the offset is measured from.
    const naive = Date.parse(`${wallLocal.length === 16 ? `${wallLocal}:00` : wallLocal}Z`);
    if (Number.isNaN(naive)) {
      return '';
    }
    let guess = naive - this.zoneOffset(new Date(naive));
    guess = naive - this.zoneOffset(new Date(guess));
    return new Date(guess).toISOString();
  }

  /**
   * A UTC instant as the value a `datetime-local` input wants, on the
   * centre's clock. The inverse of toUtc, and the reason editing a booked
   * time shows the hour the centre booked rather than the browser's.
   */
  toWallLocal(utc: string | Date): string {
    const date = this.instant(utc);
    if (Number.isNaN(date.getTime())) {
      return '';
    }
    const shifted = new Date(date.getTime() + this.zoneOffset(date));
    return shifted.toISOString().slice(0, 16);
  }

  /**
   * How far the centre's clock is ahead of UTC at a given instant, in
   * milliseconds. Positive east of Greenwich.
   */
  private zoneOffset(at: Date): number {
    const parts = this.dateFormat('offset', {
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
    }, 'latn').formatToParts(at);
    const read = (type: Intl.DateTimeFormatPartTypes): number =>
      Number(parts.find((part) => part.type === type)?.value ?? '0');
    // Hour 24 appears for midnight in some locales; Date.UTC normalises it.
    const asIfUtc = Date.UTC(
      read('year'), read('month') - 1, read('day'),
      read('hour'), read('minute'), read('second'));
    return asIfUtc - Math.floor(at.getTime() / 1000) * 1000;
  }

  private instant(utc: string | Date): Date {
    return utc instanceof Date ? utc : new Date(utc);
  }

  /** Year-month-day in the centre's zone, for same-day comparisons. */
  private dayKey(date: Date): string {
    const { year, month, day } = this.parts(date);
    return `${year}-${month}-${day}`;
  }

  /**
   * The calendar parts of an instant as the centre's clock reads them.
   *
   * Read from formatToParts, not by splitting a formatted string: ar-EG
   * writes a date as DD/MM/YYYY, so slicing on "-" would have swapped the
   * day and the year and made every age wrong by decades.
   */
  private parts(date: Date): { year: number; month: number; day: number } {
    const parts = this.dateFormat('key',
      { year: 'numeric', month: '2-digit', day: '2-digit' }, 'latn')
      .formatToParts(date);
    const read = (type: Intl.DateTimeFormatPartTypes): number =>
      Number(parts.find((part) => part.type === type)?.value ?? '0');
    return { year: read('year'), month: read('month'), day: read('day') };
  }

  private dateFormat(
    key: string,
    options: Intl.DateTimeFormatOptions,
    numbering: string = this.config.dateNumbering,
  ): Intl.DateTimeFormat {
    const cacheKey = `${key}:${numbering}`;
    let format = this.dateCache.get(cacheKey);
    if (!format) {
      format = new Intl.DateTimeFormat(
        `${this.config.locale}-u-nu-${numbering}`,
        { ...options, timeZone: this.config.timeZone },
      );
      this.dateCache.set(cacheKey, format);
    }
    return format;
  }

  private numberFormat(numbering: string): Intl.NumberFormat {
    const key = `plain:${numbering}`;
    let format = this.numberCache.get(key);
    if (!format) {
      format = new Intl.NumberFormat(`${this.config.locale}-u-nu-${numbering}`);
      this.numberCache.set(key, format);
    }
    return format;
  }

  private numberLocale(): string {
    return `${this.config.locale}-u-nu-${this.config.numberNumbering}`;
  }
}
