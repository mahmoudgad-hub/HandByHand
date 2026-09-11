import { ChangeDetectionStrategy, Component, input } from '@angular/core';

import { Icon, IconName } from '../icon/icon';

/**
 * Nothing to show, said plainly. The strings arrive already translated - this
 * component holds no text of its own.
 */
@Component({
  selector: 'hbh-empty-state',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon],
  template: `
    <div class="state">
      <hbh-icon [name]="icon()" />
      <span class="state__t">{{ title() }}</span>
      @if (note()) {
        <span>{{ note() }}</span>
      }
    </div>
  `,
})
export class EmptyState {
  readonly icon = input<IconName>('ic-info');
  readonly title = input.required<string>();
  readonly note = input<string>('');
}
