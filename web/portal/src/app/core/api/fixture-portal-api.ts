import { Injectable, inject } from '@angular/core';
import { Observable, delay, of, throwError } from 'rxjs';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { PortalApi } from './portal-api';
import {
  AppointmentSummary,
  BillingOverview,
  Child,
  Consent,
  ConsentKey,
  Guardian,
  GuardianContact,
  HomeProgramme,
  HomeSummary,
  LiveSession,
  NewRequest,
  ParentRequest,
  ProgressOverview,
  ReportSummary,
  ReportDetail,
  StreamTicket,
  TherapistProfile,
  Uuid,
  WelcomeSummary,
  NotificationFeed,
  PortalNotification,
} from '../models/portal.models';

/**
 * Stand-in for the Go service, which is not built yet. It exists so the
 * screens can be reviewed with the centre before the API lands, and so that
 * every screen is written against the real contract from the first line.
 *
 * What it deliberately does NOT do:
 *   - It enforces nothing. Not the guardian-to-child link, not the live
 *     consent, not the session window. Those are server rules, and writing a
 *     copy of them here would be a second implementation to drift.
 *   - It stores nothing outside memory. Reloading the page resets it, which
 *     is the honest behaviour for something that is not a database.
 *
 * The Arabic strings below stand for database content, not interface text.
 * Interface text lives in assets/i18n and nowhere else.
 */
@Injectable()
export class FixturePortalApi extends PortalApi {
  private readonly config = inject(HBH_CONFIG);

  /** Round trip a real network would cost, so loading states are visible. */
  private readonly latencyMs = 260;

  private readonly guardian: Guardian = {
    id: 'g-0001',
    fullName: 'علي محمود',
    phone: '+20 100 123 4567',
  };

  private readonly youssefId = 'c-0021';
  private readonly malakId = 'c-0034';
  private readonly liveSessionId = 's-9001';

  /** Mutable so a toggle on screen behaves like a toggle. */
  private activityDone = new Map<Uuid, boolean>([
    ['a-1', true],
    ['a-2', false],
    ['a-3', false],
  ]);

  private consentState = new Map<ConsentKey, boolean>([
    ['live_view', true],
    ['sms_notifications', true],
    ['activity_photos', false],
  ]);

  private submitted: ParentRequest[] = [];

  // -------------------------------------------------------------------------
  // Guardian, children, welcome
  // -------------------------------------------------------------------------

  override welcome(): Observable<WelcomeSummary> {
    return this.respond<WelcomeSummary>({
      guardian: this.guardian,
      children: [this.youssef(), this.malak()],
      // Keys and raw numbers, exactly as the real implementation produces
      // them. A fixture that carried finished Arabic would let a screen get
      // away with printing it, and the day the real data arrived it would
      // print a translation key instead - which is what happened.
      attention: [
        {
          kind: 'REPORT',
          titleKey: 'attention.report',
          amount: null, currency: null, count: 1,
          childName: 'يوسف',
        },
        {
          kind: 'INVOICE',
          titleKey: 'attention.invoice',
          amount: 950, currency: 'EGP', count: null,
          childName: null,
        },
        {
          kind: 'ACTIVITY',
          titleKey: 'attention.activities',
          amount: null, currency: null, count: 2,
          childName: 'يوسف',
        },
      ],
    });
  }

  override home(childId: Uuid): Observable<HomeSummary> {
    const child = childId === this.malakId ? this.malak() : this.youssef();
    const upcoming = this.upcomingFor(childId);
    return this.respond<HomeSummary>({
      child,
      nextAppointment: child.nextAppointment,
      live: child.liveSessionId ? this.session() : null,
      upcoming: upcoming.slice(0, 2),
      openActivityCount: 3,
      lastSession: {
        at: this.at(-4, 11, 0),
        therapistName: 'أ. سارة عبد الرحمن',
        serviceName: 'جلسة تخاطب',
      },
      latestUpdate: {
        id: 'n-1',
        kind: 'SESSION_NOTE',
        title: 'ملاحظة جلسة — تحسّن في الانتباه المشترك',
        authorName: 'سارة عبد الرحمن',
        publishedAt: this.at(-3, 18, 0),
        unread: true,
      },
      todayActivity: {
        id: 'a-2',
        title: 'كرات العجين',
        instructions: 'كرات صغيرة بالأصابع الثلاثة، لتقوية قبضة القلم.',
        howTo: 'عجينة لينة، والكرة بحجم حبة الحمص، بالإبهام والسبابة والوسطى فقط.',
        timesPerWeek: 3,
        minutesEach: 15,
        dueOn: this.at(3, 20, 0),
        completedAt: null,
      },
      unreadReportCount: 1,
      balanceUnavailable: false,
      scheduleUnavailable: false,
      activitiesUnavailable: false,
      reportsUnavailable: false,
      dueAmount: 1750,
      currency: this.config.currency,
    });
  }

  override profile(): Observable<Guardian> {
    return this.respond(this.guardian);
  }

  /**
   * The therapist behind a booking, as a family sees them.
   *
   * No mobile and no photograph: the service withholds the first from a
   * guardian, and the schema stores no second. A fixture that invented
   * either would teach the screen to draw something the real answer never
   * carries.
   */
  override therapist(therapistId: Uuid): Observable<TherapistProfile> {
    return this.respond<TherapistProfile>({
      id: therapistId,
      fullName: "أ. سارة عبد الرحمن",
      title: "أخصائية تخاطب",
      status: "ACTIVE",
      services: ["جلسة تخاطب", "تنمية مهارات"],
      // Published, because an unpublished profile shows a family nothing and
      // a fixture that showed nothing would exercise no layout at all.
      published: true,
      bio: "أعمل مع الأطفال من عمر سنتين إلى تسع سنوات. أبدأ دائمًا بجلسة ألعب فيها مع الطفل قبل أن أقيس أي شيء.",
      // Derived in the real implementation from the year practice began.
      yearsOfPractice: 11,
      ageFromMonths: 24,
      ageToMonths: 108,
      languages: [
        { code: "ar", runsSessions: true, isNative: true, levelCode: "NATIVE" },
        { code: "en", runsSessions: true, isNative: false, levelCode: "FLUENT" },
      ],
      qualifications: [
        { id: "q1", year: 2021, title: "ماجستير اضطرابات التواصل", issuer: "جامعة عين شمس" },
        { id: "q2", year: 2014, title: "بكالوريوس علاج عيوب النطق", issuer: "جامعة الزقازيق" },
      ],
      certificates: [
        // One with a published scan and one without: the pair is the point,
        // because a screen that only ever sees one of them cannot show that
        // "no image" and "image not for you" read the same to a family.
        { id: "c1", title: "PROMPT — المستوى التمهيدي", issuer: "PROMPT Institute",
          year: 2022, hasImage: true, attachmentId: "att-1" },
        { id: "c2", title: "تحليل السلوك التطبيقي ABA", issuer: "المعهد القومي",
          year: 2019, hasImage: true, attachmentId: null },
      ],
    });
  }

  // -------------------------------------------------------------------------
  // Schedule
  // -------------------------------------------------------------------------

  override appointments(
    childId: Uuid,
    scope: 'upcoming' | 'past',
  ): Observable<readonly AppointmentSummary[]> {
    return this.respond(
      scope === 'upcoming' ? this.upcomingFor(childId) : this.pastFor(childId),
    );
  }

  // -------------------------------------------------------------------------
  // Progress
  // -------------------------------------------------------------------------

  override progress(): Observable<ProgressOverview> {
    return this.respond<ProgressOverview>({
      planTitle: 'خطة العلاج — الربع الثالث ٢٠٢٦',
      goals: [
        {
          id: 'goal-1',
          title: 'نطق صوت /س/ في وسط الكلمة',
          currentPercent: 78,
          baselinePercent: 30,
          targetPercent: 80,
          measurementCount: 12,
          lastMeasuredAt: this.at(-2, 12, 0),
          series: [
            { takenAt: this.at(-90, 12, 0), value: 32 },
            { takenAt: this.at(-75, 12, 0), value: 41 },
            { takenAt: this.at(-60, 12, 0), value: 55 },
            { takenAt: this.at(-45, 12, 0), value: 60 },
            { takenAt: this.at(-20, 12, 0), value: 71 },
            { takenAt: this.at(-2, 12, 0), value: 78 },
          ],
        },
        {
          id: 'goal-2',
          title: 'تكوين جملة من أربع كلمات',
          currentPercent: 54,
          baselinePercent: 25,
          targetPercent: 70,
          measurementCount: 9,
          lastMeasuredAt: this.at(-5, 12, 0),
          series: [],
        },
        {
          id: 'goal-3',
          title: 'الإمساك بالقلم بقبضة ثلاثية',
          currentPercent: 35,
          baselinePercent: 15,
          targetPercent: 60,
          measurementCount: 6,
          lastMeasuredAt: this.at(-8, 12, 0),
          series: [],
        },
      ],
      latestReport: this.progressReport(),
    });
  }

  // -------------------------------------------------------------------------
  // Home programme
  // -------------------------------------------------------------------------

  override homeProgramme(): Observable<HomeProgramme> {
    const activities = [
      {
        id: 'a-1',
        title: 'تكرار كلمات صوت /س/ — عشر دقائق',
        instructions: 'سمسم، مسمار، بسبوسة. مرّة صباحًا ومرّة قبل النوم.',
        howTo: 'اجلس أمام الطفل في مستوى نظره، وانطق الكلمة ببطء مرّتين قبل أن يكرّرها.',
        timesPerWeek: 5,
        minutesEach: 10,
        dueOn: this.at(0, 20, 0),
        completedAt: this.activityDone.get('a-1') ? this.at(0, 9, 30) : null,
      },
      {
        id: 'a-2',
        title: 'لعبة الصلصال — خمس عشرة دقيقة',
        instructions: 'كرات صغيرة بالأصابع الثلاثة، لتقوية قبضة القلم.',
        howTo: 'عجينة لينة، والكرة بحجم حبة الحمص، بالإبهام والسبابة والوسطى فقط.',
        timesPerWeek: 3,
        minutesEach: 15,
        dueOn: this.at(0, 20, 0),
        completedAt: this.activityDone.get('a-2') ? this.at(0, 10, 0) : null,
      },
      {
        id: 'a-3',
        title: 'قراءة قصة مصوّرة والسؤال عن «مين؟ وفين؟»',
        instructions: 'قصة واحدة، وثلاثة أسئلة بعد كل صفحتين.',
        howTo: '',
        timesPerWeek: 0,
        minutesEach: 0,
        dueOn: this.at(0, 20, 0),
        completedAt: this.activityDone.get('a-3') ? this.at(0, 10, 30) : null,
      },
    ];
    return this.respond<HomeProgramme>({
      weekStart: this.at(-2, 0, 0),
      weekEnd: this.at(4, 23, 59),
      completed: 7,
      total: 10,
      activities,
    });
  }

  override setActivityDone(
    childId: Uuid,
    activityId: Uuid,
    done: boolean,
  ): Observable<void> {
    this.activityDone.set(activityId, done);
    return this.respond(undefined as void);
  }

  // -------------------------------------------------------------------------
  // Reports
  // -------------------------------------------------------------------------

  override report(reportId: Uuid): Observable<ReportDetail> {
    return this.respond<ReportDetail>({
      id: String(reportId),
      number: 'RPT-2026-00071',
      title: 'تقرير تقدّم — أغسطس ٢٠٢٦',
      summary: 'تحسّن واضح في الانتباه المشترك ومدّة الجلوس. النطق يحتاج تكرارًا '
        + 'منزليًا يوميًا، ويُنصح بمواصلة تمرين الأصوات القصيرة قبل الطويلة.',
      periodStart: '2026-08-01',
      periodEnd: '2026-08-31',
      publishedAt: this.at(-6, 12, 0),
      goals: [
        {
          title: 'نطق صوت /س/ في وسط الكلمة',
          latestPercent: 78, baselinePercent: 30, targetPercent: 80,
        },
        // One goal with no measurement, on purpose: it is the case the
        // screen used to get wrong, and a fixture where every goal has a
        // number never exercises it.
        {
          title: 'تكوين جملة من أربع كلمات',
          latestPercent: null, baselinePercent: 25, targetPercent: 70,
        },
      ],
    });
  }

  override reports(
    childId: Uuid,
    scope: 'reports' | 'notes',
  ): Observable<readonly ReportSummary[]> {
    if (scope === 'notes') {
      return this.respond<readonly ReportSummary[]>([
        {
          id: 'n-1',
          kind: 'SESSION_NOTE',
          title: 'ملاحظة جلسة — تحسّن في الانتباه المشترك',
          authorName: 'سارة عبد الرحمن',
          publishedAt: this.at(-3, 18, 0),
          unread: false,
        },
        {
          id: 'n-2',
          kind: 'SESSION_NOTE',
          title: 'ملاحظة جلسة — تعب واضح في آخر عشر دقائق',
          authorName: 'منى خالد',
          publishedAt: this.at(-9, 12, 0),
          unread: false,
        },
      ]);
    }
    return this.respond<readonly ReportSummary[]>([
      this.progressReport(),
      {
        id: 'r-2',
        kind: 'PROGRESS',
        title: 'تقرير التقدّم — الشهر الماضي',
        authorName: 'سارة عبد الرحمن',
        publishedAt: this.at(-32, 12, 0),
        unread: false,
      },
      {
        id: 'r-3',
        kind: 'ASSESSMENT',
        title: 'تقرير التقييم المبدئي',
        authorName: 'هدى سمير',
        publishedAt: this.at(-80, 12, 0),
        unread: false,
      },
    ]);
  }

  // -------------------------------------------------------------------------
  // Billing
  // -------------------------------------------------------------------------

  override billing(): Observable<BillingOverview> {
    const currency = this.config.currency;
    return this.respond<BillingOverview>({
      balanceUnavailable: false,
      packagesUnavailable: false,
      invoicesUnavailable: false,
      dueAmount: 1750,
      currency,
      packages: [
        {
          id: 'p-1',
          title: 'باقة تخاطب — اثنتا عشرة جلسة',
          used: 5,
          total: 12,
          expiresAt: this.at(89, 23, 59),
        },
        {
          id: 'p-2',
          title: 'باقة علاج وظيفي — ثماني جلسات',
          used: 2,
          total: 8,
          expiresAt: this.at(43, 23, 59),
        },
      ],
      invoices: [
        {
          id: 'i-1',
          number: 'INV-2026-00418',
          issuedAt: this.at(-1, 9, 0),
          amount: 1750,
          // Partly paid, so the fixture actually exercises the breakdown.
          // It was DUE with nothing paid, which is the one case where the
          // three figures cannot disagree and so proves nothing.
          paidAmount: 500,
          currency,
          description: 'باقة تخاطب',
          status: 'PARTIAL',
        },
        {
          id: 'i-2',
          number: 'INV-2026-00377',
          issuedAt: this.at(-30, 9, 0),
          amount: 2400,
          paidAmount: 2400,
          currency,
          description: 'باقة علاج وظيفي',
          status: 'PAID',
        },
        {
          id: 'i-3',
          number: 'INV-2026-00312',
          issuedAt: this.at(-80, 9, 0),
          amount: 900,
          paidAmount: 900,
          currency,
          description: 'تقييم مبدئي',
          status: 'PAID',
        },
      ],
    });
  }

  // -------------------------------------------------------------------------
  // Requests
  // -------------------------------------------------------------------------

  override requests(): Observable<readonly ParentRequest[]> {
    return this.respond<readonly ParentRequest[]>([
      ...this.submitted,
      {
        id: 'q-1',
        kind: 'RESCHEDULE',
        subject: 'تغيير موعد جلسة التخاطب',
        outcome: 'نُقل إلى الحادية عشرة صباحًا',
        submittedAt: this.at(-7, 14, 0),
        status: 'ACCEPTED',
      },
      {
        id: 'q-2',
        kind: 'CALLBACK',
        subject: 'مكالمة مع أ. منى خالد',
        outcome: null,
        submittedAt: this.at(-1, 18, 12),
        status: 'UNDER_REVIEW',
      },
    ]);
  }

  override submitRequest(request: NewRequest): Observable<ParentRequest> {
    const created: ParentRequest = {
      id: `q-${this.submitted.length + 100}`,
      kind: request.kind,
      subject: request.note,
      outcome: null,
      submittedAt: new Date().toISOString(),
      status: 'SUBMITTED',
    };
    this.submitted = [created, ...this.submitted];
    return this.respond(created);
  }

  // -------------------------------------------------------------------------
  // Consents
  // -------------------------------------------------------------------------

  /**
   * Live viewing is granted PER CHILD, so the fixture produces one row per
   * child - and deliberately grants it for one and not the other. A fixture
   * where every child is the same cannot show that the flag is the gate
   * rather than the family.
   */
  override consents(): Observable<readonly Consent[]> {
    return this.respond<readonly Consent[]>([
      {
        key: 'live_view', granted: true,
        childId: '1', childName: 'يوسف', decidedAt: this.at(-60, 10, 0),
      },
      {
        key: 'live_view', granted: false,
        childId: '2', childName: 'ملك', decidedAt: null,
      },
      {
        key: 'sms_notifications',
        granted: this.consentState.get('sms_notifications') ?? false,
        childId: null, childName: null, decidedAt: this.at(-60, 10, 0),
      },
      {
        key: 'activity_photos',
        granted: this.consentState.get('activity_photos') ?? false,
        childId: null, childName: null, decidedAt: this.at(-60, 10, 0),
      },
    ]);
  }

  override setConsent(key: ConsentKey, granted: boolean): Observable<Consent> {
    this.consentState.set(key, granted);
    return this.respond<Consent>({
      key,
      granted,
      childId: null,
      childName: null,
      decidedAt: new Date().toISOString(),
    });
  }

  // -------------------------------------------------------------------------
  // Live view
  // -------------------------------------------------------------------------

  override liveSession(childId: Uuid): Observable<LiveSession | null> {
    // Always live for Youssef so both states of the screen can be reviewed:
    // his card shows the running session, Malak's shows the closed one. The
    // real answer depends on the session's state machine on the server.
    return this.respond(childId === this.youssefId ? this.session() : null);
  }

  override requestStreamTicket(sessionId: Uuid): Observable<StreamTicket> {
    if (!this.consentState.get('live_view')) {
      // Shaped like the server's refusal so the screen's error path is real
      // code, not a branch that only runs in production.
      return throwError(() => ({ status: 403, error: { code: 'CONSENT_REQUIRED' } }))
        .pipe(delay(this.latencyMs));
    }
    // No token: the real service never sends one to a client, so a fixture
    // that produced one would be teaching the screens a habit the contract
    // forbids.
    return this.respond<StreamTicket>({
      expiresAt: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
      playbackUrl: '',
    });
  }

  override markMoment(): Observable<void> {
    return this.respond(undefined as void);
  }

  /**
   * A feed with one of each shape the screen has to draw: read and unread, a
   * kind that leads somewhere and a kind that leads nowhere, one about a named
   * child and one about none. A fixture of five identical rows proves the list
   * renders and nothing else.
   */
  override notifications(): Observable<NotificationFeed> {
    return this.respond({
      rows: this.feed,
      unread: this.feed.filter((row) => !row.read).length,
      total: this.feed.length,
    });
  }

  override markNotificationRead(id: string): Observable<void> {
    this.feed = this.feed.map((row) => row.id === id ? { ...row, read: true } : row);
    return this.respond(undefined as void);
  }

  private feed: readonly PortalNotification[] = [
    {
      id: '1', kind: 'REPORT_PUBLISHED', title: 'تقرير تقدّم جديد',
      body: 'تقرير التقدّم — سبتمبر', childId: '1', childName: 'يوسف',
      createdAt: new Date(Date.now() - 2 * 3600_000).toISOString(),
      read: false, target: ['/reports', '9001'],
    },
    {
      id: '2', kind: 'APPOINTMENT_BOOKED', title: 'تم تأكيد موعد',
      body: null, childId: '1', childName: 'يوسف',
      createdAt: new Date(Date.now() - 26 * 3600_000).toISOString(),
      read: false, target: ['/schedule'],
    },
    {
      id: '3', kind: 'INVOICE_ISSUED', title: 'فاتورة جديدة',
      body: 'INV-2026-0007 — 600 EGP', childId: null, childName: null,
      createdAt: new Date(Date.now() - 5 * 86_400_000).toISOString(),
      read: true, target: ['/billing'],
    },
    {
      // No target on purpose: the screen must render an item that is news
      // and not a door, rather than inventing a destination for it.
      id: '4', kind: 'SESSION_STARTED', title: 'بدأت جلسة',
      body: null, childId: '2', childName: 'ملك',
      createdAt: new Date(Date.now() - 9 * 86_400_000).toISOString(),
      read: true, target: null,
    },
  ];

  // -------------------------------------------------------------------------
  // Fixture plumbing
  // -------------------------------------------------------------------------

  private youssef(): Child {
    return {
      id: this.youssefId,
      fullName: 'يوسف علي محمود',
      childNo: 'CH-00021',
      birthDate: this.at(-6 * 365 - 40, 0, 0),
      services: ['تخاطب', 'علاج وظيفي'],
      scheduleUnavailable: false,
      liveSessionId: this.liveSessionId,
      nextAppointment: {
        id: 'ap-1',
        startsAt: this.at(0, 16, 30),
        endsAt: this.at(0, 17, 15),
        serviceName: 'تخاطب وتنمية لغة',
        therapistId: '46',
        therapistName: 'سارة عبد الرحمن',
        roomName: 'غرفة ٢',
        status: 'IN_PROGRESS',
      },
    };
  }

  private malak(): Child {
    return {
      id: this.malakId,
      fullName: 'ملك علي محمود',
      childNo: 'CH-00034',
      birthDate: this.at(-4 * 365 - 120, 0, 0),
      services: ['تنمية مهارات'],
      scheduleUnavailable: false,
      liveSessionId: null,
      nextAppointment: {
        id: 'ap-9',
        startsAt: this.at(4, 11, 0),
        endsAt: this.at(4, 11, 45),
        serviceName: 'تنمية مهارات',
        therapistId: '46',
        therapistName: 'هدى سمير',
        roomName: 'غرفة ٥',
        status: 'CONFIRMED',
      },
    };
  }

  private session(): LiveSession {
    return {
      sessionId: this.liveSessionId,
      childName: 'يوسف علي محمود',
      serviceName: 'تخاطب وتنمية لغة',
      therapistName: 'سارة عبد الرحمن',
      roomName: 'غرفة ٢',
      // Twelve minutes ago, not a fixed hour of the day. A session pinned to
      // half past four reads as not yet started to anyone opening the screen
      // in the morning, and the elapsed clock - correctly - shows zero.
      startedAt: new Date(Date.now() - 12 * 60 * 1000).toISOString(),
    };
  }

  private progressReport(): ReportSummary {
    return {
      id: 'r-1',
      kind: 'PROGRESS',
      title: 'تقرير التقدّم — الشهر الحالي',
      authorName: 'سارة عبد الرحمن',
      publishedAt: this.at(-1, 12, 0),
      unread: true,
    };
  }

  private upcomingFor(childId: Uuid): AppointmentSummary[] {
    if (childId === this.malakId) {
      return [this.malak().nextAppointment as AppointmentSummary];
    }
    return [
      this.youssef().nextAppointment as AppointmentSummary,
      {
        id: 'ap-2',
        startsAt: this.at(4, 10, 0),
        endsAt: this.at(4, 10, 45),
        serviceName: 'علاج وظيفي',
        therapistId: '46',
        therapistName: 'منى خالد',
        roomName: 'غرفة ٤',
        status: 'CONFIRMED',
      },
      {
        id: 'ap-3',
        startsAt: this.at(7, 16, 30),
        endsAt: this.at(7, 17, 15),
        serviceName: 'تخاطب وتنمية لغة',
        therapistId: '46',
        therapistName: 'سارة عبد الرحمن',
        roomName: 'غرفة ٢',
        status: 'BOOKED',
      },
      {
        id: 'ap-4',
        startsAt: this.at(11, 10, 0),
        endsAt: this.at(11, 10, 45),
        serviceName: 'علاج وظيفي',
        therapistId: '46',
        therapistName: 'منى خالد',
        roomName: 'غرفة ٤',
        status: 'BOOKED',
      },
    ];
  }

  private pastFor(childId: Uuid): AppointmentSummary[] {
    if (childId === this.malakId) {
      return [];
    }
    return [
      {
        id: 'ap-p1',
        startsAt: this.at(-3, 16, 30),
        endsAt: this.at(-3, 17, 15),
        serviceName: 'تخاطب وتنمية لغة',
        therapistId: '46',
        therapistName: 'سارة عبد الرحمن',
        roomName: 'غرفة ٢',
        status: 'COMPLETED',
      },
      {
        id: 'ap-p2',
        startsAt: this.at(-7, 10, 0),
        endsAt: this.at(-7, 10, 45),
        serviceName: 'علاج وظيفي',
        therapistId: '46',
        therapistName: 'منى خالد',
        roomName: 'غرفة ٤',
        status: 'COMPLETED',
      },
      {
        id: 'ap-p3',
        startsAt: this.at(-10, 16, 30),
        endsAt: this.at(-10, 17, 15),
        serviceName: 'تخاطب وتنمية لغة',
        therapistId: '46',
        therapistName: 'سارة عبد الرحمن',
        roomName: 'غرفة ٢',
        status: 'NO_SHOW',
      },
    ];
  }

  /**
   * A UTC instant for a wall-clock time in the centre's zone, `days` from
   * today. Fixtures are written the way the centre talks about them - "today
   * at half past four" - and stored the way everything is stored: UTC.
   *
   * The zone offset is read at the current instant. That is exact except for
   * a fixture that straddles a daylight-saving change, which is acceptable
   * for sample data and would not be for a real appointment.
   */
  private at(days: number, hour: number, minute: number): string {
    const now = new Date();
    const offsetMinutes = this.zoneOffsetMinutes(now);
    const local = new Date(now.getTime() + offsetMinutes * 60_000);
    const utcMidnight = Date.UTC(
      local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate() + days,
      hour, minute, 0);
    return new Date(utcMidnight - offsetMinutes * 60_000).toISOString();
  }

  /** Minutes the centre's zone is ahead of UTC at the given instant. */
  private zoneOffsetMinutes(at: Date): number {
    const parts = new Intl.DateTimeFormat('en-GB', {
      timeZone: this.config.timeZone,
      timeZoneName: 'longOffset',
    }).formatToParts(at);
    const name = parts.find((p) => p.type === 'timeZoneName')?.value ?? 'GMT+00:00';
    const match = /GMT([+-])(\d{2}):(\d{2})/.exec(name);
    if (!match) {
      return 0;
    }
    const sign = match[1] === '-' ? -1 : 1;
    return sign * (Number(match[2]) * 60 + Number(match[3]));
  }

  /**
   * The two fields a parent owns, held in memory like every other fixture
   * write here - so the edit form can be driven end to end without the
   * service, and a saved value survives to the next read of the screen.
   */
  private contactState: GuardianContact = { email: '', city: '' };

  override contact(): Observable<GuardianContact> {
    return this.respond<GuardianContact>({ ...this.contactState });
  }

  override setContact(value: GuardianContact): Observable<GuardianContact> {
    this.contactState = { email: value.email.trim(), city: value.city.trim() };
    return this.respond<GuardianContact>({ ...this.contactState });
  }

  private respond<T>(value: T): Observable<T> {
    return of(value).pipe(delay(this.latencyMs));
  }
}
