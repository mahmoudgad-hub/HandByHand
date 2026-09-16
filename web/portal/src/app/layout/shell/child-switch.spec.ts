import { Component, inject, signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideRouter, RouteReuseStrategy, Router } from '@angular/router';
import { RouterTestingHarness } from '@angular/router/testing';
import { of } from 'rxjs';
import { HBH_CONFIG, DEFAULT_HBH_CONFIG } from '@hbh/shared/config/app-config';
import { Shell } from './shell';
import { PortalApi } from '../../core/api/portal-api';
import { ChildContextService } from '../../core/auth/child-context.service';
import { ChildRouteReuse } from '../../core/auth/child-route-reuse';
import { NotificationBadge } from '../../core/alerts/notification-badge';
import { Child } from '../../core/models/portal.models';

@Component({ template: '<p class="loaded-child">{{ loadedId }}</p>' })
class ChildScreen {
  readonly loadedId = inject(ChildContextService).requireId();
}

describe('In-page child switch', () => {
  const children = [
    { id: 'one', fullName: 'First child', gender: 'F', birthDate: '2020-01-01', childNo: '1' },
    { id: 'two', fullName: 'Second child', gender: 'M', birthDate: '2019-01-01', childNo: '2' },
  ] as Child[];
  async function setup(count: number) {
    TestBed.configureTestingModule({ providers: [
      provideHttpClient(),
      provideRouter([{ path: '', component: Shell, children: [{ path: 'schedule', component: ChildScreen }] }]),
      { provide: RouteReuseStrategy, useExisting: ChildRouteReuse },
      { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, useFixtures: true } },
      { provide: NotificationBadge, useValue: { unread: signal(0) } },
      { provide: PortalApi, useValue: {
        profile: () => of({ fullName: 'Parent' }),
        family: () => of({ children: children.slice(0, count) }),
      } },
    ] });
    TestBed.inject(ChildContextService).select(children[0]);
    const harness = await RouterTestingHarness.create('/schedule?tab=past');
    harness.detectChanges();
    return harness;
  }
  afterEach(() => TestBed.inject(ChildContextService).clear());

  it('hides switching with only one child and keeps their name', async () => {
    const harness = await setup(1);
    expect(harness.routeNativeElement!.querySelector('.portal-switch-child')).toBeNull();
    expect(harness.routeNativeElement!.textContent).toContain('First child');
  });

  it('recreates the child screen while retaining URL, query and shell', async () => {
    const harness = await setup(2);
    const shell = harness.routeNativeElement!;
    (shell.querySelector('.portal-switch-child') as HTMLButtonElement).click();
    harness.detectChanges();
    await harness.fixture.whenStable();
    expect(shell.querySelector('dialog')?.open).toBeTrue();
    (shell.querySelectorAll('.child-picker-option')[1] as HTMLButtonElement).click();
    await harness.fixture.whenStable();
    harness.detectChanges();
    expect(TestBed.inject(Router).url).toBe('/schedule?tab=past');
    expect(harness.routeNativeElement).toBe(shell);
    expect(shell.querySelector('.loaded-child')?.textContent).toBe('two');
    expect(shell.querySelector('dialog')).toBeNull();
    expect(TestBed.inject(ChildRouteReuse).refreshingChild).toBeFalse();
  });
});
