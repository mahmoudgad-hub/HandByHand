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
      const title = this.screenName();
      this.announcement.set(title);
      // The browser tab should carry it too - it is the same answer to the
      // same question, and it is what a bookmark and a task switcher show.
      this.tabBadge.setTitle(title
        ? `${title} — ${this.i18n.translate('app.name')}`
        : this.i18n.translate('app.name'));
    });
  }

  /**
   * The name of the screen, and of the TAB inside it when it has one.
   *
   * A screen whose tabs live in the address bar is thirteen screens as far
   * as anybody reading the browser tab, a bookmark or a task switcher is
   * concerned - and the child's file announced "ملفّ المستفيد" for all
   * thirteen, so a screen reader user moving between them heard the same
   * three words each time and could not tell whether anything had happened.
   *
   * THE TAB'S NAME COMES FROM route.data, NOT FROM THE COMPONENT. A route
   * says `tabTitlePrefix: 'child.tab.'` and this reads the `tab` query
   * parameter against it. The component that draws the tabs is not asked and
   * must not be: this announcer is the one place the title is decided, and a
   * component that set document.title as well would be a second answer to
   * one question - the defect this file exists to have removed (HBH-039).
   *
   * An unknown tab name falls back to the screen alone rather than printing
   * a key: translate() returns what it was given when the bundle has no
   * entry, and "child.tab.nonsense — Hand By Hand" in a task switcher is
   * worse than the screen's name on its own.
   */
  private screenName(): string {
    let route = this.route;
    while (route.firstChild?.snapshot) {
      route = route.firstChild;
    }
    const data = route.snapshot.data as { titleKey?: string; tabTitlePrefix?: string };
    const screen = data.titleKey ? this.i18n.translate(data.titleKey) : '';
    if (!screen || !data.tabTitlePrefix) {
      return screen;
    }
    const tab = route.snapshot.queryParamMap.get('tab');
    if (!tab) {
      return screen;
    }
    const key = `${data.tabTitlePrefix}${tab}`;
    const named = this.i18n.translate(key);
    return named && named !== key ? `${screen} · ${named}` : screen;
  }
}
