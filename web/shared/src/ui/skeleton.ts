import { ChangeDetectionStrategy, Component, input } from '@angular/core';

/**
 * Placeholder blocks while a screen loads. Shaped like the rows that will
 * replace them, so the layout does not jump when the answer arrives.
 */
@Component({
  selector: 'hbh-skeleton',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="stack" aria-hidden="true" aria-busy="true">
      @for (row of placeholders(); track $index) {
        <div class="skel" [class.skel--row]="shape() === 'row'"
             [class.skel--card]="shape() === 'card'"></div>
      }
    </div>
  `,
})
export class Skeleton {
  readonly count = input(3);
  readonly shape = input<'row' | 'card'>('row');

  protected placeholders(): readonly number[] {
    return Array.from({ length: this.count() }, (unused, index) => index);
  }
}
