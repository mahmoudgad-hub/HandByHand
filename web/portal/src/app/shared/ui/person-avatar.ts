import { ChangeDetectionStrategy, Component, computed, effect, inject, input, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { Icon } from '@hbh/shared/icon/icon';
import { personAvatarChoice } from '@hbh/shared/ui/person-avatar-choice';

@Component({
  selector: 'hbh-person-avatar',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon],
  host: { '[class.female]': "gender() === 'F'", '[class.male]': "gender() === 'M'", 'aria-hidden': 'true' },
  template: `@if (source(); as src) { <img [src]="src" alt="" (error)="failed.set(src)"> } @else { <hbh-icon name="ic-user" /> }`,
  styles: [`:host{display:inline-flex;align-items:center;justify-content:center;flex:none;width:48px;height:48px;overflow:hidden;border-radius:50%;background:#edf0f2;color:#637581}:host(.female){background:#ffebf1;color:#dc587f}:host(.male){background:#e5f6fc;color:#138eb2}img{display:block;width:100%;height:100%;object-fit:cover}hbh-icon{width:45%;height:45%}`],
})
export class PersonAvatar {
  readonly childId = input.required<string>();
  readonly gender = input('');
  readonly birthDate = input('');
  private readonly http = inject(HttpClient);
  private readonly config = inject(HBH_CONFIG);
  private readonly photo = signal('');
  protected readonly failed = signal('');
  private readonly fallback = computed(() => {
    const choice = personAvatarChoice(this.gender(), this.birthDate());
    return choice ? `assets/avatars/${choice}.png` : '';
  });
  protected readonly source = computed(() => {
    const photo = this.photo();
    if (photo && photo !== this.failed()) return photo;
    const fallback = this.fallback();
    return fallback !== this.failed() ? fallback : '';
  });
  constructor() {
    effect(onCleanup => {
      const id = this.childId();
      this.photo.set('');
      this.failed.set('');
      if (!id || this.config.useFixtures) return;
      let objectUrl = '';
      const request = this.http.get(`${this.config.apiBaseUrl}/api/v1/children/${encodeURIComponent(id)}/photo`, { responseType: 'blob' }).subscribe({
        next: blob => { objectUrl = URL.createObjectURL(blob); this.photo.set(objectUrl); },
        error: () => { /* No accessible photo: keep the demographic fallback. */ },
      });
      onCleanup(() => { request.unsubscribe(); if (objectUrl) URL.revokeObjectURL(objectUrl); });
    });
  }
}
