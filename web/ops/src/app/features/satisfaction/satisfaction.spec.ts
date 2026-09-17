import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { FormatService } from '@hbh/shared/format/format.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { Satisfaction } from './satisfaction';

/**
 * The answers behind one survey's score.
 *
 * Two properties are worth holding down, and neither is the drawing.
 *
 * ONE REQUEST PER OPENING. hbh.nps_answers writes an audit row on every
 * successful call, because a list of what families said about their child's
 * therapy is a sensitive read. Filtering by band must therefore happen on
 * what was already fetched - a filter that re-asked would leave a trail
 * saying somebody opened a family's answers four times to look at them once.
 *
 * AND THE FILTER READS THE SERVICE'S BAND, NOT THE SCORE. The boundaries live
 * in hbh.nps_band (0156) and the counts in the table above are made of them.
 * A screen that re-derived "9 and up is a promoter" would disagree with the
 * number it sits under the moment anybody moved a boundary - and both would
 * look right.
 */
describe('Satisfaction answers', () => {
  let http: HttpTestingController;
  let screen: Satisfaction;

  const answer = (id: number, band: string | null, score: number | null) => ({
    response_id: id, survey_id: 7, respondent_name_ar: 'ولي أمر', mobile: '+201000000000',
    score, band, comment_ar: null, responded_at: '2026-09-14T10:00:00Z',
    skipped_flg: score === null,
  });

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(), provideHttpClientTesting(),
        { provide: HBH_CONFIG, useValue: { apiBaseUrl: '' } },
        { provide: I18nService, useValue: { translate: (key: string) => key, plural: (key: string) => key } },
        { provide: FormatService, useValue: { number: (n: number) => String(n), dayMonthYear: () => '' } },
      ],
    }).overrideComponent(Satisfaction, { set: { template: '', imports: [] } });

    http = TestBed.inject(HttpTestingController);
    screen = TestBed.createComponent(Satisfaction).componentInstance;
    http.expectOne('/api/v1/nps/summary').flush({ surveys: [], monthly: [] });
  });

  afterEach(() => http.verify());

  const open = () => {
    (screen as unknown as { openAnswers(row: Record<string, unknown>): void })
      .openAnswers({ survey_id: 7, name_ar: 'استبيان' });
    http.expectOne('/api/v1/nps/7/answers').flush({
      answers: [
        answer(1, 'PROMOTER', 10),
        answer(2, 'DETRACTOR', 2),
        // A dismissal: it is in the list so the count above adds up, and it
        // belongs to no band, so no band filter may claim it.
        answer(3, null, null),
      ],
      total: 3,
    });
  };

  it('asks once, and filters what it was given rather than asking again', () => {
    open();
    expect(screen['shownAnswers']().length).toBe(3);

    screen['band'].set('DETRACTOR');
    expect(screen['shownAnswers']().map((r) => r['response_id'])).toEqual([2]);

    screen['band'].set('PROMOTER');
    expect(screen['shownAnswers']().map((r) => r['response_id'])).toEqual([1]);

    // http.verify() in afterEach is the assertion that matters: not one more
    // request, and so not one more audit record.
  });

  it('counts each band from the band the service sent', () => {
    open();
    const filters = screen['bandFilters']();
    expect(filters.map((f) => [f.value, f.count])).toEqual([
      ['', 3], ['PROMOTER', 1], ['PASSIVE', 0], ['DETRACTOR', 1],
    ]);
  });

  it('draws a dismissal as a dismissal, with no band colour and no score', () => {
    open();
    const skipped = screen['answers']()[2];
    expect(screen['answerScore'](skipped)).toBe('');
    expect(screen['bandLabel'](skipped)).toBe('nps.skippedOne');
    expect(screen['bandColour'](skipped)).not.toContain('success');
  });

  it('leaves a masked column empty rather than printing null at somebody', () => {
    open();
    // The service returns null for a name it will not give out. The screen
    // must render nothing there - "null" in the name column is worse than a
    // blank, because it reads as a defect rather than as a withheld value.
    expect(screen['field']({ respondent_name_ar: null }, 'respondent_name_ar')).toBe('');
    expect(screen['field']({}, 'mobile')).toBe('');
  });
});
