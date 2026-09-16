import {
  AfterViewInit,
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  effect,
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

import { PHONE_COUNTRIES, PhoneCountry } from './phone-countries';

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
  host: { '(document:click)': 'onDocumentClick($event)' },
})
export class Login implements AfterViewInit {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  protected readonly config = inject(HBH_CONFIG);

  private readonly phoneBox = viewChild<ElementRef<HTMLInputElement>>('phoneBox');
  private readonly countryPicker = viewChild<ElementRef<HTMLElement>>('countryPicker');
  private readonly countryButton = viewChild<ElementRef<HTMLButtonElement>>('countryButton');
  private readonly countrySearch = viewChild<ElementRef<HTMLInputElement>>('countrySearch');
  protected readonly selectedCountry = signal(PHONE_COUNTRIES.find((country) => country.id === 'eg')!);
  protected readonly countryOpen = signal(false);
  protected readonly countryQuery = new FormControl('', { nonNullable: true });

  constructor() {
    effect(() => {
      if (this.countryOpen()) this.countrySearch()?.nativeElement.focus();
    });
  }

  /**
   * Focus for desktop keyboard users. On mobile, let the parent read the
   * page before opening the keyboard; invalid submission still focuses it.
   */
  ngAfterViewInit(): void {
    if (window.matchMedia('(min-width: 981px) and (pointer: fine)').matches) {
      this.phoneBox()?.nativeElement.focus();
    }
  }

  protected readonly phone = new FormControl('', {
    nonNullable: true,
    validators: [
      Validators.required,
      (control) => {
        const country = this.selectedCountry();
        const digits = this.normalizeDigits(control.value ?? '').replace(/\D/g, '');
        if (!digits) return null;
        const mobile = this.buildMobile(digits);
        const valid = country.id === 'eg'
          ? new RegExp(this.config.phonePattern).test(digits.startsWith('0') ? digits : `0${digits}`)
          : /^\+[1-9][0-9]{5,14}$/.test(mobile);
        return valid ? null : { pattern: true };
      },
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

  protected get filteredCountryOptions(): readonly PhoneCountry[] {
    const query = this.normalizeDigits(this.countryQuery.value).trim();
    if (!query) {
      return PHONE_COUNTRIES;
    }

    const digits = query.replace(/[^0-9]/g, '');
    if (digits.length > 0) {
      return PHONE_COUNTRIES.filter((option) => option.code.slice(1).startsWith(digits));
    }

    const lower = query.toLowerCase();
    return PHONE_COUNTRIES.filter((option) =>
      option.name.toLowerCase().includes(lower) || option.id === lower,
    );
  }

  protected toggleCountry(): void {
    this.countryQuery.setValue('');
    this.countryOpen.update((open) => !open);
  }

  protected selectCountry(country: PhoneCountry): void {
    this.selectedCountry.set(country);
    this.countryOpen.set(false);
    this.noCode.set('');
    this.phone.updateValueAndValidity();
    this.phoneBox()?.nativeElement.focus();
  }

  protected onDocumentClick(event: Event): void {
    if (!this.countryPicker()?.nativeElement.contains(event.target as Node)) {
      this.countryOpen.set(false);
    }
  }

  protected onCountryFocusOut(event: FocusEvent): void {
    if (event.relatedTarget && !this.countryPicker()?.nativeElement.contains(event.relatedTarget as Node)) {
      this.countryOpen.set(false);
    }
  }

  protected onCountryKeydown(event: KeyboardEvent): void {
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      this.countryOpen.set(false);
      this.countryButton()?.nativeElement.focus();
    } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      if (!this.countryOpen()) {
        this.toggleCountry();
        return;
      }
      const options = Array.from(this.countryPicker()?.nativeElement.querySelectorAll<HTMLButtonElement>('.country-option') ?? []);
      if (!options.length) return;
      const index = options.indexOf(event.target as HTMLButtonElement);
      const next = index < 0 ? (event.key === 'ArrowDown' ? 0 : options.length - 1)
        : index + (event.key === 'ArrowDown' ? 1 : -1);
      options[(next + options.length) % options.length]?.focus();
    } else if (event.key === 'Enter' && event.target === this.countrySearch()?.nativeElement) {
      event.preventDefault();
      if (this.filteredCountryOptions.length === 1) this.selectCountry(this.filteredCountryOptions[0]);
    }
  }

  protected submit(event?: Event): void {
    event?.preventDefault();
    this.showError.set(true);
    if (this.phone.invalid) {
      this.phoneBox()?.nativeElement.focus();
      return;
    }
    if (this.busy()) {
      return;
    }
    this.busy.set(true);
    this.failed.set(false);
    this.noCode.set('');
    const mobile = this.buildMobile(this.phone.value);
    this.auth.requestOtp(mobile).subscribe({
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
    const normalized = this.normalizeDigits(value).trim();
    let digits = normalized.replace(/\D/g, '');
    const code = this.selectedCountry().code.slice(1);
    // Pasting the selected country's international number must not add its code twice.
    if (normalized.startsWith('+') && digits.startsWith(code)) digits = digits.slice(code.length);
    else if (digits.startsWith(`00${code}`)) digits = digits.slice(code.length + 2);
    if (digits !== value) {
      this.phone.setValue(digits);
    }
  }

  private buildMobile(rawPhone: string): string {
    const country = this.selectedCountry();
    const trimmed = this.normalizeDigits(rawPhone).replace(/\D/g, '');
    const local = country.prefix && trimmed.startsWith(country.prefix)
      ? trimmed.slice(country.prefix.length) : trimmed;
    return `${country.code}${local}`;
  }

  private normalizeDigits(value: string): string {
    return value.replace(/[٠-٩۰-۹]/g, (digit) => String(digit.charCodeAt(0) - (digit <= '٩' ? 0x660 : 0x6f0)));
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
