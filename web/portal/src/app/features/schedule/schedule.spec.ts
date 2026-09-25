import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { of } from 'rxjs';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { PortalApi } from '../../core/api/portal-api';
import { ChildContextService } from '../../core/auth/child-context.service';
import { Schedule } from './schedule';

/**
 * "Ask about this appointment" sits on the appointment's own row (UX-5),
 * bound to that appointment - only while it is ahead and still live.
 */
describe('Schedule row actions', () => {
  const base = { serviceName: 'تخاطب', therapistName: 'سارة', therapistId: '236', roomName: 'غرفة ١', deliveryMode: 'IN_PERSON' };

  function mount(appointments: readonly Record<string, unknown>[]): ComponentFixture<Schedule> {
    TestBed.configureTestingModule({
      imports: [Schedule],
      providers: [
        provideRouter([{ path: '**', children: [] }]), provideHttpClient(), provideHttpClientTesting(),
        { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, apiBaseUrl: '' } },
        { provide: PortalApi, useValue: { appointments: () => of(appointments) } },
        { provide: ChildContextService, useValue: { selected: () => ({ id: '8' }), requireId: () => '8' } },
      ],
    });
    const fixture = TestBed.createComponent(Schedule);
    fixture.detectChanges();
    return fixture;
  }

  it('offers a change request on a booked or confirmed upcoming row, bound to that appointment, and on nothing else', () => {
    const fixture = mount([
      { ...base, id: '70', startsAt: '2099-01-01T10:00:00Z', status: 'BOOKED' },
      { ...base, id: '71', startsAt: '2099-01-02T10:00:00Z', status: 'CONFIRMED' },
      { ...base, id: '72', startsAt: '2099-01-03T10:00:00Z', status: 'CANCELLED' },
    ]);
    const links = Array.from((fixture.nativeElement as HTMLElement).querySelectorAll<HTMLAnchorElement>('.schedule-row-actions a'))
      .map((a) => a.getAttribute('href'));
    expect(links).toEqual([
      '/requests?kind=RESCHEDULE&appointment=70',
      '/requests?kind=RESCHEDULE&appointment=71',
    ]);
  });
});
