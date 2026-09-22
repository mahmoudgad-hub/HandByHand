import {
  ChangeDetectionStrategy,
  Component,
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
import { PersonAvatar } from '../../shared/ui/person-avatar';
import { ModalDialog } from '@hbh/shared/a11y/modal-dialog';
import { NotificationBadge } from '../../core/alerts/notification-badge';
import { Child } from '../../core/models/portal.models';
import { ChildRouteReuse } from '../../core/auth/child-route-reuse';
import { HbhAgePipe } from '@hbh/shared/format/format.pipes';

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
  imports: [RouterOutlet, RouterLink, Icon, PersonAvatar, TranslatePipe, ModalDialog, HbhAgePipe],
  templateUrl: './shell.html',
})
export class Shell {
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly child = inject(ChildContextService);
  private readonly api = inject(PortalApi);

  private readonly chromeState = signal<ScreenChrome>(this.readChrome());

  protected readonly chrome = this.chromeState.asReadonly();
  protected readonly selectedChild = this.child.selected;
  protected readonly moreOpen = signal(false);
  protected readonly childPickerOpen = signal(false);
  protected readonly familyChildren = signal<readonly Child[]>([]);
  protected readonly switchingChild = signal(false);
  protected readonly switchFailed = signal(false);
  protected readonly canSwitchChild = computed(() => this.familyChildren().length > 1);
  private readonly childRouteReuse = inject(ChildRouteReuse);

  protected openChildPicker(): void {
    if (!this.canSwitchChild()) return;
    this.moreOpen.set(false);
    this.switchFailed.set(false);
    this.childPickerOpen.set(true);
  }

  protected async chooseChild(candidate: Child): Promise<void> {
    if (this.switchingChild()) return;
    const next = this.familyChildren().find(child => child.id === candidate.id);
    if (!next) return;
    const previous = this.selectedChild();
    if (previous?.id === next.id) { this.childPickerOpen.set(false); return; }
    this.switchingChild.set(true);
    this.switchFailed.set(false);
    this.child.select(next);
    this.childRouteReuse.refreshingChild = true;
    // A report/meeting belongs to a specific child; return to its list for the new child.
    const current = this.router.parseUrl(this.router.url);
    const path = current.root.children['primary']?.segments.map(segment => segment.path).join('/') ?? '';
    let target = current;
    if (path.startsWith('reports/')) target = this.router.createUrlTree(['/progress'], { queryParams: { tab: 'reports' } });
    else if (path.startsWith('consultation/')) target = this.router.createUrlTree(['/schedule']);
    else if (path === 'requests') delete target.queryParams['appointment'];
    try {
      const navigated = await this.router.navigateByUrl(target, { onSameUrlNavigation: 'reload', replaceUrl: true });
      if (!navigated) throw new Error('Child navigation cancelled');
      this.childPickerOpen.set(false);
    } catch {
      if (previous) this.child.select(previous); else this.child.clear();
      this.switchFailed.set(true);
    } finally {
      this.childRouteReuse.refreshingChild = false;
      this.switchingChild.set(false);
    }
  }
  protected readonly pageIntro = computed(() => {
    const tab = this.chrome().tab;
    return ['home', 'schedule', 'progress', 'activities', 'billing', 'requests', 'profile', 'notifications'].includes(tab ?? '')
      ? `portal.intro.${tab}` : '';
  });

  /**
   * The phone's tab bar: four screens and "more", because a sixth tab
   * stops being tappable. The account moved into "more" with billing, the
   * requests, the centre's messages and the notifications (UX-5): the four
   * that stay are the ones a parent opens every day.
   */
  protected readonly tabs = [
    { key: 'home', path: '/home', icon: 'ic-home', labelKey: 'nav.home' },
    { key: 'schedule', path: '/schedule', icon: 'ic-calendar', labelKey: 'nav.schedule' },
    { key: 'progress', path: '/progress', icon: 'ic-target', labelKey: 'nav.progress' },
    { key: 'activities', path: '/activities', icon: 'ic-puzzle', labelKey: 'nav.activities' },
  ] as const;

  /** "More" is lit while one of the screens it holds is on show. */
  protected readonly moreTabOn = computed(
    () => ['billing', 'requests', 'notifications', 'profile'].includes(this.chrome().tab ?? ''));

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
  protected readonly unread = inject(NotificationBadge).unread;

  constructor() {
    this.api.family().pipe(takeUntilDestroyed()).subscribe({
      next: family => this.familyChildren.set(family.children),
      error: () => this.familyChildren.set([]),
    });
    this.api.profile()
      .pipe(takeUntilDestroyed())
      .subscribe({
        next: (guardian) => this.guardianName.set(guardian.fullName),
        error: () => this.guardianName.set(''),
      });

    this.router.events.pipe(
      filter((event) => event instanceof NavigationEnd),
      takeUntilDestroyed(),
    ).subscribe(() => {
      this.moreOpen.set(false);
      this.chromeState.set(this.readChrome());
      // The authenticated notification watcher keeps the badge current.
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
