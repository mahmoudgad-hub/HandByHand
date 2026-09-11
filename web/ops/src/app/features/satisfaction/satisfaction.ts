import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { HttpClient } from '@angular/common/http';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { FormatService } from '@hbh/shared/format/format.service';
import { Icon, IconName } from '@hbh/shared/icon/icon';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';

import { Row } from '../../core/api/ops-api';

const text = (row: Row, key: string): string => {
  const value = row[key];
  return value === null || value === undefined ? '' : String(value);
};

const num = (row: Row, key: string): number => Number(text(row, key) || 0);

/** One tile above the charts. */
interface Tile {
  readonly key: string;
  readonly labelKey: string;
  readonly icon: IconName;
  readonly tone: string;
  readonly value: string;
  /** The line under the number - the basis, or why there is a dash. */
  readonly foot?: string;
}

/** One slice of the doughnut. */
interface Slice {
  readonly key: string;
  readonly labelKey: string;
  readonly count: number;
  readonly share: number;
  readonly colour: string;
  /** stroke-dasharray and offset, in percent units of the circumference. */
  readonly dash: string;
  readonly offset: number;
}

/**
 * What the families answered.
 *
 * The centre could already CREATE satisfaction surveys - they are a resource
 * on the catalogue screen - and could not read a single answer. Families were
 * being asked a question nobody could hear the reply to, which is worse than
 * not asking: it spends a family's goodwill and returns nothing.
 *
 * hbh.v_nps_summary has done the arithmetic for a long time and no screen
 * called it.
 *
 * NPS AND THE MEAN ARE DIFFERENT NUMBERS AND BOTH ARE SHOWN.
 * The store's own comment records that in one acceptance run the NPS was 25
 * while the mean was 7.25. They answer different questions - the NPS is
 * promoters minus detractors, the mean is the average score - and showing one
 * alone invites somebody to compute the other from the counts beside it, which
 * is how one number quietly becomes two that disagree.
 *
 * WHAT THIS SCREEN ADDS UP, AND WHAT IT REFUSES TO.
 *
 * Counts are additive: two surveys' promoters really are that many promoters,
 * so the tiles total answered, skipped, promoters, passives and detractors
 * across every survey.
 *
 * THE INDEX AND THE MEAN ARE NOT. An average of two surveys' averages is not
 * the average of their answers unless both were answered the same number of
 * times, and averaging two NPS figures is not an NPS of anything. So both come
 * STRAIGHT FROM THE VIEW and are shown in the tiles only while there is
 * exactly one survey. With more than one the tile shows a dash and says the
 * figures are per survey, in the table. A plausible wrong number here would
 * outlive every correction.
 *
 * AND A BAND NEVER APPEARS WITHOUT ITS SAMPLE. "Excellent - satisfaction is
 * high" under a nine is true of the nine and says nothing about the centre
 * when one family has replied. The count it rests on is printed with it,
 * always, rather than a hidden threshold that decides for the reader.
 */
@Component({
  selector: 'hbh-satisfaction',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon, TranslatePipe, Skeleton, EmptyState, ErrorNote],
  templateUrl: './satisfaction.html',
  styleUrl: './satisfaction.css',
})
export class Satisfaction {
  private readonly http = inject(HttpClient);
  private readonly base = `${inject(HBH_CONFIG).apiBaseUrl}/api/v1/nps`;
  private readonly destroyRef = inject(DestroyRef);
  private readonly i18n = inject(I18nService);
  protected readonly format = inject(FormatService);

  protected readonly rows = signal<readonly Row[]>([]);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);

  /** The one survey, when there is exactly one. Null otherwise. */
  private readonly single = computed<Row | null>(() => {
    const list = this.rows();
    return list.length === 1 ? list[0] : null;
  });

  private readonly totals = computed(() => {
    const list = this.rows();
    const sum = (key: string) => list.reduce((run, row) => run + num(row, key), 0);
    return {
      answered: sum('answered_cnt'),
      skipped: sum('skipped_cnt'),
      promoters: sum('promoters'),
      passives: sum('passives'),
      detractors: sum('detractors'),
    };
  });

  /** The most recent reply across every survey, or '' if none. */
  private readonly lastResponseAt = computed(() => {
    const stamps = this.rows()
      .map((row) => text(row, 'last_response_at'))
      .filter((at) => at !== '');
    // Sorted as strings: these are ISO-8601 in UTC, where lexical order and
    // chronological order are the same thing.
    return stamps.sort().at(-1) ?? '';
  });

  protected readonly answered = computed(() => this.totals().answered);

  /** The mean as the view wrote it, or a dash. Never averaged here. */
  protected readonly meanText = computed(() => {
    const one = this.single();
    return one ? text(one, 'mean_score') || '—' : '—';
  });

  /**
   * "based on N answers", printed under every band.
   *
   * The reference this screen was drawn from announced "Excellent - family
   * satisfaction is high" beside a single reply. The band was not wrong; it
   * was unaccompanied, which let a nine from one family read as a statement
   * about the centre. So the count travels with the word, always.
   */
  protected readonly basisText = computed(() =>
    this.i18n.plural('nps.basis', this.answered()));

  protected readonly tiles = computed<readonly Tile[]>(() => {
    const t = this.totals();
    const one = this.single();
    const dash = '—';
    // Only meaningful for a single survey - see the class comment.
    const perSurvey = this.rows().length > 1
      ? this.i18n.translate('nps.perSurvey') : undefined;

    return [
      { key: 'skipped', labelKey: 'nps.skipped', icon: 'ic-x-circle', tone: 'red', value: this.format.count(t.skipped) },
      {
        key: 'answered', labelKey: 'nps.answered', icon: 'ic-users', tone: 'blue',
        value: this.format.count(t.answered),
        foot: t.skipped > 0
          ? this.i18n.translate('nps.skippedFoot', { count: this.format.count(t.skipped) })
          : undefined,
      },
      {
        key: 'promoters', labelKey: 'nps.promoters', icon: 'ic-check-circle',
        tone: 'green', value: this.format.count(t.promoters),
        foot: this.shareFoot(t.promoters, t.answered),
      },
      {
        key: 'passives', labelKey: 'nps.passives', icon: 'ic-info', tone: 'amber',
        value: this.format.count(t.passives),
        foot: this.shareFoot(t.passives, t.answered),
      },
      {
        key: 'detractors', labelKey: 'nps.detractors', icon: 'ic-x-circle',
        tone: 'red', value: this.format.count(t.detractors),
        foot: this.shareFoot(t.detractors, t.answered),
      },
      {
        key: 'nps', labelKey: 'nps.score', icon: 'ic-chart', tone: 'navy',
        value: one ? text(one, 'nps') || dash : dash,
        foot: perSurvey ?? this.i18n.translate('nps.outOf100'),
      },
      {
        key: 'mean', labelKey: 'nps.mean', icon: 'ic-star', tone: 'purple',
        value: one ? text(one, 'mean_score') || dash : dash,
        foot: perSurvey ?? this.i18n.translate('nps.outOf10'),
      },
      {
        key: 'last', labelKey: 'nps.lastResponse', icon: 'ic-calendar', tone: 'navy',
        // A dash when nobody has answered, never a fabricated date.
        //
        // The date reads "٥ سبتمبر", and ٥ is ARABIC-INDIC FIVE (U+0665),
        // which looks like a Latin zero at a glance - it was read as "0
        // September" twice while this screen was being built, once by the
        // owner and once by me. It is correct, and it is correct by the
        // project's own rule: digits inside prose are Arabic-Indic, digits
        // in a left-to-right box are Latin. Worth knowing before somebody
        // "fixes" it into a bug.
        value: this.lastResponseAt() ? this.format.shortDate(this.lastResponseAt()) : dash,
      },
    ];
  });

  /**
   * The doughnut, as three arcs of one circle.
   *
   * Drawn by hand rather than with a charting library: the project's rule is
   * one charting library, chosen once and written down, and this console has
   * neither a library nor that decision recorded. Two arcs and a needle are
   * not worth spending it on, and a dependency added quietly is how the
   * choice gets made by whoever needed a pie first.
   *
   * The denominator is ANSWERED, and only answered. A share of anything else
   * is a different question wearing the same percent sign.
   */
  protected readonly slices = computed<readonly Slice[]>(() => {
    const t = this.totals();
    const total = t.answered;
    const parts = [
      { key: 'promoters', labelKey: 'nps.promoters', count: t.promoters, colour: 'var(--hbh-success)' },
      { key: 'passives', labelKey: 'nps.passives', count: t.passives, colour: 'var(--hbh-progress)' },
      { key: 'detractors', labelKey: 'nps.detractors', count: t.detractors, colour: 'var(--hbh-danger)' },
    ];

    let run = 0;
    return parts.map((part) => {
      const share = total > 0 ? (part.count / total) * 100 : 0;
      const slice: Slice = {
        ...part, share,
        dash: `${share} ${100 - share}`,
        // Negative, because the circle is drawn anticlockwise from the top by
        // default and the offset walks it back to where this arc begins.
        offset: -run,
      };
      run += share;
      return slice;
    });
  });

  /** The gauge sweep, as a fraction of a half circle. 0 when nobody replied. */
  protected readonly meanFraction = computed(() => {
    const one = this.single();
    if (!one || this.totals().answered === 0) {
      return 0;
    }
    const mean = num(one, 'mean_score');
    return Math.max(0, Math.min(1, mean / 10));
  });

  /**
   * The band, and it is never shown without the count beneath it.
   *
   * The thresholds are the standard reading of a 0-10 satisfaction score, and
   * they are here rather than in the database because they describe a WORD ON
   * A SCREEN, not a rule the centre operates by. Nothing is decided from them.
   */
  protected readonly meanBandKey = computed(() => {
    const one = this.single();
    if (!one || this.totals().answered === 0) {
      return '';
    }
    const mean = num(one, 'mean_score');
    if (mean >= 9) { return 'nps.band.excellent'; }
    if (mean >= 7) { return 'nps.band.good'; }
    if (mean >= 5) { return 'nps.band.fair'; }
    return 'nps.band.poor';
  });

  protected readonly columns: readonly {
    readonly key: string;
    readonly labelKey: string;
    readonly read: (row: Row) => string;
    readonly ltr?: boolean;
  }[] = [
    { key: 'name', labelKey: 'field.name', read: (row) => text(row, 'name_ar') },
    {
      key: 'answered', labelKey: 'nps.answered', ltr: true,
      read: (row) => this.format.number(num(row, 'answered_cnt')),
    },
    {
      key: 'skipped', labelKey: 'nps.skipped', ltr: true,
      read: (row) => this.format.number(num(row, 'skipped_cnt')),
    },
    {
      key: 'promoters', labelKey: 'nps.promoters', ltr: true,
      read: (row) => this.format.number(num(row, 'promoters')),
    },
    {
      key: 'passives', labelKey: 'nps.passives', ltr: true,
      read: (row) => this.format.number(num(row, 'passives')),
    },
    {
      key: 'detractors', labelKey: 'nps.detractors', ltr: true,
      read: (row) => this.format.number(num(row, 'detractors')),
    },
    // Straight from the view. An unanswered survey has no score, and a zero
    // would read as "neutral" when the truth is "nobody has replied".
    { key: 'nps', labelKey: 'nps.score', ltr: true, read: (row) => text(row, 'nps') },
    { key: 'mean', labelKey: 'nps.mean', ltr: true, read: (row) => text(row, 'mean_score') },
    {
      key: 'last', labelKey: 'nps.lastResponse',
      read: (row) => {
        const at = text(row, 'last_response_at');
        return at ? this.format.shortDate(at) : '';
      },
    },
  ];

  protected readonly monthly = signal<readonly Row[]>([]);
  protected readonly trend = computed(() => this.monthly().map((r,i,all) => ({x: all.length === 1 ? 200 : 42+i*316/(all.length-1), y: 155-Number(r['mean_score'])*13, score: Number(r['mean_score']), month: String(r['month'])})));
  protected readonly trendLine = computed(() => this.trend().map(p => p.x+','+p.y).join(' '));
  constructor() {
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    this.http
      .get<{ surveys?: readonly Row[]; monthly?: readonly Row[] }>(`${this.base}/summary`)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (body) => {
          this.rows.set(body.surveys ?? []);
          this.monthly.set(body.monthly ?? []);
          this.loading.set(false);
        },
        error: () => {
          this.loading.set(false);
          this.failed.set(true);
        },
      });
  }

  protected cell(row: Row, column: { readonly read: (row: Row) => string }): string {
    return column.read(row);
  }

  protected rowKey(row: Row, index: number): string {
    return text(row, 'survey_id') || String(index);
  }

  protected sharePercent(slice: Slice): string {
    return this.format.percent(slice.share);
  }

  /**
   * A share of the answers, or nothing at all.
   *
   * Nothing when there are no answers: 0% of nothing is not zero per cent, it
   * is undefined, and printing "0%" says the families were asked and none of
   * them are promoters.
   */
  private shareFoot(part: number, total: number): string | undefined {
    if (total <= 0) {
      return undefined;
    }
    return this.format.percent((part / total) * 100);
  }

}
