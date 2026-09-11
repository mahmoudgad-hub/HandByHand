import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { fromEvent, merge } from 'rxjs';

import { TranslatePipe } from '../i18n/translate.pipe';
import { Icon } from '../icon/icon';

/**
 * A bar that says the device is offline.
 *
 * This portal is opened on a phone in a waiting room and on the road. Without
 * this, a lost connection looks like the centre's fault: every screen shows
 * "could not load" and a parent has no way to tell a dead network from a dead
 * service.
 *
 * `navigator.onLine` is only a hint - it reports the network interface, not
 * whether anything is reachable - so this never blocks a request. It only
 * offers an explanation while requests are failing anyway.
 */
@Component({
  selector: 'hbh-connectivity',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon, TranslatePipe],
  template: `
    @if (offline()) {
      <div class="netbar" role="status" aria-live="polite">
        <hbh-icon name="ic-warn" />
        <span>{{ 'error.offline' | t }}</span>
      </div>
    }
  `,
})
export class Connectivity {
  protected readonly offline = signal(!navigator.onLine);

  constructor() {
    merge(fromEvent(window, 'online'), fromEvent(window, 'offline'))
      .pipe(takeUntilDestroyed())
      .subscribe(() => this.offline.set(!navigator.onLine));
  }
}
