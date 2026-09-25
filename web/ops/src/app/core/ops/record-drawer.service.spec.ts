import { Location } from '@angular/common';
import { provideLocationMocks } from '@angular/common/testing';
import { TestBed } from '@angular/core/testing';
import { Router, provideRouter } from '@angular/router';

import { DrawerTarget } from './record-drawer';
import { RecordDrawerService } from './record-drawer.service';

/**
 * The address bar is the one source of truth for "a drawer is open".
 * Opening writes it, the back button and a pasted link read it, closing
 * rewrites it - and the service's state follows the address every time.
 */
describe('RecordDrawerService', () => {
  let router: Router;
  let location: Location;

  const ROW = { appointment_id: 881, status: 'BOOKED' };

  beforeEach(async () => {
    TestBed.configureTestingModule({
      providers: [provideRouter([{ path: '**', children: [] }]), provideLocationMocks()],
    });
    router = TestBed.inject(Router);
    location = TestBed.inject(Location);
    await router.navigateByUrl('/tasks');
  });

  function svc(): RecordDrawerService {
    return TestBed.inject(RecordDrawerService);
  }

  it('keeps the appointment instant in copied links and removes it for another entity', async () => {
    const service = svc();
    await service.open({ entity: 'appointment', id: 881, row: {
      ...ROW, starts_at: '2026-08-20T10:00:00Z',
    }, source: 'LIST' });
    expect(router.parseUrl(router.url).queryParams['recordAt']).toBe('2026-08-20T10:00:00.000Z');
    await service.open({ entity: 'invoice', id: 12, source: 'LIST' });
    expect(router.parseUrl(router.url).queryParams['recordAt']).toBeUndefined();
  });

  it('opens on a row, writes ?open= (and the step) to the address, and reads nothing', async () => {
    const s = svc();
    const written = s.open({ entity: 'appointment', id: 881, row: ROW, action: 'confirm', source: 'TASK_INBOX' });
    expect(s.active()?.target).toEqual({ entity: 'appointment', id: 881 });
    expect(s.active()?.row).toBe(ROW);
    expect(s.active()?.action).toBe('confirm');
    expect(s.active()?.pushed).toBeTrue();
    await written;
    expect(router.url).toContain('open=appointment:881');
    // The step lives in the state, never in the address it wrote.
    expect(router.url).not.toContain('action=');
    expect(router.url).toContain('/tasks');
  });

  it('closes a drawer it pushed by stepping back, so back and X agree', async () => {
    const s = svc();
    spyOn(location, 'back').and.callThrough();
    await s.open({ entity: 'invoice', id: 12, source: 'LIST' });
    await s.close();
    expect(location.back).toHaveBeenCalled();
  });

  it('closes when the address stops naming it - the back button, or a navigation elsewhere', async () => {
    const s = svc();
    await s.open({ entity: 'invoice', id: 12, source: 'LIST' });
    expect(s.active()).not.toBeNull();
    await router.navigateByUrl('/children/5');
    expect(s.active()).toBeNull();
  });

  it('opens from the address alone: a deep link, or a refresh', async () => {
    await router.navigateByUrl('/children/5?tab=appointments&open=appointment:70&action=start');
    const s = svc();
    expect(s.active()?.target).toEqual({ entity: 'appointment', id: 70 });
    expect(s.active()?.action).toBe('start');
    expect(s.active()?.source).toBe('DEEP_LINK');
    expect(s.active()?.pushed).toBeFalse();
    expect(s.active()?.row).toBeNull();
  });

  it('ignores an open value it cannot parse, and a step name it does not know', async () => {
    const s = svc();
    await router.navigateByUrl('/tasks?open=foo');
    expect(s.active()).toBeNull();
    await router.navigateByUrl('/tasks?open=appointment:abc');
    expect(s.active()).toBeNull();
    await router.navigateByUrl('/tasks?open=appointment:5&action=delete');
    expect(s.active()?.target.id).toBe(5);
    expect(s.active()?.action).toBeUndefined();
  });

  it('closes a drawer that arrived in the address by rewriting the address in place', async () => {
    await router.navigateByUrl('/tasks?open=invoice:12&action=issue');
    const s = svc();
    spyOn(location, 'back').and.callThrough();
    expect(s.active()).not.toBeNull();
    await s.close();
    expect(location.back).not.toHaveBeenCalled();
    expect(router.url).toBe('/tasks');
    expect(s.active()).toBeNull();
  });

  it('consumes the step off the address and keeps the drawer open', async () => {
    await router.navigateByUrl('/tasks?open=invoice:12&action=issue');
    const s = svc();
    await s.consumeAction();
    expect(router.url).toBe('/tasks?open=invoice:12');
    expect(s.active()?.action).toBeUndefined();
    expect(s.active()?.target.id).toBe(12);
  });

  it('remembers a handed row for the next open, and forgets it once the record changed', async () => {
    const s = svc();
    await s.open({ entity: 'appointment', id: 881, row: ROW, source: 'LIST' });
    await s.close();
    await router.navigateByUrl('/tasks');
    expect(s.active()).toBeNull();
    await router.navigateByUrl('/tasks?open=appointment:881');
    expect(s.active()?.row).toBe(ROW);
    const changed: DrawerTarget[] = [];
    s.changed$.subscribe((target) => changed.push(target));
    s.notifyChanged({ entity: 'appointment', id: 881 });
    expect(changed).toEqual([{ entity: 'appointment', id: 881 }]);
    expect(s.active()?.row).toBeNull();
  });

  it('a second open replaces the first without a second history entry', async () => {
    const s = svc();
    await s.open({ entity: 'appointment', id: 1, source: 'LIST' });
    const navigate = spyOn(router, 'navigateByUrl').and.callThrough();
    s.open({ entity: 'appointment', id: 2, source: 'LIST' });
    expect(navigate.calls.mostRecent().args[1]).toEqual(jasmine.objectContaining({ replaceUrl: true }));
    expect(s.active()?.target.id).toBe(2);
    expect(s.active()?.pushed).toBeTrue();
  });
});
