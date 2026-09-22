import { Component } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { provideRouter, Router } from '@angular/router';
import { RouterTestingHarness } from '@angular/router/testing';
import { of } from 'rxjs';
import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { PortalApi } from '../../core/api/portal-api';
import { ChildContextService } from '../../core/auth/child-context.service';
import { routes } from '../../app.routes';
import { Shell } from '../../layout/shell/shell';

@Component({ template: 'Choose child' })
class Picker {}

describe('Portal phone more menu', () => {
  it('opens a native modal and closes on Escape without changing route', async () => {
    TestBed.configureTestingModule({ providers: [
      provideRouter([]), provideHttpClient(), provideHttpClientTesting(),
      { provide: HBH_CONFIG, useValue: DEFAULT_HBH_CONFIG },
      { provide: ChildContextService, useValue: { selected: () => null } },
      { provide: PortalApi, useValue: { profile: () => of({ fullName: 'Guardian' }), family: () => of({ children: [] }), notifications: () => of({ unread: 0 }) } },
    ] });
    const fixture = TestBed.createComponent(Shell);
    fixture.detectChanges();
    // "More" is the fifth tab now, and the phone header carries the bell.
    expect(fixture.nativeElement.querySelector('.pa__head a[href="/notifications"]')).not.toBeNull();
    fixture.nativeElement.querySelector('.pa__tabs button[aria-haspopup="dialog"]').click();
    fixture.detectChanges();
    await fixture.whenStable();
    const modal = fixture.nativeElement.querySelector('dialog') as HTMLDialogElement;
    expect(modal.open).toBeTrue();
    expect(modal.querySelector('a[href="/billing"]')).not.toBeNull();
    expect(modal.querySelector('a[href="/notifications"]')).not.toBeNull();
    expect(modal.querySelector('a[href="/profile"]')).not.toBeNull();
    expect(modal.querySelector('a[href="/requests?tab=messages"]')).not.toBeNull();
    modal.dispatchEvent(new Event('cancel', { cancelable: true }));
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('dialog')).toBeNull();
    expect(TestBed.inject(Router).url).toBe('/');
  });
});

describe('Portal merged journeys', () => {
  let selected: { id: string } | null;
  let api: { reports: jasmine.Spy; requests: jasmine.Spy; appointments: jasmine.Spy };
  let http: HttpTestingController;
  beforeEach(() => {
    selected = { id: '8' };
    api = {
      reports: jasmine.createSpy().and.returnValue(of([])),
      requests: jasmine.createSpy().and.returnValue(of([])),
      appointments: jasmine.createSpy().and.returnValue(of([])),
    };
    const children = routes.find(r => r.path === '')!.children!;
    TestBed.configureTestingModule({ providers: [
      provideHttpClient(), provideHttpClientTesting(),
      provideRouter([
        ...children.filter(r => ['progress', 'reports', 'communications', 'requests'].includes(r.path!)),
        { path: 'welcome', component: Picker },
      ]),
      { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, apiBaseUrl: '' } },
      { provide: PortalApi, useValue: api },
      { provide: ChildContextService, useValue: {
        selected: () => selected, rememberedId: () => null, requireId: () => selected!.id,
      } },
    ] });
    http = TestBed.inject(HttpTestingController);
  });
  afterEach(() => http.verify());

  it('does not mark a late message response as read after its tab is hidden', async () => {
    const harness = await RouterTestingHarness.create();
    await harness.navigateByUrl('/requests?tab=messages');
    http.expectOne(r => r.url === '/api/v1/chat-contacts').flush({ rows: [
      // A real conversation: in portal mode a contact with no last_at is not
      // an open conversation yet, so nothing would be selected or fetched.
      { guardian_id: 9, kind: 'staff', role: 'reception', name: 'Family', can_send: true, can_manage: false,
        last_message: 'Reply', last_at: '2026-09-14T12:00:00Z', unread: 1 },
    ], more: false });
    const messages = http.expectOne('/api/v1/family-messages/9');
    await harness.navigateByUrl('/requests?tab=requests');
    messages.flush({ rows: [{ message_id: 4, body: 'Reply', mine: false, created_at: '2026-09-14T12:00:00Z' }], more: false });
    http.expectNone(r => r.method === 'POST');
  });

  it('redirects the legacy notes link and reads notes, then reports when switching tabs', async () => {
    const harness = await RouterTestingHarness.create();
    await harness.navigateByUrl('/reports?tab=notes');
    expect(TestBed.inject(Router).url).toBe('/progress?tab=notes');
    expect(api.reports).toHaveBeenCalledWith('8', 'notes');
    await harness.navigateByUrl('/progress?tab=reports');
    expect(api.reports).toHaveBeenCalledWith('8', 'reports');
    await harness.navigateByUrl('/progress?tab=notes');
    expect(api.reports.calls.mostRecent().args).toEqual(['8', 'notes']);
  });

  it('redirects the old reports route to the reports tab', async () => {
    const harness = await RouterTestingHarness.create();
    await harness.navigateByUrl('/reports');
    expect(TestBed.inject(Router).url).toBe('/progress?tab=reports');
    expect(api.reports).toHaveBeenCalledWith('8', 'reports');
  });

  it('opens messages without a selected child and guards only the child request tab', async () => {
    selected = null;
    const harness = await RouterTestingHarness.create();
    await harness.navigateByUrl('/communications');
    expect(TestBed.inject(Router).url).toBe('/requests?tab=messages');
    http.expectOne(r => r.url === '/api/v1/chat-contacts').flush({ rows: [], more: false });
    expect(api.requests).not.toHaveBeenCalled();
    expect(api.appointments).not.toHaveBeenCalled();
    await harness.navigateByUrl('/requests?tab=requests');
    expect(TestBed.inject(Router).url).toBe('/welcome');
    expect(api.requests).not.toHaveBeenCalled();
  });

  it('retains the request form while switching to messages and back', async () => {
    const harness = await RouterTestingHarness.create();
    await harness.navigateByUrl('/requests?kind=CALLBACK');
    const original = harness.routeNativeElement!.querySelector('hbh-requests');
    const note = original!.querySelector('textarea')!;
    note.value = 'Please call tomorrow';
    note.dispatchEvent(new Event('input'));
    await harness.navigateByUrl('/requests?tab=messages');
    http.expectOne(r => r.url === '/api/v1/chat-contacts').flush({ rows: [], more: false });
    await harness.navigateByUrl('/requests?tab=requests');
    expect(harness.routeNativeElement!.querySelector('hbh-requests')).toBe(original);
    expect(note.value).toBe('Please call tomorrow');
    expect(api.requests).toHaveBeenCalledTimes(1);
  });
});
