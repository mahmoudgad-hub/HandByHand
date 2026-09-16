import { ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { HttpClient } from '@angular/common/http';
import { FormControl, ReactiveFormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { Icon } from '@hbh/shared/icon/icon';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { readRefusal, refusalKey } from '../../core/api/ops-error';
import { UserAvatar } from '@hbh/shared/ui/user-avatar';
import { AvatarEditor } from '@hbh/shared/ui/avatar-editor';

@Component({
  selector: 'hbh-my-profile',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, ReactiveFormsModule, Icon, TranslatePipe, UserAvatar, AvatarEditor],
  templateUrl: './my-profile.html',
  styleUrl: './my-profile.css',
})
export class MyProfile {
  protected readonly auth = inject(OpsAuthService);
  private readonly http = inject(HttpClient);
  private readonly destroyRef = inject(DestroyRef);
  private readonly base = inject(HBH_CONFIG).apiBaseUrl;
  protected readonly passwordEnabled = computed(() => ['STAFF', 'THERAPIST'].includes(this.auth.me()?.userType ?? ''));
  protected readonly roleLabelKey = computed(() => this.auth.roleLabelKey(this.auth.me()));
  protected readonly currentPassword = new FormControl('', { nonNullable: true });
  protected readonly newPassword = new FormControl('', { nonNullable: true });
  protected readonly confirmPassword = new FormControl('', { nonNullable: true });
  protected readonly busy = signal(false);
  protected readonly error = signal('');
  protected readonly done = signal(false);

  constructor() {
    // Re-read the user record when opening My Account after an administration edit.
    this.auth.loadIdentity().pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      error: error => this.error.set(refusalKey(readRefusal(error))),
    });
  }

  protected changePassword(): void {
    if (this.busy() || !this.passwordEnabled()) return;
    this.error.set('');
    this.done.set(false);
    const current = this.currentPassword.value;
    const next = this.newPassword.value;
    if (!current || !next || !this.confirmPassword.value) { this.error.set('error.field.REQUIRED'); return; }
    if (Array.from(next).length < 10) { this.error.set('error.PASSWORD_TOO_SHORT'); return; }
    if (next !== this.confirmPassword.value) { this.error.set('profile.passwordMismatch'); return; }
    this.busy.set(true);
    this.http.post(`${this.base}/api/v1/auth/password`, { current_password: current, new_password: next })
      .pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
        next: () => {
          this.busy.set(false);
          this.done.set(true);
          this.currentPassword.reset();
          this.newPassword.reset();
          this.confirmPassword.reset();
        },
        error: error => { this.busy.set(false); this.error.set(refusalKey(readRefusal(error))); },
      });
  }
}
