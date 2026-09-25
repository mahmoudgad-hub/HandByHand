import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, convertToParamMap } from '@angular/router';
import { of, throwError } from 'rxjs';
import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { PortalApi } from '../../core/api/portal-api';
import { ChildContextService } from '../../core/auth/child-context.service';
import { Requests } from './requests';

describe('Request composition', () => {
  const appointment = { id: '42', status: 'BOOKED', startsAt: '2099-01-01T10:00:00Z', serviceName: 'تخاطب' };
  let api: { appointments: jasmine.Spy; requests: jasmine.Spy; submitRequest: jasmine.Spy };
  beforeEach(() => {
    api = { appointments: jasmine.createSpy().and.returnValue(of([appointment])),
      requests: jasmine.createSpy().and.returnValue(of([])), submitRequest: jasmine.createSpy().and.returnValue(of({ id:'1' })) };
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting(),
      { provide: HBH_CONFIG, useValue: DEFAULT_HBH_CONFIG },
      { provide: PortalApi, useValue: api },
      { provide: ChildContextService, useValue: { requireId: () => '8' } },
      { provide: ActivatedRoute, useValue: { snapshot: { queryParamMap: convertToParamMap({ kind: 'RESCHEDULE', appointment: '42' }) } } },
    ] });
  });
  function pickDate(root: HTMLElement, year: number, month: number, day: number): void {
    const [d, m, y] = Array.from(root.querySelectorAll('.hbh-dateparts select')) as HTMLSelectElement[];
    for (const [box, value] of [[d, day], [m, month], [y, year]] as [HTMLSelectElement, number][]) {
      box.value = String(value);
      box.dispatchEvent(new Event('change'));
    }
  }
  it('preselects the originating appointment and requires a future alternative', () => {
    const fixture = TestBed.createComponent(Requests);
    fixture.detectChanges();
    const root: HTMLElement = fixture.nativeElement;
    expect((root.querySelector('select') as HTMLSelectElement).value).toBe('42');
    const send = root.querySelector('.req__actions button') as HTMLButtonElement;
    expect(send.disabled).toBeTrue();
    // The date is three named parts now: day, month, year.
    const time = root.querySelector('input[type=time]') as HTMLInputElement;
    pickDate(root, new Date().getFullYear() + 1, 1, 2);
    time.value = '11:30'; time.dispatchEvent(new Event('input'));
    fixture.detectChanges();
    expect(send.disabled).toBeFalse();
    send.click();
    expect(api.submitRequest).toHaveBeenCalledWith(jasmine.objectContaining({ childId:'8', appointmentId:'42', kind:'RESCHEDULE' }));
  });
  it('keeps submission unavailable when appointments fail to load', () => {
    api.appointments.and.returnValue(throwError(() => new Error('offline')));
    const fixture = TestBed.createComponent(Requests); fixture.detectChanges();
    expect((fixture.nativeElement.querySelector('.req__actions button') as HTMLButtonElement).disabled).toBeTrue();
    expect(api.submitRequest).not.toHaveBeenCalled();
  });
  it('rejects a past alternative even when an appointment is selected', () => {
    const fixture = TestBed.createComponent(Requests); fixture.detectChanges();
    const root: HTMLElement = fixture.nativeElement;
    // The date is three named parts now: day, month, year.
    const time = root.querySelector('input[type=time]') as HTMLInputElement;
    pickDate(root, 2000, 1, 1);
    time.value = '11:30'; time.dispatchEvent(new Event('input'));
    fixture.detectChanges();
    expect((root.querySelector('.req__actions button') as HTMLButtonElement).disabled).toBeTrue();
  });
});
