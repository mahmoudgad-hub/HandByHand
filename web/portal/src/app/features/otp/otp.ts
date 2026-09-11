import {
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  AfterViewInit,
  OnDestroy,
  computed,
  inject,
  signal,
  viewChildren,
  viewChild,
} from '@angular/core';
import { Router } from '@angular/router';

import { AuthService } from '../../core/auth/auth.service';
import { OtpFailure } from '../../core/auth/auth-api';
import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { HbhPluralPipe } from '@hbh/shared/format/format.pipes';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';

/**
 * Sign-in, step two: the one-time code.
 *
 * The countdown and the code length here are presentation. The code's real
 * lifetime, its single use, and the lock after repeated failures are enforced
 * where they cannot be edited - in the database function that issues and
 * verifies it. This screen only says what the server already told it.
 *
 * A locked account is a dead end on purpose. Repeating the request will not
 * change the answer, so the boxes are removed rather than left inviting
 * another guess.
 */
@Component({
  selector: 'hbh-otp',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon, TranslatePipe, HbhPluralPipe],
  templateUrl: './otp.html',
  styleUrl: './otp.css',
})
export class Otp implements AfterViewInit, OnDestroy {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  protected readonly config = inject(HBH_CONFIG);

  private readonly boxes = viewChildren<ElementRef<HTMLInputElement>>('box');
  private readonly dialog = viewChild<ElementRef<HTMLDialogElement>>('dialog');
  private ticker: ReturnType<typeof setInterval> | null = null;

  protected readonly challenge = this.auth.pendingChallenge;
  protected readonly maskedMobile = this.auth.maskedMobile;

  /**
   * The one-time code, shown on screen, in development only.
   *
   * There is no SMS gateway. The service generates a real random code and
   * returns it in the response when OTP_ECHO is on - a switch it refuses to
   * start a non-development process with - and until this was displayed the
   * parent portal could not be signed into at all: the code existed, was
   * correct, and was visible to nobody. Guessing 123456 is what a person does
   * next, and it is refused, correctly.
   *
   * TWO CONDITIONS, and both must hold. The service must have echoed a code -
   * production never does - AND the page must be served from a local address.
   * The second is what matters: a build that somehow reached a public host
   * with echoing on still cannot put a working code on the screen.
   *
   * The same discipline as the staff console's sign-in shortcuts, for the
   * same reason.
   */
  protected readonly devCode = computed(() => {
    const code = this.challenge()?.devCode;
    return code && this.isLocal() ? code : '';
  });

  private isLocal(): boolean {
    const host = location.hostname;
    return host === 'localhost'
      || host === '127.0.0.1'
      || host === '[::1]'
      // A centre's own network during a demonstration. Not the internet.
      || /^10\./.test(host)
      || /^192\.168\./.test(host)
      || /^172\.(1[6-9]|2\d|3[01])\./.test(host);
  }

  /** Fills the boxes from the echoed code, so nobody retypes six digits. */
  protected useDevCode(): void {
    const code = this.devCode();
    if (code) {
      this.onInput(0, code);
    }
  }
  /** The template needs it to mark the last box enterkeyhint="go". */
  protected readonly otpLength = this.config.otpLength;

  protected readonly slots = Array.from({ length: this.config.otpLength }, (u, i) => i);
  protected readonly digits = signal<string[]>(new Array(this.config.otpLength).fill(''));
  protected readonly busy = signal(false);
  protected readonly failure = signal<OtpFailure | null>(null);
  protected readonly attemptsLeft = signal<number | null>(null);
  protected readonly secondsLeft = signal(0);

  protected readonly code = computed(() => this.digits().join(''));
  protected readonly complete = computed(() => this.code().length === this.config.otpLength);

  /** A locked account cannot be unlocked by trying again. */
  protected readonly locked = computed(() => {
    const current = this.failure();
    return current === 'TOO_MANY_ATTEMPTS' || current === 'USER_LOCKED';
  });

  /** The message under the boxes, chosen by the service's own code. */
  protected readonly failureKey = computed(() => {
    switch (this.failure()) {
      case 'WRONG_CODE': return 'otp.wrong';
      case 'EXPIRED': return 'otp.expired';
      case 'NO_PENDING_CODE': return 'otp.noPendingCode';
      case 'TOO_MANY_ATTEMPTS': return 'otp.tooManyAttempts';
      case 'USER_LOCKED': return 'otp.userLocked';
      case 'RATE_LIMITED': return 'otp.rateLimited';
      case 'UNKNOWN': return 'error.network';
      default: return '';
    }
  });

  constructor() {
    const pending = this.auth.pendingChallenge();
    if (!pending) {
      // Reached without asking for a code: there is nothing to verify.
      void this.router.navigate(['/login']);
      return;
    }
    this.secondsLeft.set(pending.resendInSeconds);
    this.ticker = setInterval(() => {
      this.secondsLeft.update((value) => (value > 0 ? value - 1 : 0));
    }, 1000);
  }

  /**
   * Put the caret in the first box.
   *
   * This screen is only ever reached by a router navigation from sign-in, so
   * the autofocus attribute never fires for it: the browser honours that
   * attribute when the parser meets the element, and by then this document
   * finished parsing. Without this the parent lands on six empty boxes and
   * has to tap one before a single digit can be typed - with the code
   * already sitting in their notifications.
   *
   * A locked account renders no boxes at all; the optional chain in focus()
   * is what makes that a no-op rather than a crash on the one screen a
   * parent reaches while already blocked.
   */
  ngAfterViewInit(): void {
    if (this.challenge()) this.dialog()?.nativeElement.showModal();
    this.focus(0);
  }

  ngOnDestroy(): void {
    this.dialog()?.nativeElement.close();
    if (this.ticker) {
      clearInterval(this.ticker);
    }
  }

  /** "00:47" - Latin digits, and the element is dir="ltr" in the template. */
  protected get countdown(): string {
    const value = this.secondsLeft();
    const minutes = String(Math.floor(value / 60)).padStart(2, '0');
    const seconds = String(value % 60).padStart(2, '0');
    return `${minutes}:${seconds}`;
  }

  /**
   * One box changed - or, on the first box, the whole code arrived at once.
   *
   * iOS fills the SMS code into the single field that carries
   * autocomplete="one-time-code", which is box one. That delivers six
   * digits to a handler that used to keep only the last of them, so the
   * autofill left "2" in the first box and dropped the rest. Anything
   * longer than one digit is spread across the boxes from here.
   */
  protected onInput(index: number, raw: string): void {
    const digits = raw.replace(/\D/g, '');
    if (digits.length > 1) {
      this.fillFrom(index, digits);
      return;
    }
    this.setDigit(index, digits);
    if (digits && index + 1 < this.config.otpLength) {
      this.focus(index + 1);
    }
    if (this.complete()) {
      this.submit();
    }
  }

  /**
   * Write a run of digits into the boxes starting at `from`, then put the
   * cursor after the last one written. Shared by autofill and paste,
   * because a code that arrives whole should behave the same either way.
   */
  private fillFrom(from: number, digits: string): void {
    const room = this.config.otpLength - from;
    const run = digits.slice(0, room);
    const next = [...this.digits()];
    for (let i = 0; i < run.length; i++) {
      next[from + i] = run[i];
    }
    this.digits.set(next);
    this.syncBoxes();
    this.focus(Math.min(from + run.length, this.config.otpLength - 1));
    if (this.complete()) {
      this.submit();
    }
  }

  protected onKeydown(index: number, event: KeyboardEvent): void {
    if (event.key === 'Backspace' && !this.digits()[index] && index > 0) {
      this.focus(index - 1);
    }
  }

  /**
   * A code arrives as one SMS line; pasting it must fill every box.
   *
   * From box one, not from wherever the caret happened to be: a pasted code
   * is the whole code. Shares fillFrom with autofill so the two paths cannot
   * drift - they were separate copies of the same loop, and only one of them
   * would have been fixed.
   */
  protected onPaste(event: ClipboardEvent): void {
    const pasted = event.clipboardData?.getData('text') ?? '';
    const digits = pasted.replace(/\D/g, '');
    if (!digits) {
      return;
    }
    event.preventDefault();
    this.fillFrom(0, digits);
  }

  protected submit(): void {
    if (!this.complete() || this.busy() || this.locked()) {
      return;
    }
    this.busy.set(true);
    this.failure.set(null);
    this.auth.verifyOtp(this.code()).subscribe({
      next: () => {
        this.busy.set(false);
        void this.router.navigate(['/welcome']);
      },
      error: (error: unknown) => {
        const refusal = this.auth.readRefusal(error);
        this.busy.set(false);
        this.failure.set(refusal.failure);
        this.attemptsLeft.set(refusal.attemptsLeft);
        this.digits.set(new Array(this.config.otpLength).fill(''));
        this.syncBoxes();
        if (!this.locked()) {
          this.focus(0);
        }
      },
    });
  }

  /**
   * Both "change the number" and "send another code" start over at sign-in.
   * The portal holds the number only while a code is outstanding, and asking
   * again is a fresh request either way.
   */
  protected restart(): void {
    if (this.busy()) return;
    this.auth.abandonChallenge();
    void this.router.navigate(['/login']);
  }

  protected cancel(event: Event): void {
    event.preventDefault();
    this.restart();
  }

  private setDigit(index: number, digit: string): void {
    this.digits.update((current) => {
      const next = [...current];
      next[index] = digit;
      return next;
    });
  }

  /** The boxes are uncontrolled inputs; this pushes state back into them. */
  private syncBoxes(): void {
    const values = this.digits();
    this.boxes().forEach((box, index) => {
      box.nativeElement.value = values[index] ?? '';
    });
  }

  private focus(index: number): void {
    this.boxes()[index]?.nativeElement.focus();
  }
}
