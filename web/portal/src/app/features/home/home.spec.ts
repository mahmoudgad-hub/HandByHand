import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { Router, provideRouter } from '@angular/router';
import { of, throwError } from 'rxjs';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { PortalApi } from '../../core/api/portal-api';
import { ChildContextService } from '../../core/auth/child-context.service';
import { Home } from './home';

/**
 * The front page carries what needs the family's attention, for every
 * child at once (UX-5): the list the welcome screen used to hold. Each
 * row leads where the thing is dealt with, and a row about another child
 * chooses that child first.
 */
describe('Home attention list', () => {
  let selected: { id: string; fullName: string };
  let selectSpy: jasmine.Spy;

  const HOME = {
    nextAppointment: null, live: null, lastSession: null, latestUpdate: null, todayActivity: null,
    upcoming: [], balanceUnavailable: false, dueAmount: 0, currency: 'EGP',
    openActivityCount: 0, unreadReportCount: 0,
  };
  const WELCOME = {
    guardian: { fullName: 'منى' },
    children: [{ id: '8', fullName: 'عمر' }, { id: '9', fullName: 'ليلى' }],
    attention: [
      { kind: 'INVOICE', childId: null, titleKey: 'attention.invoice', amount: 600, currency: 'EGP', count: null, childName: null },
      { kind: 'ACTIVITY', childId: '9', titleKey: 'attention.activities', amount: null, currency: null, count: 2, childName: 'ليلى' },
    ],
  };

  function mount(welcome: unknown = WELCOME): ComponentFixture<Home> {
    selected = { id: '8', fullName: 'عمر' };
    selectSpy = jasmine.createSpy('select');
    TestBed.configureTestingModule({
      imports: [Home],
      providers: [
        provideRouter([{ path: '**', children: [] }]), provideHttpClient(), provideHttpClientTesting(),
        { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, apiBaseUrl: '' } },
        {
          provide: PortalApi, useValue: {
            home: () => of(HOME),
            welcome: () => (welcome instanceof Error ? throwError(() => welcome) : of(welcome)),
          },
        },
        {
          provide: ChildContextService, useValue: {
            selected: () => selected, requireId: () => selected.id,
            select: (child: { id: string }) => selectSpy(child),
          },
        },
      ],
    });
    spyOn(TestBed.inject(Router), 'navigate').and.resolveTo(true);
    const fixture = TestBed.createComponent(Home);
    fixture.detectChanges();
    return fixture;
  }

  it('lists every child\'s pending items, with the money formatted and the count pluralised', () => {
    const fixture = mount();
    const rows = Array.from((fixture.nativeElement as HTMLElement).querySelectorAll('.home-attention .row'));
    expect(rows.length).toBe(2);
    expect(rows[0].textContent).toContain('attention.invoice');
    expect(rows[1].textContent).toContain('ليلى');
    expect(rows[1].textContent).toContain('attention.openActivities');
  });

  it('opens a family-wide item without touching the chosen child, and a child\'s item after choosing that child', () => {
    const fixture = mount();
    const rows = Array.from((fixture.nativeElement as HTMLElement).querySelectorAll<HTMLButtonElement>('.home-attention .row'));
    rows[0].click();
    expect(selectSpy).not.toHaveBeenCalled();
    expect(TestBed.inject(Router).navigate).toHaveBeenCalledWith(['/billing'], { queryParams: {} });
    rows[1].click();
    expect(selectSpy).toHaveBeenCalledWith(jasmine.objectContaining({ id: '9' }));
    expect(TestBed.inject(Router).navigate).toHaveBeenCalledWith(['/activities'], { queryParams: {} });
  });

  it('draws no list when nothing is waiting, or when the read failed', () => {
    let fixture = mount({ ...WELCOME, attention: [] });
    expect((fixture.nativeElement as HTMLElement).querySelector('.home-attention')).toBeNull();
    TestBed.resetTestingModule();
    fixture = mount(new Error('down'));
    expect((fixture.nativeElement as HTMLElement).querySelector('.home-attention')).toBeNull();
  });
});
