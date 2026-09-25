import { Component, Injectable, Injector, DestroyRef, computed, effect, inject, input, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Subscription, switchMap, tap } from 'rxjs';
import { HBH_CONFIG } from '../config/app-config';

@Injectable({ providedIn: 'root' })
export class UserAvatars {
  private readonly injector = inject(Injector);
  private get http() { return this.injector.get(HttpClient); }
  private get base() { return this.injector.get(HBH_CONFIG).apiBaseUrl; }
  readonly urls = signal<Record<number, string>>({});
  readonly viewer = signal<number | null>(null);
  private requested = new Map<number, number>();
  private requests = new Map<number, Subscription>();
  private generation = 0;
  constructor() { inject(DestroyRef).onDestroy(() => this.reset(null)); }
  reset(viewer: number | null): void {
    if (this.viewer() === viewer) {
      return;
    }
    this.generation++;
    this.requests.forEach(request => request.unsubscribe());
    this.requests.clear();
    Object.values(this.urls()).forEach(url => URL.revokeObjectURL(url));
    this.urls.set({});
    this.requested.clear();
    this.viewer.set(viewer);
  }
  load(id: number | null, refresh = false): void {
    if (!id || (!refresh && Date.now() - (this.requested.get(id) ?? 0) < 60000)) return;
    this.requested.set(id, Date.now());
    this.requests.get(id)?.unsubscribe();
    const generation = this.generation;
    this.requests.set(id, this.http.get(`${this.base}/api/v1/users/${id}/photo`, { responseType: 'blob' }).subscribe({
      next: blob => { if(generation === this.generation) this.replace(id, blob); },
      error: (error) => { if (generation === this.generation && error.status === 404) this.clear(id); },
    }));
  }
  clear(id: number): void {
    this.requests.get(id)?.unsubscribe();
    const old = this.urls()[id];
    this.urls.update(urls => { const next = { ...urls }; delete next[id]; return next; });
    this.requested.delete(id);
    if (old) URL.revokeObjectURL(old);
  }
  private replace(id: number, blob: Blob): void {
    const old = this.urls()[id];
    this.urls.update(urls => ({ ...urls, [id]: URL.createObjectURL(blob) }));
    if(old) URL.revokeObjectURL(old);
  }
  save(id: number, blob: Blob) {
    const generation = this.generation;
    const form = new FormData();
    form.append('file', blob, 'photo.' + (blob.type === 'image/png' ? 'png' : blob.type === 'image/webp' ? 'webp' : 'jpg'));
    return this.http.post(`${this.base}/api/v1/users/${id}/photo`, form).pipe(
      switchMap(() => this.http.get(`${this.base}/api/v1/users/${id}/photo`, { responseType: 'blob' })),
      tap(savedPhoto => {
      if(generation === this.generation) { this.requests.get(id)?.unsubscribe(); this.requested.set(id, Date.now()); this.replace(id, savedPhoto); }
    }));
  }
}

@Component({
  selector: 'hbh-user-avatar',
  template: `@if(url(); as src) {<img [src]="src" alt="" (error)="failed.set(src)">} @else {<span>{{ initials() }}</span>}`,
  styles: [`:host{display:inline-grid;place-items:center;width:100%;height:100%;min-width:0;overflow:hidden;border-radius:50%;background:#dceff0;color:#087381;font-weight:700;vertical-align:middle}img{display:block;width:100%;height:100%;object-fit:cover}span{font-size:inherit}`],
})
export class UserAvatar {
  readonly userId = input<number | null | undefined>();
  readonly name = input('');
  protected readonly avatars = inject(UserAvatars);
  protected readonly failed = signal('');
  protected readonly url = computed(() => {
    const src = this.avatars.urls()[this.userId() ?? 0];
    return src !== this.failed() ? src : null;
  });
  protected readonly initials = computed(() => this.name().trim().split(/\s+/).slice(0,2).map(part => Array.from(part)[0] ?? '').join('') || '•');
  constructor() { effect(() => { this.avatars.viewer(); this.avatars.load(this.userId() ?? null); }); }
}
