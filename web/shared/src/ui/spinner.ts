import { ChangeDetectionStrategy, Component, input } from '@angular/core';

/**
 * Work in progress, in the centre's own three colours.
 *
 * WHEN TO USE THIS AND WHEN NOT TO. A skeleton is better for a screen that is
 * loading its rows: it shows the shape of what is coming and the page does
 * not jump when it arrives. A spinner is for work with no shape - a button
 * that was pressed, a save, a stream being opened - where there is nothing to
 * outline because the answer is a yes or a no.
 *
 * The ring is drawn in teal, green and coral - the three sampled from the
 * logo mark, in that order - so it reads as this product's rather than as a
 * default borrowed from a framework.
 *
 * IT RESPECTS `prefers-reduced-motion`. A spinner is the single most common
 * thing on a page for somebody who gets migraines or motion sickness from
 * animation, and this one is on a screen used by families in a clinical
 * setting. Reduced motion turns it into a still ring that still says "busy".
 */
@Component({
  selector: 'hbh-spinner',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <span class="hbh-spin"
          [class.hbh-spin--sm]="size() === 'sm'"
          [class.hbh-spin--lg]="size() === 'lg'"
          [attr.role]="label() ? 'status' : null"
          [attr.aria-label]="label() || null"
          [attr.aria-hidden]="label() ? null : 'true'">
      <span class="hbh-spin__r"></span>
    </span>
    @if (label()) {
      <span class="hbh-spin__t">{{ label() }}</span>
    }
  `,
  styles: [':host { display: inline-flex; align-items: center; gap: 9px; }'],
})
export class Spinner {
  readonly size = input<'sm' | 'md' | 'lg'>('md');

  /**
   * What is being waited for, in words.
   *
   * When set the spinner is announced; when not it is hidden from assistive
   * technology entirely. A spinning shape with no name is noise to a screen
   * reader, and "loading, loading, loading" is worse than silence.
   */
  readonly label = input<string>('');
}
