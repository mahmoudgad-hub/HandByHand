import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { FormatService } from '@hbh/shared/format/format.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { Inbox } from './inbox';

/**
 * "Mark all read" (#24), through the real InboxApi.
 *
 * The request is what this is about. The endpoint takes no body and names
 * nobody - "all" is decided inside the database from the caller's identity -
 * and the count the screen reports is the service's, not a tally of the rows
 * on this page. The feed shows the newest fifty; the write clears every
 * unread row the person has.
 */
describe('Marking the whole inbox read', () => {
  let http: HttpTestingController;
  let screen: Inbox;
  let shown: string[];

  const row = (id: number) => ({
    notification_id: id, kind_code: 'REPORT_PUBLISHED', title_ar: 'تقرير',
    body_ar: null, created_at: '2026-09-14T10:00:00Z', read_at: null,
    link_kind: null, link_id: null, child_id: null,
  });

  beforeEach(() => {
    shown = [];
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(), provideHttpClientTesting(),
        { provide: HBH_CONFIG, useValue: { apiBaseUrl: '' } },
        { provide: Router, useValue: { navigate: () => Promise.resolve(true) } },
        { provide: ToastService, useValue: { show: (t: string) => shown.push(t), warning: (t: string) => shown.push(t) } },
        { provide: I18nService, useValue: { plural: (key: string, n: number) => `${key}:${n}`, translate: (key: string) => key } },
        { provide: FormatService, useValue: {} },
      ],
    }).overrideComponent(Inbox, { set: { template: '', imports: [] } });

    http = TestBed.inject(HttpTestingController);
    screen = TestBed.createComponent(Inbox).componentInstance;
    http.expectOne((r) => r.url === '/api/v1/notifications')
      .flush({ rows: [row(1), row(2)], unread: 2, total: 2 });
  });

  afterEach(() => http.verify());

  it('asks for nobody in particular, and reports the count the service gave', () => {
    (screen as unknown as { markAllRead(): void }).markAllRead();

    const sent = http.expectOne('/api/v1/notifications/read-all');
    expect(sent.request.method).toBe('POST');
    // No body, and no way to name a user: an endpoint that took one would be
    // a way to clear somebody else's bell.
    expect(sent.request.body).toEqual({});

    // Nothing has moved yet. The rows change when the service says so.
    expect(screen['data']()?.unread).toBe(2);

    // Nine, not the two rows on this page - the feed is the newest fifty and
    // the write cleared everything.
    sent.flush({ marked: 9 });
    expect(screen['data']()?.unread).toBe(0);
    expect(screen['data']()?.rows.every((r) => r.read)).toBeTrue();
    expect(shown).toEqual(['inbox.markedAll:9']);
  });

  it('leaves the feed unread and says so when the write fails', () => {
    (screen as unknown as { markAllRead(): void }).markAllRead();
    http.expectOne('/api/v1/notifications/read-all')
      .flush(null, { status: 503, statusText: 'Unavailable' });

    expect(screen['data']()?.unread).toBe(2);
    expect(screen['data']()?.rows.some((r) => r.read)).toBeFalse();
    expect(shown).toEqual(['inbox.markAllFailed']);
  });

  it('sends nothing when there is nothing unread', () => {
    const feed = screen['data']();
    screen['data'].set({ ...feed!, unread: 0, rows: feed!.rows.map((r) => ({ ...r, read: true })) });
    (screen as unknown as { markAllRead(): void }).markAllRead();
    // http.verify() in afterEach is the assertion: a request here would be a
    // write that changes nothing, reported to the person as success.
  });
});
