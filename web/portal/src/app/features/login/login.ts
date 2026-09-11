import {
  AfterViewInit,
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  inject,
  signal,
  viewChild,
} from '@angular/core';
import { FormControl, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router, RouterOutlet } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';
import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';

/**
 * Sign-in, step one: the mobile number already on the child's file.
 *
 * A number the centre does not know is now told so, and stays on this screen.
 * It did not used to be: the service answered identically either way, so a
 * parent with no file was sent on to the code screen to wait for an SMS that
 * was never coming, with nothing to explain it. What that costs in return -
 * this screen can now be used to ask whether a family attends the centre - is
 * set out in full at `otpRequestOut` in api/internal/http/auth_handlers.go.
 * The owner made that call on 2026-09-05.
 *
 * The message is paired with the enrolment link rather than left as a bare
 * refusal, because "you are not registered" with no next step is the same
 * dead end wearing different words.
 */
@Component({
  selector: 'hbh-login',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [ReactiveFormsModule, Icon, TranslatePipe, RouterOutlet],
  templateUrl: './login.html',
  styleUrl: './login.css',
})
export class Login implements AfterViewInit {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  protected readonly config = inject(HBH_CONFIG);

  private readonly phoneBox = viewChild<ElementRef<HTMLInputElement>>('phoneBox');

  /**
   * Put the caret in the field.
   *
   * The autofocus attribute alone is not enough here. The browser honours it
   * when the parser meets the element on a document load; this screen is also
   * reached by a router navigation - from the guard, from sign-out, from the
   * code screen going back - and then the input is inserted into a document
   * that finished parsing long ago. The attribute is kept for the hard load
   * and this runs for every other way in.
   *
   * One field, one purpose: nothing is skipped past by focusing it.
   */
  ngAfterViewInit(): void {
    this.phoneBox()?.nativeElement.focus();
  }

  protected readonly phone = new FormControl('', {
    nonNullable: true,
    validators: [
      Validators.required,
      Validators.pattern(inject(HBH_CONFIG).phonePattern),
    ],
  });

  protected readonly busy = signal(false);
  protected readonly failed = signal(false);
  protected readonly showError = signal(false);

  /**
   * Why no code is coming, when none is.
   *
   * Empty while nothing has been asked, or while a code really was sent.
   *
   * Two reasons and two different sentences, because they lead two different
   * ways: a number on no child's file should fill in an application, and a
   * family whose application is already on the desk should do NOTHING except
   * wait. Telling the second one to apply would have them fill the same form
   * twice and wonder which one the centre is reading.
   */
  protected readonly noCode = signal<'' | 'NOT_REGISTERED' | 'ENROLMENT_PENDING'>('');

  protected submit(event?: Event): void {
    event?.preventDefault();
    this.showError.set(true);
    if (this.phone.invalid || this.busy()) {
      return;
    }
    this.busy.set(true);
    this.failed.set(false);
    this.noCode.set('');
    this.auth.requestOtp(this.phone.value).subscribe({
      next: (challenge) => {
        this.busy.set(false);
        if (challenge.outcome !== 'SENT') {
          this.noCode.set(challenge.outcome);
          return;
        }
        void this.router.navigate(['/login/otp']);
      },
      error: () => {
        this.busy.set(false);
        this.failed.set(true);
      },
    });
  }

  /** Digits only, so a pasted number with spaces or a country code still fits. */
  protected onInput(value: string): void {
    // The refusal named the number that was sent. Once it is being edited it
    // no longer describes what is on screen, and leaving it there reads as a
    // verdict on the digits being typed now.
    this.noCode.set('');
    const digits = value.replace(/\D/g, '').slice(0, 11);
    if (digits !== value) {
      this.phone.setValue(digits);
    }
  }

  /**
   * The enrolment form, for a family with no file.
   *
   * They cannot sign in - this screen only knows numbers already on a child's
   * record - so the only honest thing to offer them is a way to apply.
   */
  protected goToApply(): void {
    void this.router.navigate(['/apply']);
  }
}
