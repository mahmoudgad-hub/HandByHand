import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute, NavigationEnd, Router } from '@angular/router';
import { filter } from 'rxjs';

import { TabBadge } from './tab-badge';
import { I18nService } from '../i18n/i18n.service';

/**
 * Says the name of the screen after a route change.
 *
 * A single-page app replaces the body without a page load, and a screen
 * reader has nothing to announce - the user is silently somewhere else. This
 * writes the new screen's title into a live region so it is read out, the way
 * a browser reads a new page's title.
 *
 * The region is visually hidden, never empty-then-filled in the same frame,
 * and polite: it waits for the reader to finish rather than cutting in.
 */
@Component({
  selector: 'hbh-route-announcer',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <span class="hbh-sr" role="status" aria-live="polite" aria-atomic="true">
      {{ announcement() }}
    </span>
  `,
})
export class RouteAnnouncer {
  private readonly tabBadge = inject(TabBadge);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly i18n = inject(I18nService);

  protected readonly announcement = signal('');

  constructor() {
    this.router.events.pipe(
      filter((event) => event instanceof NavigationEnd),
      takeUntilDestroyed(),
    ).subscribe(() => {
      const title = this.i18n.translate(this.titleKey());
      this.announcement.set(title);
      // The browser tab should carry it too - it is the same answer to the
      // same question, and it is what a bookmark and a task switcher show.
      this.tabBadge.setTitle(title
        ? `${title} — ${this.i18n.translate('app.name')}`
        : this.i18n.translate('app.name'));
    });
  }

  private titleKey(): string {
    let route = this.route;
    while (route.firstChild?.snapshot) {
      route = route.firstChild;
    }
    const data = route.snapshot.data as { titleKey?: string };
    return data.titleKey ?? '';
  }
}
