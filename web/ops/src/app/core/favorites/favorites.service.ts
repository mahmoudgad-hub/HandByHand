import { Injectable, InjectionToken, computed, inject, signal } from '@angular/core';
import { OpsAuthService } from '../auth/ops-auth.service';
import { NavEntry, OPS_NAV_GROUPS } from '../../layout/shell/nav';

export const FAVORITABLE_SCREENS = OPS_NAV_GROUPS.flatMap(group => group.entries).filter(entry => entry.key !== 'favorites');

export const FAVORITES_STORAGE = new InjectionToken<Storage | null>('Favorites storage', {
  providedIn: 'root', factory: () => { try { return localStorage; } catch { return null; } },
});

/** Browser preferences contain only known screen keys, never record data or URLs. */
@Injectable({ providedIn: 'root' })
export class FavoritesService {
  private readonly auth = inject(OpsAuthService);
  private readonly storage = inject(FAVORITES_STORAGE);
  private readonly memory = signal<Record<string, readonly string[]>>({});
  readonly storageFailed = signal(false);
  private readonly owner = computed(() => {
    const me = this.auth.me();
    return me?.userId && me.centerCode
      ? `hbh.ops.favorites.v1:${encodeURIComponent(me.centerCode)}:${me.userId}` : null;
  });
  private readonly keys = computed(() => {
    const owner = this.owner();
    if (!owner) return [];
    return this.memory()[owner] ?? this.read(owner);
  });
  readonly entries = computed(() => this.keys().flatMap(key => {
    const entry = FAVORITABLE_SCREENS.find(item => item.key === key);
    return entry && this.canOpen(entry) ? [entry] : [];
  }));

  canOpen(entry: NavEntry): boolean {
    return (!entry.needsTherapist || this.auth.me()?.therapistId !== undefined)
      && (this.auth.can(entry.permission) || !!entry.altPermission && this.auth.can(entry.altPermission));
  }

  has(key: string): boolean { return this.entries().some(entry => entry.key === key); }

  toggle(key: string): void {
    const owner = this.owner();
    const entry = FAVORITABLE_SCREENS.find(item => item.key === key);
    if (!owner || !entry || key === 'favorites' || !this.canOpen(entry)) return;
    const keys = this.keys().includes(key) ? this.keys().filter(item => item !== key) : [...this.keys(), key];
    this.memory.update(value => ({ ...value, [owner]: keys }));
    try {
      if (!this.storage) throw new Error('Storage unavailable');
      this.storage.setItem(owner, JSON.stringify(keys));
      this.storageFailed.set(false);
    } catch { this.storageFailed.set(true); }
  }

  pathOf(entry: NavEntry): string {
    const therapist = this.auth.me()?.therapistId;
    return therapist !== undefined ? entry.path.replace('/me/', `/${therapist}/`) : entry.path;
  }

  queryOf(entry: NavEntry): Record<string, string> | null {
    if (entry.key === 'appointments' && !this.auth.can('APPOINTMENT.BOOK') && this.auth.me()?.therapistId !== undefined) {
      return { view: 'mine' };
    }
    return entry.query ? { ...entry.query } : null;
  }

  private read(owner: string): readonly string[] {
    try {
      const parsed: unknown = JSON.parse(this.storage?.getItem(owner) ?? '[]');
      return Array.isArray(parsed) ? [...new Set(parsed.filter((key): key is string =>
        typeof key === 'string' && key !== 'favorites' && FAVORITABLE_SCREENS.some(entry => entry.key === key)))] : [];
    } catch { return []; }
  }
}
