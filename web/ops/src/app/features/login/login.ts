import {
  ChangeDetectionStrategy, Component, computed, inject, signal,
} from '@angular/core';
import { FormControl, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { HttpClient } from '@angular/common/http';

import { DevAccount, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { readRefusal } from '../../core/api/ops-error';
import { OpsAuthService } from '../../core/auth/ops-auth.service';

/**
 * Staff sign-in: username and password, one step.
 *
 * Every rule behind it is hbh.verify_password's - the attempt counter that
 * survives a refusal, the lock after LOGIN_MAX_ATTEMPTS, and one identical
 * answer for "no such account" and "wrong password" so this box cannot be
 * used to find out who works here. This screen shows what came back.
 */
@Component({
  selector: 'hbh-login',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [ReactiveFormsModule, Icon, TranslatePipe],
  templateUrl: './login.html',
  styleUrl: './login.css',
})
export class Login {
  private readonly auth = inject(OpsAuthService);
  private readonly router = inject(Router);
  private readonly http = inject(HttpClient);
  protected readonly config = inject(HBH_CONFIG);

  // ---- setting a first password from a code --------------------------
  //
  // This is on the SIGN-IN screen and not behind it, because the person
  // using it cannot sign in yet - the account exists with no password.
  // The code their administrator handed them is the authorisation, which
  // is why the service makes it single use, expiring and counted.
  //
  // No "current password" field: there is nothing to confirm against. A
  // person who already has one changes it from inside the console.

  protected readonly setupOpen = signal(false);
  protected readonly setupCode = new FormControl('', { nonNullable: true });
  protected readonly setupPassword = new FormControl('', { nonNullable: true });
  protected readonly setupBusy = signal(false);
  protected readonly setupError = signal('');
  protected readonly setupDone = signal(false);

  protected toggleSetup(): void {
    this.setupOpen.update((v) => !v);
    this.setupError.set('');
    this.setupDone.set(false);
  }

  protected redeemSetup(): void {
    const username = this.username.value.trim();
    const code = this.setupCode.value.trim();
    const password = this.setupPassword.value;
    if (!username || !code || !password) {
      // The username comes from the field above rather than a second copy
      // of it: two boxes asking the same question is how one of them ends
      // up holding something different from the other.
      this.setupError.set('login.setupNeedsAll');
      return;
    }
    this.setupBusy.set(true);
    this.setupError.set('');
    this.http.post(`${this.config.apiBaseUrl}/api/v1/auth/password-setup`,
      { username, setup_code: code, password })
      .subscribe({
        next: () => {
          this.setupBusy.set(false);
          this.setupDone.set(true);
          this.setupCode.setValue('');
          this.setupPassword.setValue('');
          // Not signed in automatically. Typing the new password once more
          // is how somebody finds out immediately that they mistyped it -
          // rather than at the start of their next shift.
          this.password.setValue('');
        },
        error: (error: unknown) => {
          this.setupBusy.set(false);
          const refusal = readRefusal(error);
          this.setupError.set(`error.${refusal.failure}`);
        },
      });
  }

  protected readonly username = new FormControl('', {
    nonNullable: true, validators: [Validators.required],
  });
  protected readonly password = new FormControl('', {
    nonNullable: true, validators: [Validators.required],
  });

  protected readonly busy = signal(false);
  protected readonly shown = signal(false);
  protected readonly errorKey = signal('');

  /**
   * The development sign-in shortcuts, or nothing.
   *
   * Two conditions, and both must hold. The config must list accounts - a
   * production config lists none - and the page must be served from a local
   * address. The second is the one that matters: it means a build that
   * accidentally kept the list still cannot show working credentials from a
   * public host.
   */
  protected readonly devAccounts = computed(() =>
    this.isLocal() ? this.config.devAccounts : []);

  /**
   * Whether two of the shortcuts open the SAME account under different role
   * names - which they do: "admin" and "centre manager" are one role here.
   *
   * The note explaining that was guarded by
   * `devAccounts().length !== config.devAccounts.length`, and that condition
   * can only be true when devAccounts() is EMPTY - which is exactly when the
   * whole block is not rendered. So the sentence never appeared once, and the
   * key it was meant to show (`login.devSameRole`) was referenced by nothing.
   *
   * This asks the question the comment above the block actually asks: do two
   * buttons lead to the same place? If somebody later gives every shortcut
   * its own account, the note stops showing on its own.
   */
  protected readonly devSharesAccount = computed(() => {
    const names = this.devAccounts().map((account) => account.username);
    return new Set(names).size !== names.length;
  });

  /**
   * Which shortcut is selected, keyed by role and not by username.
   *
   * Two buttons can point at the same account - "admin" and "centre manager"
   * are one role here - and keying this by username would light both when
   * either is pressed.
   */
  protected readonly picked = signal<string | null>(null);

  private isLocal(): boolean {
    const host = location.hostname;
    return host === 'localhost'
      || host === '127.0.0.1'
      || host === '[::1]'
      // A centre's own LAN during a demo. Not the public internet.
      || /^10\./.test(host)
      || /^192\.168\./.test(host)
      || /^172\.(1[6-9]|2\d|3[01])\./.test(host);
  }

  /**
   * Fills the form from a shortcut and signs in. It fills the fields rather
   * than posting straight through, so what is being sent is visible - a
   * button that silently authenticates teaches nobody which account they are
   * looking at.
   */
  protected useDevAccount(account: DevAccount): void {
    if (account.unavailableKey || this.busy()) {
      return;
    }
    this.picked.set(account.roleKey);
    this.username.setValue(account.username);
    this.password.setValue(account.password);
    this.errorKey.set('');
    this.submit();
  }

  private focus(id: string): void {
    document.getElementById(id)?.focus();
  }

  protected togglePeek(): void {
    this.shown.update((value) => !value);
  }

  protected submit(event?: Event): void {
    event?.preventDefault();
    if (this.busy()) {
      return;
    }
    // Name the field that is missing, and put the cursor in it. "Enter your
    // username and password" in front of a form where one of them is already
    // filled makes the person read both to find which - and on the static
    // prototype it read as a bug when placeholders made empty fields look
    // full.
    if (this.username.invalid) {
      this.errorKey.set('login.usernameRequired');
      this.focus('f-user');
      return;
    }
    if (this.password.invalid) {
      this.errorKey.set('login.passwordRequired');
      this.focus('f-pass');
      return;
    }

    this.busy.set(true);
    this.errorKey.set('');
    this.auth.signIn(this.username.value.trim(), this.password.value).subscribe({
      next: () => {
        // The identity is fetched before leaving, so the shell never draws a
        // frame with an empty menu and a nameless user.
        this.auth.loadIdentity().subscribe({
          next: () => {
            this.busy.set(false);
            void this.router.navigate(['/dashboard']);
          },
          // The password was accepted but the identity could not be read.
          // Same treatment as any other failure: name what happened rather
          // than blaming the credentials, which were right.
          error: (error: unknown) => {
            this.busy.set(false);
            this.errorKey.set(this.messageFor(error));
          },
        });
      },
      error: (error: unknown) => {
        this.busy.set(false);
        this.password.setValue('');
        this.errorKey.set(this.messageFor(error));
      },
    });
  }

  /**
   * One message for every refusal the server does not distinguish between.
   * Only a locked account gets its own, because it is the one a person can
   * act on - and only reception can clear it.
   */
  private messageFor(error: unknown): string {
    const status = (error as { status?: number })?.status;
    // Status 0 is not a refusal - the request never arrived. The service was
    // restarting, or the network dropped. Calling that "an unexpected error"
    // sends someone hunting for a password problem they do not have.
    if (status === 0 || status === undefined) {
      return 'error.connection';
    }
    if (status === 423) {
      return 'login.locked';
    }
    if (status === 429) {
      return 'error.RATE_LIMITED';
    }
    if (status === 401) {
      return 'login.badCredentials';
    }
    return `error.${readRefusal(error).failure}`;
  }
}
