import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { OpsAuthService } from '../auth/ops-auth.service';
import { FAVORITES_STORAGE, FAVORITABLE_SCREENS, FavoritesService } from './favorites.service';

describe('Screen favorites', () => {
  const identity = signal({ userId: 1, centerCode: 'demo', therapistId: 12 as number | undefined });
  const permissions = signal(['PORTAL.VIEW', 'SITE.EDIT', 'SESSION.START']);
  let data: Map<string, string>;
  let storage: { getItem: jasmine.Spy; setItem: jasmine.Spy };
  function mount() {
    TestBed.configureTestingModule({ providers: [
      { provide: OpsAuthService, useValue: { me: identity, can: (p: string) => permissions().includes(p) } },
      { provide: FAVORITES_STORAGE, useValue: storage },
    ] });
    return TestBed.inject(FavoritesService);
  }
  beforeEach(() => {
    identity.set({ userId: 1, centerCode: 'demo', therapistId: 12 });
    permissions.set(['PORTAL.VIEW', 'SITE.EDIT', 'SESSION.START']);
    data = new Map();
    storage = { getItem: jasmine.createSpy().and.callFake((key: string) => data.get(key) ?? null),
      setItem: jasmine.createSpy().and.callFake((key: string, value: string) => data.set(key, value)) };
  });
  it('persists additions across service recreation and removes the same screen without duplicates', () => {
    let service = mount(); service.toggle('site-team');
    expect(service.has('site-team')).toBeTrue();
    TestBed.resetTestingModule(); service = mount();
    expect(service.entries().map(e => e.path)).toEqual(['/site/team']);
    service.toggle('site-team'); expect(service.entries()).toEqual([]);
    expect([...data.values()]).toEqual(['[]']);
  });
  it('isolates preferences by account and centre even when identity changes in one session', () => {
    const service = mount(); service.toggle('dashboard');
    identity.update(me => ({ ...me, userId: 2 })); expect(service.entries()).toEqual([]);
    service.toggle('site');
    identity.update(me => ({ ...me, userId: 1 })); expect(service.has('dashboard')).toBeTrue();
    expect(service.has('site')).toBeFalse();
    identity.update(me => ({ ...me, centerCode: 'other' })); expect(service.entries()).toEqual([]);
  });
  it('hides revoked permissions and cannot add a forbidden or unknown screen', () => {
    const service = mount(); service.toggle('site'); service.toggle('billing'); service.toggle('favorites'); service.toggle('https://example.com');
    expect(service.entries().map(e => e.key)).toEqual(['site']);
    permissions.set(['PORTAL.VIEW']); expect(service.entries()).toEqual([]);
  });
  it('sanitizes storage and tolerates invalid JSON', () => {
    data.set('hbh.ops.favorites.v1:demo:1', JSON.stringify(['site', 'site', null, '/unsafe', 'favorites']));
    const service = mount(); expect(service.entries().map(e => e.key)).toEqual(['site']);
    data.set('hbh.ops.favorites.v1:demo:2', '{broken');
    identity.update(me => ({ ...me, userId: 2 })); expect(service.entries()).toEqual([]);
  });
  it('keeps working in memory and reports when persistence is unavailable', () => {
    storage.setItem.and.throwError('Quota');
    const service = mount(); service.toggle('dashboard');
    expect(service.has('dashboard')).toBeTrue(); expect(service.storageFailed()).toBeTrue();
  });
  it('preserves the clinician diary and own-profile destinations', () => {
    const service = mount();
    expect(service.queryOf(FAVORITABLE_SCREENS.find(e => e.key === 'appointments')!)).toEqual({ view: 'mine' });
    expect(service.pathOf(FAVORITABLE_SCREENS.find(e => e.key === 'my-profile')!)).toBe('/therapists/12/profile');
    service.toggle('my-profile'); identity.update(me => ({ ...me, therapistId: undefined }));
    expect(service.entries()).toEqual([]);
  });
});
