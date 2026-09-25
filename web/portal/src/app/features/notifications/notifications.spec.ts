import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';
import { of, Subject } from 'rxjs';
import { HBH_CONFIG, DEFAULT_HBH_CONFIG } from '@hbh/shared/config/app-config';
import { ChildContextService } from '../../core/auth/child-context.service';
import { PortalApi } from '../../core/api/portal-api';
import { Child, PortalNotification } from '../../core/models/portal.models';
import { Notifications } from './notifications';

describe('Notification family context', () => {
  const item: PortalNotification = { id: '1', kind: 'NOTE_PUBLISHED', title: 'ملاحظة', body: null,
    childId: '8', childName: 'طفل', createdAt: '2026-09-14T10:00:00Z', read: false,
    target: ['/progress'], targetQuery: { tab: 'notes' } };
  let family: Subject<{ children: Child[] }>;
  let select: jasmine.Spy;
  let navigate: jasmine.Spy;
  let markRead: jasmine.Spy;

  beforeEach(() => {
    family = new Subject();
    select = jasmine.createSpy();
    navigate = jasmine.createSpy().and.returnValue(Promise.resolve(true));
    markRead = jasmine.createSpy().and.returnValue(of(undefined));
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting(),
      { provide: HBH_CONFIG, useValue: DEFAULT_HBH_CONFIG },
      { provide: Router, useValue: { navigate } },
      { provide: ChildContextService, useValue: { select } },
      { provide: PortalApi, useValue: {
        notifications: () => of({ rows: [item], unread: 1, total: 1 }),
        family: () => family, markNotificationRead: markRead,
      } },
    ] });
  });

  function open() {
    const fixture = TestBed.createComponent(Notifications);
    fixture.detectChanges();
    (fixture.nativeElement.querySelector('.nrow') as HTMLButtonElement).click();
    fixture.detectChanges();
    return fixture;
  }

  it('waits for the authorized family and selects the notification child before navigating', async () => {
    const fixture = open();
    expect(navigate).not.toHaveBeenCalled();
    expect((fixture.nativeElement.querySelector('.nrow') as HTMLButtonElement).disabled).toBeTrue();
    const sibling = { id: '7', name: 'طفل' } as unknown as Child;
    const target = { id: '8', name: 'طفل' } as unknown as Child;
    navigate.and.callFake(() => {
      expect(select).toHaveBeenCalledWith(target);
      return Promise.resolve(true);
    });
    family.next({ children: [sibling, target] });
    await fixture.whenStable();
    expect(navigate).toHaveBeenCalledWith(['/progress'], { queryParams: { tab: 'notes' } });
    expect(markRead).toHaveBeenCalledWith('1');
  });

  it('does not open a sibling when access to the notification child has gone', () => {
    const fixture = open();
    family.next({ children: [{ id: '7' } as Child] });
    fixture.detectChanges();
    expect(navigate).not.toHaveBeenCalled();
    expect(select).not.toHaveBeenCalled();
    expect(markRead).not.toHaveBeenCalled();
    expect(fixture.nativeElement.querySelector('[role=alert]')).not.toBeNull();
  });

  it('keeps the item available for retry when the family lookup fails', () => {
    const fixture = open();
    family.error(new Error('offline'));
    fixture.detectChanges();
    expect(navigate).not.toHaveBeenCalled();
    expect((fixture.nativeElement.querySelector('.nrow') as HTMLButtonElement).disabled).toBeFalse();
    expect(fixture.nativeElement.querySelector('[role=alert]')).not.toBeNull();
  });
});

/**
 * "Mark all read" (#24).
 *
 * The behaviour worth holding down is not the happy path - it is that this
 * one is NOT optimistic. The parent is looking at the list while it runs, so
 * a failure that silently leaves the dots cleared would be the screen
 * telling them something it knows is untrue.
 */
describe('Marking the whole feed read', () => {
  const unread = (id: string): PortalNotification => ({
    id, kind: 'REPORT_PUBLISHED', title: 'تقرير', body: null, childId: null,
    childName: null, createdAt: '2026-09-14T10:00:00Z', read: false,
    target: null, targetQuery: undefined,
  } as unknown as PortalNotification);

  let markAll: Subject<number>;

  const start = () => {
    markAll = new Subject();
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting(),
      { provide: HBH_CONFIG, useValue: DEFAULT_HBH_CONFIG },
      { provide: Router, useValue: { navigate: jasmine.createSpy() } },
      { provide: ChildContextService, useValue: { select: jasmine.createSpy() } },
      { provide: PortalApi, useValue: {
        notifications: () => of({ rows: [unread('1'), unread('2')], unread: 2, total: 2 }),
        family: () => of({ children: [] }),
        markNotificationRead: () => of(undefined),
        markAllNotificationsRead: () => markAll,
      } },
    ] });
    const fixture = TestBed.createComponent(Notifications);
    fixture.detectChanges();
    return fixture;
  };

  const button = (fixture: ReturnType<typeof start>) =>
    fixture.nativeElement.querySelector('.nlist__all') as HTMLButtonElement;

  it('clears the dots only once the service has answered', () => {
    const fixture = start();
    expect(fixture.nativeElement.querySelectorAll('.nrow--unread').length).toBe(2);

    button(fixture).click();
    fixture.detectChanges();
    // In flight: nothing has changed on screen yet, and a second tap cannot
    // be sent.
    expect(fixture.nativeElement.querySelectorAll('.nrow--unread').length).toBe(2);
    expect(button(fixture).disabled).toBeTrue();

    markAll.next(2);
    markAll.complete();
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelectorAll('.nrow--unread').length).toBe(0);
    // The badge and the button go with the count they described.
    expect(fixture.nativeElement.querySelector('.nlist__all')).toBeNull();
  });

  it('says so and leaves the feed alone when the write fails', () => {
    const fixture = start();
    button(fixture).click();
    fixture.detectChanges();

    markAll.error(new Error('offline'));
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelectorAll('.nrow--unread').length).toBe(2);
    expect(fixture.nativeElement.querySelector('[role=alert]')).not.toBeNull();
    // Offered again, not left spinning.
    expect(button(fixture).disabled).toBeFalse();
  });
});
