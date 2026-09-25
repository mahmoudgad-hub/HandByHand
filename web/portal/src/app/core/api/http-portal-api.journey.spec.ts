import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { HttpPortalApi } from './http-portal-api';
import { reportDisplayTitle } from './report-title';

describe('Parent journey data integrity', () => {
  let api: HttpPortalApi;
  let http: HttpTestingController;
  const base = `${DEFAULT_HBH_CONFIG.apiBaseUrl}/api/v1`;
  beforeEach(() => {
    TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting(),
      { provide: HBH_CONFIG, useValue: DEFAULT_HBH_CONFIG }, HttpPortalApi] });
    api = TestBed.inject(HttpPortalApi);
    http = TestBed.inject(HttpTestingController);
  });
  afterEach(() => http.verify());

  it('opens published notes in the notes tab', () => {
    api.notifications().subscribe(feed => {
      expect(feed.rows[0].target).toEqual(['/progress']);
      expect(feed.rows[0].targetQuery).toEqual({ tab: 'notes' });
      expect(feed.rows[0].childId).toBe('8');
    });
    http.expectOne(`${base}/notifications?limit=30`).flush({ rows: [{
      notification_id: 1, kind_code: 'NOTE_PUBLISHED', link_kind: 'NOTE', link_id: 42,
      child_id: 8, read_at: null,
    }] });
  });

  it('does not invent denied SMS or photo consents when only live access is returned', () => {
    api.consents().subscribe(items => {
      expect(items.length).toBe(2);
      expect(items.map(item => [item.key, item.childId, item.granted])).toEqual([
        ['live_view', '7', true], ['live_view', '8', false],
      ]);
    });
    http.expectOne(`${base}/children`).flush({ children: [
      { child_id: 7, link: { can_view_live: true } },
      { child_id: 8, link: { can_view_live: false } },
    ] });
  });

  it('keeps child identifiers on attention items even when siblings share a name', () => {
    api.welcome().subscribe(summary => {
      expect(summary.attention.map(item => item.childId)).toEqual(['7', '8']);
    });
    http.expectOne(`${base}/me`).flush({ user: { user_id:1, full_name_ar:'ولي أمر' } });
    http.expectOne(`${base}/children`).flush({ children: [
      { child_id:7, full_name_ar:'اسم متشابه' }, { child_id:8, full_name_ar:'اسم متشابه' },
    ] });
    http.match(() => true).forEach(request => request.flush(
      request.request.url.endsWith('/activities')
        ? { activities:[{ child_activity_id:1, done_today:false }] } : {}));
  });

  it('submits to the selected child with the selected appointment, without choosing the first sibling', () => {
    api.submitRequest({ childId: '8', kind: 'RESCHEDULE', appointmentId: '42', note: 'موعد بديل' }).subscribe();
    const request = http.expectOne(`${base}/children/8/requests`);
    expect(request.request.method).toBe('POST');
    expect(request.request.body).toEqual({ kind_code: 'RESCHEDULE', body_ar: 'موعد بديل', appointment_id: 42 });
    request.flush({ request_id: 1, status: 'NEW', kind_code: 'RESCHEDULE', body_ar: 'موعد بديل' });
  });

  it('preserves arrival separately from a running session', () => {
    api.appointments('8', 'upcoming').subscribe(items => expect(items[0].status).toBe('CHECKED_IN'));
    http.expectOne(`${base}/children/8/appointments`).flush({ appointments: [{
      appointment_id: 42, starts_at: '2099-01-01T10:00:00Z', ends_at: '2099-01-01T11:00:00Z', status: 'CHECKED_IN',
    }] });
  });

  it('does not mark today complete because the activity was done yesterday', () => {
    api.homeProgramme('8').subscribe(programme => {
      expect(programme.completed).toBe(1);
      expect(programme.activities[0].completedAt).toBeNull();
      expect(programme.activities[1].completedAt).not.toBeNull();
    });
    http.expectOne(`${base}/children/8/activities`).flush({ activities: [
      { child_activity_id: 1, done_today: false, last_done_at: '2026-09-12T10:00:00Z' },
      { child_activity_id: 2, done_today: true, last_done_at: '2026-09-13T10:00:00Z' },
    ] });
  });

  it('does not report a successful undo when the service has no undo endpoint', () => {
    let refused = false;
    api.setActivityDone('8', '1', false).subscribe({ next: () => fail('undo reported success'), error: () => refused = true });
    expect(refused).toBeTrue();
  });

  it('retains healthy titles and identifies reports whose titles were lost', () => {
    expect(reportDisplayTitle('تقرير التقدم', 1)).toBe('تقرير التقدم');
    expect(reportDisplayTitle('هل تحسن النطق؟', 2)).toBe('هل تحسن النطق؟');
    expect(reportDisplayTitle('???? ????? C5', 389)).toContain('389');
    expect(reportDisplayTitle('???? ????? C5', 389)).not.toContain('?');
  });
});
