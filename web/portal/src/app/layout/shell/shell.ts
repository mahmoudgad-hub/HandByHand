import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  computed,
  inject,
  signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import {
  ActivatedRoute,
  NavigationEnd,
  Router,
  RouterLink,
  RouterOutlet,
} from '@angular/router';
import { filter } from 'rxjs';

import { PortalApi } from '../../core/api/portal-api';
import { ChildContextService } from '../../core/auth/child-context.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';

/** What a routed screen tells the shell about its own chrome. */
interface ScreenChrome {
  readonly titleKey: string;
  readonly subtitle: 'child' | null;
  readonly back: string | null;
  readonly tab: string | null;
}

const NO_CHROME: ScreenChrome = {
  titleKey: '', subtitle: null, back: null, tab: null,
};

/**
 * Header, body and tab bar. The shell renders chrome and routes; it loads no
 * data of its own, so a screen's failure never takes the navigation with it.
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
  private readonly child = inject(ChildContextService);
  private readonly api = inject(PortalApi);
  private readonly destroyRef = inject(DestroyRef);

  private readonly chromeState = signal<ScreenChrome>(this.readChrome());

  protected readonly chrome = this.chromeState.asReadonly();

  /**
   * The phone's tab bar: five, because a sixth stops being tappable. Account
   * is one of them, since a phone has nowhere else to put it.
   */
  protected readonly tabs = [
    { key: 'home', path: '/home', icon: 'ic-home', labelKey: 'nav.home' },
    { key: 'schedule', path: '/schedule', icon: 'ic-calendar', labelKey: 'nav.schedule' },
    { key: 'progress', path: '/progress', icon: 'ic-target', labelKey: 'nav.progress' },
    { key: 'activities', path: '/activities', icon: 'ic-puzzle', labelKey: 'nav.activities' },
    { key: 'profile', path: '/profile', icon: 'ic-user', labelKey: 'nav.profile' },
  ] as const;

  /**
   * The wide screen's top bar. It carries two more than the phone can -
   * reports and billing - because there is room, and because on a laptop a
   * parent expects to reach a document without going through a card. Account
   * is not here: it is the chip at the end of the bar.
   */
  protected readonly webNav = [
    { key: 'home', path: '/home', icon: 'ic-home', labelKey: 'nav.home' },
    { key: 'schedule', path: '/schedule', icon: 'ic-calendar', labelKey: 'nav.schedule' },
    { key: 'progress', path: '/progress', icon: 'ic-target', labelKey: 'nav.progress' },
    { key: 'activities', path: '/activities', icon: 'ic-puzzle', labelKey: 'nav.activities' },
    { key: 'reports', path: '/reports', icon: 'ic-file', labelKey: 'nav.reports' },
    { key: 'billing', path: '/billing', icon: 'ic-receipt', labelKey: 'nav.billing' },
  ] as const;

  protected readonly subtitle = computed(() =>
    this.chrome().subtitle === 'child' ? this.child.selected()?.fullName ?? '' : '');

  /**
   * The name on the chip at the end of the wide bar. Fetched here rather than
   * handed down, because the shell outlives every screen and a reload
   * straight onto a deep route has no welcome screen to have supplied it.
   * An empty name leaves the chip as a plain link to the account - never a
   * placeholder that looks like a name.
   */
  protected readonly guardianName = signal('');

  /**
   * How many notifications this family has not opened.
   *
   * NULL MEANS UNKNOWN, AND UNKNOWN DRAWS NOTHING. C4's rule, in the one
   * place where breaking it would be invisible: a badge that falls back to 0
   * when the request fails tells a parent there is nothing waiting, which is
   * a statement the app has no basis for. No badge at all is honest - the
   * bell is still there and still opens the list, which will say what
   * happened.
   *
   * AND A FAILURE HERE TAKES NOTHING WITH IT. The shell loads no data that
   * any screen depends on, so a feed that will not load costs a badge and
   * leaves children, billing, appointments and reports untouched. That is
   * clause 37 of the brief and it is structural rather than promised: the
   * subscription is the shell's own, and the header renders before it
   * resolves either way.
   */
  protected readonly unread = signal<number | null>(null);

  constructor() {
    this.api.profile()
      .pipe(takeUntilDestroyed())
      .subscribe({
        next: (guardian) => this.guardianName.set(guardian.fullName),
        error: () => this.guardianName.set(''),
      });

    this.loadUnread();

    this.router.events.pipe(
      filter((event) => event instanceof NavigationEnd),
      takeUntilDestroyed(),
    ).subscribe(() => {
      this.chromeState.set(this.readChrome());
      // The count is refreshed on navigation rather than polled. A parent who
      // has just read three notifications should not carry a badge saying
      // three around the app - and a timer would keep a request going all
      // evening on a screen nobody is looking at.
      this.loadUnread();
      // Both, because the shell has two shapes and each scrolls a
      // different thing. Below 900px .pa__body is an overflow container
      // inside a fixed-height column and the document does not move; above
      // it .pa__body is an ordinary block and the window is what scrolls.
      // Resetting only one leaves the other shape landing halfway down the
      // page it just left.
      document.getElementById("paBody")?.scrollTo({ top: 0 });
      window.scrollTo({ top: 0 });
    });
  }

  /**
   * The cheapest possible ask: one row, for the count on the envelope.
   *
   * limit=1 rather than the default thirty. The service counts unread over
   * the WHOLE feed regardless of the page, so a page of one is enough - and
   * the difference is thirty rows of Arabic on every navigation in the app.
   */
  private loadUnread(): void {
    this.api.notifications(1)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (feed) => this.unread.set(feed.unread),
        // Unknown, not zero. See the field's own note.
        error: () => this.unread.set(null),
      });
  }

  /**
   * The deepest activated child owns the chrome for the screen on show.
   *
   * The walk stops at a child that has no snapshot yet. That is not defensive
   * padding: this component is constructed while the router is still
   * activating, and a child route's `snapshot` is only attached when the
   * router advances to it - which happens after the parent's component
   * exists. Reading it during construction threw, and the shell never
   * rendered. The header is briefly blank in that window, and the
   * NavigationEnd below fills it in before the frame is painted.
   */
  private readChrome(): ScreenChrome {
    let route = this.route;
    while (route.firstChild?.snapshot) {
      route = route.firstChild;
    }
    const data = route.snapshot.data as Partial<ScreenChrome>;
    return {
      titleKey: data.titleKey ?? NO_CHROME.titleKey,
      subtitle: data.subtitle ?? NO_CHROME.subtitle,
      back: data.back ?? NO_CHROME.back,
      tab: data.tab ?? NO_CHROME.tab,
    };
  }
}
