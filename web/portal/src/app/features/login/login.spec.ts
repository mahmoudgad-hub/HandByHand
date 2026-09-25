import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed, ComponentFixture } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { of } from 'rxjs';
import { HBH_CONFIG, DEFAULT_HBH_CONFIG } from '@hbh/shared/config/app-config';
import { AuthService } from '../../core/auth/auth.service';
import { Login } from './login';
import { ALL_PHONE_COUNTRIES, ENABLED_PHONE_COUNTRIES, PHONE_COUNTRIES } from './phone-countries';

describe('Login country and mobile input', () => {
  let fixture: ComponentFixture<Login>;
  let requestOtp: jasmine.Spy;
  const element = <T extends HTMLElement>(selector: string): T => fixture.nativeElement.querySelector(selector);

  beforeEach(() => {
    requestOtp = jasmine.createSpy('requestOtp').and.returnValue(of({ outcome: 'NOT_REGISTERED' }));
    TestBed.configureTestingModule({ providers: [
      provideHttpClient(), provideHttpClientTesting(), provideRouter([]),
      { provide: HBH_CONFIG, useValue: DEFAULT_HBH_CONFIG },
      { provide: AuthService, useValue: { requestOtp } },
    ] });
    fixture = TestBed.createComponent(Login);
    fixture.detectChanges();
  });

  function input(selector: string, value: string): void {
    const field = element<HTMLInputElement>(selector);
    field.value = value;
    field.dispatchEvent(new Event('input', { bubbles: true }));
    fixture.detectChanges();
  }

  function choose(code: string): void {
    element<HTMLButtonElement>('#phoneCountry').click();
    fixture.detectChanges();
    input('.country-search', code);
    element<HTMLButtonElement>('.country-option').click();
    fixture.detectChanges();
  }

  function submit(): void {
    element<HTMLFormElement>('form').dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    fixture.detectChanges();
  }

  it('defaults to the Egyptian flag and sends a local number with one country code', () => {
    expect(element<HTMLImageElement>('#phoneCountry img').getAttribute('src')).toBe('assets/flags/eg.svg');
    expect(element('#phoneCountry').textContent?.trim()).toBe('+20');
    input('#phone', '01012345678');
    submit();
    expect(requestOtp).toHaveBeenCalledOnceWith('+201012345678', '01012345678');
  });

  it('accepts a pasted international number and Arabic digits without duplication or truncation', () => {
    input('#phone', '+٢٠ ١٠ ١٢٣٤ ٥٦٧٨');
    expect(element<HTMLInputElement>('#phone').value).toBe('1012345678');
    submit();
    // The national form is rebuilt for the display line, so a pasted
    // international number is still shown back the way Egypt writes it.
    expect(requestOtp).toHaveBeenCalledOnceWith('+201012345678', '01012345678');
  });

  it('filters calling codes by prefix in either digit script and clears the search on reopening', () => {
    element<HTMLButtonElement>('#phoneCountry').click();
    fixture.detectChanges();
    input('.country-search', '٩');
    const codes = Array.from(fixture.nativeElement.querySelectorAll('.country-option bdi') as NodeListOf<HTMLElement>);
    expect(codes.length).toBe(7);
    expect(codes.every((code) => code.textContent!.startsWith('+9'))).toBeTrue();
    element<HTMLInputElement>('.country-search').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    fixture.detectChanges();
    expect(element('#countryMenu')).toBeNull();
    element<HTMLButtonElement>('#phoneCountry').click();
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelectorAll('.country-option').length).toBe(8);
  });

  it('accepts a Saudi mobile with its national prefix instead of requiring an Egyptian number', () => {
    choose('+966');
    input('#phone', '0501234567');
    submit();
    expect(requestOtp).toHaveBeenCalledOnceWith('+966501234567', '0501234567');
  });



  it('does not send an empty or malformed Egyptian number', () => {
    submit();
    input('#phone', '123');
    submit();
    expect(requestOtp).not.toHaveBeenCalled();
    expect(element('#phone').getAttribute('aria-invalid')).toBe('true');
  });

  it('supports opening, navigating, selecting and closing the country menu by keyboard', () => {
    element('#phoneCountry').dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
    fixture.detectChanges();
    input('.country-search', '966');
    element('.country-search').dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true }));
    expect(document.activeElement).toBe(element('.country-option'));
    element('.country-option').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    fixture.detectChanges();
    expect(document.activeElement).toBe(element('#phoneCountry'));
    expect(element('#countryMenu')).toBeNull();
  });

  it('rejects an overlong international mobile instead of silently truncating it', () => {
    choose('+965');
    input('#phone', '512345671234567890');
    submit();
    expect(element<HTMLInputElement>('#phone').value).toBe('512345671234567890');
    expect(requestOtp).not.toHaveBeenCalled();
  });

  it('sends a mobile from a country with no national prefix as typed', () => {
    choose('+965');
    input('#phone', '51234567');
    submit();
    expect(requestOtp).toHaveBeenCalledOnceWith('+96551234567', '51234567');
  });

  it('offers exactly the countries the database stores mobiles for', () => {
    // hbh.country_dial_codes, active rows, 2026-09-16. Any other country was
    // a dead end: canonical_mobile refuses its dial code (HB173), so no
    // application or staff-registered number from it can exist.
    element<HTMLButtonElement>('#phoneCountry').click();
    fixture.detectChanges();
    const codes = Array.from(fixture.nativeElement.querySelectorAll('.country-option bdi') as NodeListOf<HTMLElement>)
      .map((code) => code.textContent!.trim());
    expect(codes.sort()).toEqual(['+20', '+962', '+965', '+966', '+968', '+971', '+973', '+974']);
    input('.country-search', '39');
    expect(fixture.nativeElement.querySelectorAll('.country-option').length).toBe(0);
  });

  it('keeps the hidden countries, so enabling one is a line and not a rebuild of the list', () => {
    // The owner's call: hide, do not delete. Italy stays in the data.
    expect(ALL_PHONE_COUNTRIES.length).toBe(243);
    expect(ALL_PHONE_COUNTRIES.some((country) => country.id === 'it')).toBeTrue();
    expect(PHONE_COUNTRIES.some((country) => country.id === 'it')).toBeFalse();
    // An enabled id with no entry would vanish silently instead of showing.
    for (const id of ENABLED_PHONE_COUNTRIES) {
      expect(ALL_PHONE_COUNTRIES.some((country) => country.id === id)).withContext(id).toBeTrue();
    }
    expect(PHONE_COUNTRIES[0].id).toBe('eg');
  });
});
