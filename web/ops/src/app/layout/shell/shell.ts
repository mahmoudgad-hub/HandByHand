import { AccountDialog } from '../../features/profile/account-dialog';
import {
  ChangeDetectionStrategy, Component, DestroyRef, HostListener, computed, inject, signal, effect, untracked,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import {
  ActivatedRoute, NavigationEnd, Router, RouterLink, RouterOutlet,
} from '@angular/router';
import { filter, interval, finalize } from 'rxjs';
import { NgTemplateOutlet } from '@angular/common';
import { TabBadge } from '@hbh/shared/a11y/tab-badge';
import { ModalDialog } from '@hbh/shared/a11y/modal-dialog';
import { I18nService } from '@hbh/shared/i18n/i18n.service';

import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { UserAvatar } from '@hbh/shared/ui/user-avatar';
import { InboxApi, InboxItem } from '../../core/api/inbox-api';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { FAVORITABLE_SCREENS, FavoritesService } from '../../core/favorites/favorites.service';
import { Task } from '../../core/tasks/task-model';
import { TasksService, sortTasks, taskTime } from '../../core/tasks/tasks.service';
import { ActionDialogHost } from '../../features/day/action-dialog-host';
import { RecordDrawerHost } from '../../features/drawer/record-drawer-host';
import { NavEntry, NavGroup, OPS_NAV, OPS_NAV_GROUPS } from './nav';

/**
 * Sidebar, page header, content. The console's shell.
 *
 * It draws the menu from the permissions the server returned. That is a
 * convenience - it keeps a receptionist from clicking into a screen they
 * cannot fill - and it is not a control. The refusal lives in the policy
 * under the query, and it happens whether or not the entry was drawn.
 *
 * TWO NUMBERS LIVE IN THE MENU: how many tasks are waiting and how many
 * notifications are unread. Both refresh every fifteen seconds and on navigation;
 * both come from the same services the screens behind them use, so the
 * badge and the screen cannot disagree.
 */
@Component({
  selector: 'hbh-shell',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [AccountDialog, RouterOutlet, RouterLink, Icon, TranslatePipe, NgTemplateOutlet, ModalDialog, ActionDialogHost, RecordDrawerHost, UserAvatar],
  templateUrl: './shell.html',
  // Order is load-bearing and is NOT alphabetical: frame -> topbar ->
  // panels -> nav is the order these rules stood in shell-controls.css
  // before it was split (HBH-129). Same rules in another order is a
  // different screen.
  styleUrls: [
    './shell.css',
    './shell-frame.css',
    './shell-topbar.css',
    './shell-panels.css',
    './shell-nav.css',
  ],
})
export class Shell {
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly destroyRef = inject(DestroyRef);
  private readonly inbox = inject(InboxApi);
  private readonly i18n = inject(I18nService);
  protected readonly auth = inject(OpsAuthService);
  protected readonly tasks = inject(TasksService);
  protected readonly favorites = inject(FavoritesService);
  private readonly pageUrl = signal(this.router.url);
  protected readonly favoriteEntry = computed(() => {
    const ownId = this.auth.me()?.therapistId;
    const key = ownId !== undefined && this.pageUrl().split('?')[0] === '/therapists/' + ownId + '/profile' ? 'my-profile' : this.active();
    if (['dashboard', 'tasks', 'notifications'].includes(key)) return undefined;
    return FAVORITABLE_SCREENS.find(entry => entry.key === key && this.allowed(entry));
  });

  private readonly activeKey = signal<string>(this.readKey());
  protected readonly active = this.activeKey.asReadonly();

  /** Unread notifications, or null until read (a failure draws nothing, never zero). */
  protected readonly unread = signal<number | null>(null);
  protected readonly unreadPreview = signal<readonly InboxItem[]>([]);
  protected readonly quickOpen = signal('');
  protected readonly quickLeft = signal(16);
  protected positionQuick(event: Event): void {
    const rect=(event.currentTarget as HTMLElement).getBoundingClientRect();
    this.quickLeft.set(Math.max(16, Math.min(rect.left, window.innerWidth - 376)));
  }
  protected readPreview(item: InboxItem): void {
    this.pendingNotifications.update(rows=>rows.filter(row=>row.id!==item.id));this.tabBadge.setCount(this.newItems());
    this.inbox.markRead(item.id).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({next:()=>{
      this.unreadPreview.update(rows=>rows.filter(row=>row.id!==item.id));
      this.refreshBadges();
    },error:()=>undefined});
  }

  protected readonly menuOpen = signal(false);
  protected readonly sidebarCollapsed = signal(false);
  protected readonly profileOpen = signal(false);
  protected readonly accountOpen = signal(false);
  protected readonly search = signal('');
  protected readonly quickLinks = computed(() => this.groups().flatMap(g => g.entries).filter(e => e.key === 'tasks' || e.key === 'notifications'));
  protected readonly collapsed = signal<ReadonlySet<string>>(new Set());

  /** Only the groups with at least one entry this account may open. */
  protected readonly groups = computed<readonly NavGroup[]>(() =>
    OPS_NAV_GROUPS
      .map((group) => ({ ...group, entries: group.entries.filter((entry) => this.allowed(entry)) }))
      .filter((group) => group.entries.length > 0));

  protected readonly filteredGroups = computed(() => {
    const terms = this.fold(this.search()).split(/\s+/).filter(Boolean);
    return this.groups().map(group => ({ ...group, entries: group.entries.filter(entry => {
      const label = this.fold(this.i18n.translate(entry.labelKey) + ' '
        + (group.labelKey ? this.i18n.translate(group.labelKey) : ''));
      return terms.every(term => label.includes(term));
    }) })).filter(group => group.entries.length > 0);
  });

  protected expanded(group: NavGroup): boolean {
    return !!this.search().trim() || !this.collapsed().has(group.key);
  }

  protected toggleGroup(group: NavGroup): void {
    this.collapsed.update(current => {
      const next = new Set(current);
      if (next.has(group.key)) next.delete(group.key); else next.add(group.key);
      return next;
    });
  }

  protected readonly railOpen = signal('');
  protected readonly railTop = signal(0);
  protected readonly railLeft = signal(0);
  protected groupActive(group: NavGroup): boolean { return group.entries.some(entry => entry.key === this.active()); }
  protected groupIcon(group: NavGroup): NavEntry['icon'] {
    const icons: Record<string, NavEntry['icon']> = { customers: 'ic-users', operations: 'ic-calendar', finance: 'ic-card', communication: 'ic-chat', team: 'ic-user-check', settings: 'ic-settings' };
    return icons[group.key] ?? group.entries[0].icon;
  }
  @HostListener('window:resize')
  protected closeRail(): void {
    document.querySelectorAll<HTMLElement>('.ops-rail-panel:popover-open').forEach(panel => panel.hidePopover());
    this.railOpen.set('');
  }
  protected toggleSidebar(): void {
    this.closeRail();
    this.sidebarCollapsed.update(value => !value);
  }
  protected showRail(group: NavGroup, surface: string, event: Event): void {
    if (surface !== 'desktop' || !this.sidebarCollapsed()) return;
    const trigger = event.currentTarget as HTMLElement;
    const rect = trigger.getBoundingClientRect();
    const panel = document.getElementById('desktop-nav-' + group.key);
    if (!panel) return;
    this.railLeft.set(getComputedStyle(trigger).direction === 'rtl' ? rect.left - 248 : rect.right);
    panel.showPopover();
    this.railOpen.set(group.key);
    this.railTop.set(Math.max(12, Math.min(rect.top, window.innerHeight - panel.offsetHeight - 12)));
  }
  protected hideRail(group: NavGroup, surface: string): void {
    if (surface !== 'desktop' || !this.sidebarCollapsed()) return;
    const panel = document.getElementById('desktop-nav-' + group.key);
    if (panel?.matches(':popover-open') && !panel.contains(document.activeElement)) panel.hidePopover();
  }
  protected railToggled(group: NavGroup, event: Event): void {
    if ((event as ToggleEvent).newState === 'open') this.railOpen.set(group.key);
    else if (this.railOpen() === group.key) this.railOpen.set('');
  }
  protected activateGroup(group: NavGroup, surface: string, event: Event): void {
    if (surface === 'desktop' && this.sidebarCollapsed()) this.showRail(group, surface, event);
    else this.toggleGroup(group);
  }
  protected dismissBackdrop(event: MouseEvent): void {
    const dialog = event.currentTarget as HTMLDialogElement;
    if (event.target !== dialog) return;
    const rect = dialog.getBoundingClientRect();
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) this.closeMenu();
  }

  protected closeMenu(): void { this.menuOpen.set(false); }
  protected followLink(): void { this.closeMenu(); this.search.set(''); this.closeRail(); }

  private fold(value: string): string {
    return value.normalize('NFKD').replace(/[\u064B-\u065F\u0670\u0640]/g, '')
      .replace(/[إأآٱ]/g, 'ا').replace(/ى/g, 'ي').toLocaleLowerCase().trim();
  }

  protected readonly title = computed(() => {
    if (this.activeKey() === 'profile') return 'profile.title';
    const entry = OPS_NAV.find((item) => item.key === this.activeKey());
    return entry ? entry.labelKey : '';
  });

  protected readonly accountRole = computed(() => {
    const roleKey = this.auth.roleLabelKey(this.auth.me());
    if (!roleKey) return '';
    return this.i18n.translate(roleKey);
  });

  protected readonly pendingTasks = signal<readonly Task[]>([]);
  protected readonly pendingNotifications = signal<readonly InboxItem[]>([]);
  protected readonly newTasks = computed(()=>this.pendingTasks().length);
  protected readonly newNotifications = computed(()=>this.pendingNotifications().length);
  protected readonly popupOpening = signal(false);
  protected readonly popupError = signal('');
  protected readonly popupItems = computed(()=>[
    ...this.pendingTasks().map(task=>({key:'task:'+task.id,at:taskTime(task),task,notification:null as InboxItem|null})),
    ...this.pendingNotifications().map(notification=>({key:'notification:'+notification.id,at:Date.parse(notification.at)||0,task:null as Task|null,notification})),
  ].sort((a,b)=>b.at-a.at||b.key.localeCompare(a.key,undefined,{numeric:true})));
  protected readonly newItems = computed(() => this.newTasks() + this.newNotifications());
  private readonly tabBadge = inject(TabBadge);
  private seenTasks = new Set<string>();
  private tasksReady = false;
  private lastNotification: number | null = null;
  protected dismissNew(): void {this.pendingTasks.set([]);this.pendingNotifications.set([]);this.popupError.set('');this.tabBadge.setCount(0);}
  protected async openNew(task:Task|null,item:InboxItem|null):Promise<void>{
    if(this.popupOpening())return;
    this.popupOpening.set(true);this.popupError.set('');
    try {
      const opened=await this.router.navigate([...(task?.primaryAction.link??item?.target??['/notifications'])],{queryParams:task?.primaryAction.query??item?.targetQuery});
      // Navigating to an already-open target can return false without an error.
      const target=this.router.createUrlTree([...(task?.primaryAction.link??item?.target??['/notifications'])],{queryParams:task?.primaryAction.query??item?.targetQuery});
      if(!opened&&!this.router.isActive(target,{paths:'exact',queryParams:'exact',fragment:'ignored',matrixParams:'ignored'})){this.popupError.set('تعذر فتح الإشعار. حاول مرة أخرى.');return;}
      if(task)this.pendingTasks.update(rows=>rows.filter(row=>row.id!==task.id));
      if(item){this.pendingNotifications.update(rows=>rows.filter(row=>row.id!==item.id));this.readPreview(item);}
      this.tabBadge.setCount(this.newItems());
    }catch{this.popupError.set('تعذر فتح الإشعار. حاول مرة أخرى.');}
    finally{this.popupOpening.set(false);}
  }
  constructor() {
    effect(()=>{
      if(!this.tasks.loadedAt() || this.tasks.loading() || this.tasks.failed().length)return;
      const rows=this.tasks.tasks(),fresh=this.tasksReady?rows.filter(row=>!this.seenTasks.has(row.id)):[];
      for(const row of rows)this.seenTasks.add(row.id);
      untracked(()=>{
        this.pendingTasks.set(sortTasks([...new Map([...this.pendingTasks(),...fresh].filter(task=>rows.some(row=>row.id===task.id)).map(task=>[task.id,task])).values()]));
        this.tabBadge.setCount(this.newItems());
      });
      this.tasksReady=true;
    });
    this.destroyRef.onDestroy(()=>this.tabBadge.setCount(0));
    this.refreshBadges();
    interval(15_000).pipe(takeUntilDestroyed(this.destroyRef)).subscribe(() => this.refreshBadges(true));
    this.router.events.pipe(
      filter((event) => event instanceof NavigationEnd),
      takeUntilDestroyed(),
    ).subscribe(() => {
      this.profileOpen.set(false);
      this.activeKey.set(this.readKey());
      this.pageUrl.set(this.router.url);
      this.followLink();
      const group = this.groups().find(group => group.entries.some(entry => entry.key === this.active()));
      if (group) this.collapsed.update(current => new Set([...current].filter(key => key !== group.key)));
      this.refreshBadges();
    });
  }

  protected allowed(entry: NavEntry): boolean {
    if (entry.needsTherapist && this.auth.me()?.therapistId === undefined) {
      return false;
    }
    return this.auth.can(entry.permission)
      || (entry.altPermission !== undefined && this.auth.can(entry.altPermission));
  }

  /** The path an entry opens, with "me" resolved to the signed-in therapist. */
  protected pathOf(entry: NavEntry): string {
    const me = this.auth.me()?.therapistId;
    return me !== undefined ? entry.path.replace('/me/', `/${me}/`) : entry.path;
  }

  /**
   * The query an entry opens with. The diary opens on "my day" for an
   * account that can start sessions but not book them - the clinician - and
   * on the centre's day for everyone else. Nothing is decided here that the
   * screen does not decide again from the same permissions.
   */
  protected queryOf(entry: NavEntry): Record<string, string> | null {
    if (entry.key === 'appointments'
      && !this.auth.can('APPOINTMENT.BOOK') && this.auth.me()?.therapistId !== undefined) {
      return { view: 'mine' };
    }
    return entry.query ? { ...entry.query } : null;
  }

  protected badgeOf(entry: NavEntry): number | null {
    if (entry.badge === 'tasks') {
      return this.tasks.loadedAt() ? this.tasks.count() : null;
    }
    if (entry.badge === 'notifications') {
      return this.unread();
    }
    return null;
  }

  protected signOut(): void {
    this.auth.signOut();
  }

  // Avoid overlapping notification requests; keep the last count on failure.
  private notificationsLoading = false;
  private refreshBadges(force = false): void {
    if (!this.auth.can('PORTAL.VIEW')) {
      return;
    }
    this.tasks.refreshIfStale(force ? 0 : 15_000);
    if (this.notificationsLoading) return;
    this.notificationsLoading = true;
    this.inbox.list(50)
      .pipe(takeUntilDestroyed(this.destroyRef), finalize(() => { this.notificationsLoading = false; }))
      .subscribe({
        next: (feed) => {
          this.unread.set(feed.unread);
          this.unreadPreview.set(feed.rows.filter(row=>!row.read).slice(0,5));
          const newest=Math.max(0,...feed.rows.map(row=>row.id));
          const fresh=this.lastNotification===null?[]:feed.rows.filter(row=>row.id>this.lastNotification!&&!row.read);
          const read=new Set(feed.rows.filter(row=>row.read).map(row=>row.id));
          this.pendingNotifications.set([...new Map([...this.pendingNotifications(),...fresh].filter(row=>!read.has(row.id)).map(row=>[row.id,row])).values()]);
          this.tabBadge.setCount(this.newItems());
          this.lastNotification=Math.max(this.lastNotification??0,newest);
        },
        error: () => undefined,
      });
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
    return (route.snapshot.data['navKey'] as string | undefined) || '';
  }
}
