import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import {
  ActivatedRoute, NavigationEnd, Router, RouterLink, RouterOutlet,
} from '@angular/router';
import { filter } from 'rxjs';

import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { NavEntry, OPS_NAV } from './nav';

/**
 * Sidebar, page header, content. The console's shell.
 *
 * It draws the menu from the permissions the server returned. That is a
 * convenience - it keeps a receptionist from clicking into a screen they
 * cannot fill - and it is not a control. The refusal lives in the policy
 * under the query, and it happens whether or not the entry was drawn.
 */
@Component({
  selector: 'hbh-shell',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterOutlet, RouterLink, Icon, TranslatePipe],
  templateUrl: './shell.html',
})
export class Shell {
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  protected readonly auth = inject(OpsAuthService);

  private readonly activeKey = signal<string>(this.readKey());
  protected readonly active = this.activeKey.asReadonly();

  /** Only the entries this account's permissions allow. */
  protected readonly nav = computed<readonly NavEntry[]>(() =>
    OPS_NAV.filter((entry) => this.auth.can(entry.permission)));

  protected readonly title = computed(() => {
    const entry = OPS_NAV.find((item) => item.key === this.activeKey());
    return entry ? entry.labelKey : '';
  });

  constructor() {
    this.router.events.pipe(
      filter((event) => event instanceof NavigationEnd),
      takeUntilDestroyed(),
    ).subscribe(() => this.activeKey.set(this.readKey()));
  }

  protected signOut(): void {
    this.auth.signOut();
  }

  /**
   * The deepest activated child names the screen. The walk stops at a child
   * without a snapshot: this component is built while the router is still
   * activating, and a child's snapshot is attached only after its parent's
   * component exists. Reading it too early throws and the shell never renders.
   */
  private readKey(): string {
    let route = this.route;
    while (route.firstChild?.snapshot) {
      route = route.firstChild;
    }
    return (route.snapshot.data['navKey'] as string | undefined) ?? '';
  }
}
