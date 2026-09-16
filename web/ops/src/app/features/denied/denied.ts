import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';

import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';

/**
 * A screen this account may not open.
 *
 * Drawn instead of the page rather than on top of it. It says the attempt is
 * recorded, because it is - the server writes a DENY - and saying so is
 * fairer than letting someone wonder. It also names the permission the guard
 * asked for: the guard has always passed it in `?need=`, and a refusal that
 * says which right is missing is one the person can actually ask for.
 */
@Component({
  selector: 'hbh-denied',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Icon, TranslatePipe],
  template: `
    <div class="hbh-denied">
      <hbh-icon name="ic-shield" />
      <p class="hbh-denied__t">{{ 'denied.title' | t }}</p>
      <p class="hbh-denied__s">{{ 'denied.note' | t }}</p>
      @if (need) {
        <p class="hbh-denied__s">{{ 'denied.need' | t }} <code dir="ltr">{{ need }}</code></p>
      }
      <a class="hbh-btn hbh-btn--ghost" routerLink="/dashboard">
        {{ 'denied.back' | t }}
      </a>
    </div>
  `,
})
export class Denied {
  protected readonly need = inject(ActivatedRoute).snapshot.queryParamMap.get('need');
}
