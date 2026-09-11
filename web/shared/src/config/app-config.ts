import { InjectionToken } from '@angular/core';

/**
 * Every locale-shaped decision the portal makes is a parameter, never a
 * literal in a component. Egypt is the first centre, not the only shape the
 * code may take: currency, time zone, weekend and phone shape all live here.
 *
 * The values below are development defaults. Once the API is up, the centre
 * row is the source of truth and these are replaced at bootstrap by whatever
 * `GET /api/v1/me/context` returns - the portal must not decide them itself.
 */
export interface AppConfig {
  /** Base URL of the Go service. Empty string means same origin. */
  readonly apiBaseUrl: string;

  /** True while the API is not built yet: read screens run on fixtures. */
  readonly useFixtures: boolean;

  readonly locale: string;
  readonly direction: 'rtl' | 'ltr';

  /**
   * Display time zone. Every instant crosses the wire as UTC and is compared
   * as UTC; this is applied for rendering only, and nowhere else.
   */
  readonly timeZone: string;

  readonly currency: string;

  /**
   * Digit shapes. The design uses Arabic-Indic digits in dates and Latin
   * digits in clock times, money and identifiers, which is what the centre's
   * own printed material does.
   */
  readonly dateNumbering: string;
  readonly numberNumbering: string;

  /** Mobile shape accepted at sign-in, as a source-of-truth pattern. */
  readonly phonePattern: string;
  readonly phoneCountryCode: string;

  /**
   * The centre this deployment belongs to, as its short code.
   *
   * Needed by exactly one call: the enrolment form, which is the only
   * unauthenticated write in the service and therefore the only place where
   * the centre cannot be derived from the caller. Everywhere else the server
   * knows which centre is asking and the client must not say.
   *
   * An unknown code is refused without saying so - answering "no such centre"
   * would let anyone enumerate the centres by trying codes.
   */
  readonly centerCode: string;

  /** Length of the one-time code the server issues. */
  readonly otpLength: number;

  /**
   * Sign-in shortcuts for development, shown as buttons on the staff login.
   *
   * THIS LIST MUST BE EMPTY IN PRODUCTION. It holds working credentials, and
   * anything here is readable by anyone who opens the page - it is a
   * convenience for demonstrating how the console changes by role, not a
   * feature. The production config omits the field entirely, and the login
   * screen renders nothing when the list is empty.
   */
  readonly devAccounts: readonly DevAccount[];
}

/** One development sign-in shortcut. */
export interface DevAccount {
  readonly username: string;
  readonly password: string;
  /** The role it signs in as, for the button's label. */
  readonly roleKey: string;
  /**
   * When set, the button is shown disabled with this reason. A role the
   * centre has but no development account for is more useful said than
   * hidden - it tells whoever is testing what they cannot try yet.
   */
  readonly unavailableKey?: string;
}

export const HBH_CONFIG = new InjectionToken<AppConfig>('HBH_CONFIG');

export const DEFAULT_HBH_CONFIG: AppConfig = {
  apiBaseUrl: '',
  useFixtures: true,
  locale: 'ar-EG',
  direction: 'rtl',
  timeZone: 'Africa/Cairo',
  currency: 'EGP',
  dateNumbering: 'arab',
  numberNumbering: 'latn',
  phonePattern: '^01[0-9]{9}$',
  phoneCountryCode: '+20',
  centerCode: 'HBH',
  otpLength: 6,

  // Empty by default. Only the development config fills it, and only for
  // the console - the parent portal never shows sign-in shortcuts.
  devAccounts: [],
};
