import { of } from 'rxjs';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { HBH_CONFIG, DEFAULT_HBH_CONFIG } from '@hbh/shared/config/app-config';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { FAVORITES_STORAGE } from '../../core/favorites/favorites.service';
import { MyProfile } from './my-profile';

describe('MyProfile', () => {
  let http: HttpTestingController;
  function mount(userType = 'STAFF') {
    TestBed.configureTestingModule({ providers: [
      provideRouter([]), provideHttpClient(), provideHttpClientTesting(),
      { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, apiBaseUrl: '' } },
      { provide: FAVORITES_STORAGE, useValue: null },
      { provide: OpsAuthService, useValue: {
        me: () => ({ userId: 8, username: 'staff8', fullName: 'عضو استقبال', userType, centerName: 'المركز', timeZone: 'Africa/Cairo' }),
        loadIdentity: jasmine.createSpy('loadIdentity').and.returnValue(of({})),
        can: (permission: string) => permission === 'PORTAL.VIEW',
        roleLabelKey: () => 'role.RECEPTION',
      } },
    ] });
    http = TestBed.inject(HttpTestingController);
    const fixture = TestBed.createComponent(MyProfile);
    fixture.detectChanges();
    http.expectOne('/api/v1/users/8/photo').flush(null, { status: 404, statusText: 'Not Found' });
    return fixture;
  }
  afterEach(() => http.verify());

  it('shows the signed-in identity without needing user administration or listing other users', () => {
    const fixture = mount();
    expect(TestBed.inject(OpsAuthService).loadIdentity).toHaveBeenCalledTimes(1);
    expect(fixture.nativeElement.textContent).toContain('عضو استقبال');
    expect(fixture.nativeElement.textContent).toContain('staff8');
    const editor = fixture.nativeElement.querySelector('hbh-avatar-editor') as HTMLElement;
    const fileInput = editor.querySelector('input[type=file]') as HTMLInputElement;
    const pick = spyOn(fileInput, 'click');
    (editor.querySelector('button') as HTMLButtonElement).click();
    expect(pick).toHaveBeenCalledTimes(1);
    expect(fixture.nativeElement.querySelector('a[href="/users"]')).toBeNull();
    expect(fixture.nativeElement.querySelector('.profile-access')).toBeNull();
    http.expectNone(() => true);
  });

  it('validates confirmation, changes only the current password and clears secrets after success', () => {
    const fixture = mount();
    const el = fixture.nativeElement as HTMLElement;
    const fill = (id: string, value: string) => {
      const input = el.querySelector<HTMLInputElement>(id)!;
      input.value = value;
      input.dispatchEvent(new Event('input'));
    };
    const submit = () => el.querySelector('form')!.dispatchEvent(new Event('submit', { cancelable: true }));
    fill('#profile-current', 'old-password');
    fill('#profile-new', 'new-password-123');
    fill('#profile-confirm', 'mismatch');
    submit();
    http.expectNone(() => true);
    fill('#profile-confirm', 'new-password-123');
    submit();
    submit();
    const request = http.expectOne('/api/v1/auth/password');
    expect(request.request.body).toEqual({ current_password: 'old-password', new_password: 'new-password-123' });
    request.flush(null, { status: 204, statusText: 'No Content' });
    fixture.detectChanges();
    expect(el.querySelector('[role=status]')).not.toBeNull();
    el.querySelectorAll<HTMLInputElement>('input').forEach(input => expect(input.value).toBe(''));
  });

  it('does not offer password changes to OTP-only guardians', () => {
    const fixture = mount('GUARDIAN');
    expect(fixture.nativeElement.querySelector('form')).toBeNull();
    http.expectNone(() => true);
  });
});
