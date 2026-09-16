import { AccountDialog } from '../../features/profile/account-dialog';
import { output } from '@angular/core';
import { Component, signal } from '@angular/core';
import { UserAvatars } from '@hbh/shared/ui/user-avatar';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, Router, provideRouter } from '@angular/router';
import { of } from 'rxjs';
import ar from '../../../assets/i18n/ar.json';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { InboxApi } from '../../core/api/inbox-api';
import { TasksService } from '../../core/tasks/tasks.service';
import { ActionDialogHost } from '../../features/day/action-dialog-host';
import { RecordDrawerHost } from '../../features/drawer/record-drawer-host';
import { FAVORITES_STORAGE } from '../../core/favorites/favorites.service';
import { Shell } from './shell';

@Component({ selector: 'hbh-account-dialog', template: '<button class=close-account (click)="closed.emit()">Close</button>' }) class AccountStub { readonly closed = output<void>(); }

@Component({ selector: 'hbh-action-dialog-host', template: '' }) class ActionStub {}
@Component({ selector: 'hbh-record-drawer-host', template: '' }) class DrawerStub {}

describe('Staff navigation', () => {
  let held: Set<string>;
  let signOut: jasmine.Spy;
  beforeEach(() => {
    signOut = jasmine.createSpy('signOut');
    held = new Set(['PORTAL.VIEW', 'STAFF.MANAGE', 'SITE.EDIT']);
    TestBed.configureTestingModule({ providers: [provideRouter([]),
      { provide: UserAvatars, useValue: { viewer: signal(91), urls: signal({}), load: () => {} } },
      { provide: FAVORITES_STORAGE, useValue: { getItem: () => null, setItem: () => undefined } },
      { provide: OpsAuthService, useValue: {
        can: (p: string) => held.has(p),
        me: () => ({ userId: 91, centerCode: 'test', fullName: 'عضو', centerName: 'المركز' }),
        roleLabelKey: () => '',
        signOut,
      } },
      { provide: InboxApi, useValue: { list: () => of({ unread: 2, rows: [] }) } },
      { provide: TasksService, useValue: { refreshIfStale: () => undefined, loadedAt: () => 1, count: () => 3, loading: () => false, failed: () => [], tasks: () => [] } },
      { provide: I18nService, useValue: { translate: (key: string) => (ar as Record<string, string>)[key] ?? key } },
    ] }).overrideComponent(Shell, { remove: { imports: [AccountDialog, ActionDialogHost, RecordDrawerHost] }, add: { imports: [AccountStub, ActionStub, DrawerStub] } });
  });

  function mount() { const fixture = TestBed.createComponent(Shell); fixture.detectChanges(); return fixture; }

  it('opens only the clicked popup and preserves the remaining notifications',async()=>{
    const fixture=mount(),vm=fixture.componentInstance as any;
    const item={id:22,title:'New message',body:'message',at:'2026-09-14T12:00:00Z',read:false,kind:'CHAT_MESSAGE',target:['/communications'],targetQuery:{peer:8}};
    vm.pendingNotifications.set([{...item,id:21,at:'2026-09-13T12:00:00Z'},item]);
    const router=TestBed.inject(Router);const navigate=spyOn(router,'navigate').and.resolveTo(true);
    const read=jasmine.createSpy().and.returnValue(of({}));(TestBed.inject(InboxApi) as any).markRead=read;
    fixture.detectChanges();
    const buttons=fixture.nativeElement.querySelectorAll('button.ops-alert-item');expect(buttons.length).toBe(2);
    await vm.openNew(null,item);
    expect(navigate).toHaveBeenCalledWith(['/communications'],{queryParams:{peer:8}});
    expect(vm.pendingNotifications().map((r:any)=>r.id)).toEqual([21]);expect(read).toHaveBeenCalledWith(22);
    fixture.destroy();
  });
  it('keeps a popup available when navigation fails',async()=>{
    const fixture=mount(),vm=fixture.componentInstance as any;
    const item={id:22,title:'Notice',body:'',at:'2026-09-14',read:false,kind:'CHAT_MESSAGE',target:['/communications']};
    vm.pendingNotifications.set([item]);spyOn(TestBed.inject(Router),'navigate').and.rejectWith(new Error('failed'));
    await vm.openNew(null,item);expect(vm.pendingNotifications()).toEqual([item]);expect(vm.popupError()).toBeTruthy();fixture.destroy();
  });
  it('opens My Account over the current page and closes without navigation', () => {
    const fixture = mount();
    (fixture.nativeElement.querySelector('.ops-account-profile') as HTMLButtonElement).click();
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('hbh-account-dialog')).not.toBeNull();
    expect(fixture.nativeElement.querySelector('router-outlet')).not.toBeNull();
    (fixture.nativeElement.querySelector('.close-account') as HTMLButtonElement).click();
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('hbh-account-dialog')).toBeNull();
  });

  it('collapses the desktop sidebar into an accessible icon rail', () => {
    const fixture = mount();
    const button: HTMLButtonElement = fixture.nativeElement.querySelector('.ops-desktop-trigger');
    const sidebar: HTMLElement = fixture.nativeElement.querySelector('#opsSidebar');
    button.click(); fixture.detectChanges();
    expect(button.getAttribute('aria-expanded')).toBe('false');
    expect(sidebar.hasAttribute('inert')).toBeFalse();
    expect(fixture.nativeElement.querySelector('.ops-sidebar-collapsed')).not.toBeNull();
    expect(sidebar.querySelector('a[aria-label]')).not.toBeNull();
    button.click(); fixture.detectChanges();
    expect(button.getAttribute('aria-expanded')).toBe('true');
    expect(sidebar.hasAttribute('inert')).toBeFalse();
  });

  it('opens a rail group on click, keeps permission filtering, and closes when expanded', () => {
    const fixture = mount();
    (fixture.nativeElement.querySelector('.ops-desktop-trigger') as HTMLButtonElement).click(); fixture.detectChanges();
    const trigger = fixture.nativeElement.querySelector('[aria-controls=desktop-nav-team]') as HTMLButtonElement;
    trigger.click(); fixture.detectChanges();
    const panel = fixture.nativeElement.querySelector('#desktop-nav-team') as HTMLElement;
    expect(panel.matches(':popover-open')).toBeTrue();
    expect(trigger.getAttribute('aria-expanded')).toBe('true');
    expect(panel.querySelector('a')).not.toBeNull();
    expect(fixture.nativeElement.querySelector('a[href="/billing"]')).toBeNull();
    // Native popovers own Escape/light dismissal; switching mode must also close them.
    (fixture.nativeElement.querySelector('.ops-desktop-trigger') as HTMLButtonElement).click(); fixture.detectChanges();
    expect(panel.matches(':popover-open')).toBeFalse();
    expect(panel.hasAttribute('popover')).toBeFalse();
  });

  it('opens rail groups on hover without navigating', () => {
    const fixture = mount();
    (fixture.nativeElement.querySelector('.ops-desktop-trigger') as HTMLButtonElement).click(); fixture.detectChanges();
    const trigger = fixture.nativeElement.querySelector('[aria-controls=desktop-nav-team]') as HTMLButtonElement;
    trigger.dispatchEvent(new MouseEvent('mouseenter')); fixture.detectChanges();
    const panel = fixture.nativeElement.querySelector('#desktop-nav-team') as HTMLElement;
    expect(panel.matches(':popover-open')).toBeTrue();
    trigger.parentElement!.dispatchEvent(new MouseEvent('mouseleave')); fixture.detectChanges();
    expect(panel.matches(':popover-open')).toBeFalse();
  });

  it('provides the signed-in account and explicit sign out in the mobile drawer', () => {
    const fixture = mount();
    (fixture.nativeElement.querySelector('.ops-mobile-trigger') as HTMLButtonElement).click(); fixture.detectChanges();
    const footer = fixture.nativeElement.querySelector('.ops-drawer-account') as HTMLElement;
    expect(footer.textContent).toContain('عضو');
    expect(signOut).not.toHaveBeenCalled();
    (footer.querySelector('button') as HTMLButtonElement).click(); fixture.detectChanges();
    expect(signOut).toHaveBeenCalledTimes(1);
    expect(fixture.nativeElement.querySelector('.ops-menu-dialog')).toBeNull();
  });

  it('toggles the current screen favorite with an accessible pressed state', () => {
    TestBed.inject(ActivatedRoute).snapshot.data = { navKey: 'site-team' };
    const fixture = mount();
    const star: HTMLButtonElement = fixture.nativeElement.querySelector('.ops-favorite-toggle');
    expect(star.getAttribute('aria-pressed')).toBe('false');
    star.click(); fixture.detectChanges();
    expect(star.getAttribute('aria-pressed')).toBe('true');
    expect(star.classList.contains('is-favorite')).toBeTrue();
    star.click(); fixture.detectChanges();
    expect(star.getAttribute('aria-pressed')).toBe('false');
  });

  it('opens the user dropdown from the top bar and signs out only on explicit selection', () => {
    const fixture = mount();
    const trigger: HTMLButtonElement = fixture.nativeElement.querySelector('.ops-account-trigger');
    const menu: HTMLElement = fixture.nativeElement.querySelector('#opsAccountMenu');
    expect(fixture.nativeElement.querySelector('.hbh-side__signout')).toBeNull();
    expect(trigger.textContent).toContain('عضو');
    expect(menu.querySelector('button.ops-account-profile')?.textContent).toContain('حسابي');
    expect(menu.matches(':popover-open')).toBeFalse();
    trigger.click();
    expect(menu.matches(':popover-open')).toBeTrue();
    expect(signOut).not.toHaveBeenCalled();
    (menu.querySelector('.ops-account-logout') as HTMLButtonElement).click();
    expect(signOut).toHaveBeenCalledTimes(1);
    expect(menu.matches(':popover-open')).toBeFalse();
  });

  it('searches Arabic names without hamza or vowel marks and keeps unauthorized pages hidden', () => {
    const fixture = mount();
    const input: HTMLInputElement = fixture.nativeElement.querySelector('input');
    input.value = 'شَهَادَات الاخصائيين'; input.dispatchEvent(new Event('input')); fixture.detectChanges();
    const links: NodeListOf<HTMLAnchorElement> = fixture.nativeElement.querySelectorAll('nav a');
    expect(links.length).toBe(1);
    expect(links[0].getAttribute('href')).toBe('/site/team');
    input.value = 'الفواتير'; input.dispatchEvent(new Event('input')); fixture.detectChanges();
    expect(fixture.nativeElement.querySelectorAll('nav a').length).toBe(0);
    expect(fixture.nativeElement.querySelector('[role=status]')).not.toBeNull();
  });

  it('reveals a collapsed group while searching and preserves its collapse after clearing', () => {
    const fixture = mount();
    const toggle: HTMLButtonElement = fixture.nativeElement.querySelector('[aria-controls=desktop-nav-team]');
    toggle.click(); fixture.detectChanges();
    expect(toggle.getAttribute('aria-expanded')).toBe('false');
    const input: HTMLInputElement = fixture.nativeElement.querySelector('input');
    input.value = 'شهادات'; input.dispatchEvent(new Event('input')); fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('#desktop-nav-team').hidden).toBeFalse();
    input.value = ''; input.dispatchEvent(new Event('input')); fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('#desktop-nav-team').hidden).toBeTrue();
  });

  it('keeps the website menu selected when changing its inner tab to team', () => {
    const snapshot = TestBed.inject(ActivatedRoute).snapshot;
    snapshot.data = { navKey: 'site' };
    snapshot.queryParams = { tab: 'team' };
    const fixture = mount();
    const active: HTMLAnchorElement = fixture.nativeElement.querySelector('a[aria-current=page]');
    expect(active.getAttribute('href')).toBe('/site');
    expect(fixture.nativeElement.querySelectorAll('a[aria-current=page]').length).toBe(1);
  });

  it('highlights the team entry when opening its standalone screen', () => {
    TestBed.inject(ActivatedRoute).snapshot.data = { navKey: 'site-team' };
    const fixture = mount();
    const active: HTMLAnchorElement = fixture.nativeElement.querySelector('a[aria-current=page]');
    expect(active.getAttribute('href')).toBe('/site/team');
    expect(fixture.nativeElement.querySelectorAll('a[aria-current=page]').length).toBe(1);
  });

  it('opens a native menu dialog with readable links and closes on Escape', () => {
    const fixture = mount();
    const opener: HTMLButtonElement = fixture.nativeElement.querySelector('.ops-mobile-trigger');
    opener.click(); fixture.detectChanges(); TestBed.tick();
    const dialog: HTMLDialogElement = fixture.nativeElement.querySelector('dialog');
    expect(dialog.open).toBeTrue();
    expect(document.activeElement).toBe(dialog.querySelector('input'));
    expect(getComputedStyle(dialog.querySelector('.hbh-nav__item span')!).display).not.toBe('none');
    expect(dialog.scrollWidth).toBeLessThanOrEqual(dialog.clientWidth);
    dialog.dispatchEvent(new Event('cancel', { cancelable: true })); fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('dialog')).toBeNull();
    expect(opener.getAttribute('aria-expanded')).toBe('false');
  });
});
