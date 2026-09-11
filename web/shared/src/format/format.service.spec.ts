import { TestBed } from '@angular/core/testing';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '../config/app-config';
import { FormatService } from './format.service';

/**
 * These guard the one rule that has already cost this project a release: an
 * instant is UTC everywhere, and becomes local only at the moment it is
 * printed. A regression here does not throw - it quietly shifts every time on
 * every screen by the zone offset, which is exactly how the defect hid last
 * time.
 */
describe('FormatService', () => {
  let format: FormatService;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        { provide: HBH_CONFIG, useValue: DEFAULT_HBH_CONFIG },
        FormatService,
      ],
    });
    format = TestBed.inject(FormatService);
  });

  it('renders a UTC instant in the centre time zone, not the machine one', () => {
    // 13:30 UTC on 2 September 2026. Cairo is on summer time that day, so the
    // centre reads 16:30 - half past four in the afternoon.
    const rendered = format.time('2026-09-02T13:30:00Z');

    expect(rendered).toContain('4:30');
    // Whatever the test machine's own zone is, the answer must not be 13:30.
    expect(rendered).not.toContain('1:30');
  });

  it('keeps the same calendar day for two instants inside one Cairo day', () => {
    // 22:00 UTC is already the next day in some zones and not in Cairo, which
    // is the kind of edge a naive local-time comparison gets wrong.
    const evening = format.dayNumber('2026-09-02T19:00:00Z');
    const earlier = format.dayNumber('2026-09-02T06:00:00Z');

    expect(evening).toBe(earlier);
  });

  it('never counts elapsed time backwards', () => {
    const future = new Date(Date.now() + 60_000).toISOString();

    expect(format.elapsed(future)).toBe('00:00:00');
  });

  it('counts elapsed time as hours, minutes and seconds', () => {
    const now = new Date('2026-09-02T13:42:41Z');

    expect(format.elapsed('2026-09-02T13:30:00Z', now)).toBe('00:12:41');
  });

  it('counts age in whole years, in the centre time zone', () => {
    const now = new Date('2026-09-03T09:00:00Z');

    expect(format.ageYears('2020-03-15', now)).toBe(6);
  });

  it('does not add the year until the birthday has passed', () => {
    const now = new Date('2026-09-03T09:00:00Z');

    // Birthday is later this month: still five, not six.
    expect(format.ageYears('2020-09-30', now)).toBe(5);
    // Birthday is today: six.
    expect(format.ageYears('2020-09-03', now)).toBe(6);
  });

  it('never reports a negative age', () => {
    const now = new Date('2026-09-03T09:00:00Z');

    expect(format.ageYears('2027-01-01', now)).toBe(0);
  });

  it('prints a whole amount without decimals', () => {
    const rendered = format.money(1750, 'EGP');

    expect(rendered).toContain('1,750');
    expect(rendered).not.toContain('1,750.00');
  });

  /**
   * The booking form collects a wall-clock time and the service stores an
   * instant. This is the conversion between them, and it is the one place a
   * silent two- or three-hour error can enter a booking without anything on
   * screen looking wrong.
   */
  it('reads a typed time on the CENTRE clock, not the browser one', () => {
    // Ten in the morning in Cairo in September is summer time, UTC+3.
    expect(format.toUtc('2026-09-03T10:00')).toBe('2026-09-03T07:00:00.000Z');
  });

  it('reads a typed time in winter, when the offset is different', () => {
    // Same wall clock in January is UTC+2, so the instant is an hour later.
    // A single fixed offset would get one of these two wrong.
    expect(format.toUtc('2026-01-15T10:00')).toBe('2026-01-15T08:00:00.000Z');
  });

  it('round-trips an instant back to the value a picker shows', () => {
    expect(format.toWallLocal('2026-09-03T07:00:00Z')).toBe('2026-09-03T10:00');
  });

  it('opens the diary on the centre day, not the UTC one', () => {
    // 21:30 UTC is already tomorrow in Cairo. Taking the day from an ISO
    // string would open the diary on the wrong day every evening - during
    // the hours reception is still working.
    expect(format.today(new Date('2026-09-03T21:30:00Z'))).toBe('2026-09-04');
  });
});
