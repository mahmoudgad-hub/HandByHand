import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, catchError, forkJoin, map, of, switchMap, throwError, tap } from 'rxjs';
import { UserAvatars } from '@hbh/shared/ui/user-avatar';
import { reportDisplayTitle } from './report-title';

import { Result, dataOr, ok, resilient } from './result';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import {
  AppointmentStatus,
  AppointmentSummary,
  AttentionItem,
  BillingOverview,
  Child,
  Consent,
  ConsentKey,
  Guardian,
  CentreContact,
  GuardianContact,
  HomeProgramme,
  HomeActivity,
  HomeSummary,
  LastSession,
  Invoice,
  InvoiceStatus,
  LiveSession,
  MeetingPass,
  NewRequest,
  ParentRequest,
  ProgressOverview,
  ReportDetail,
  ReportSummary,
  RequestStatus,
  ServicePackage,
  StreamTicket,
  TherapistProfile,
  Uuid,
  NotificationFeed,
  PortalNotification,
  WelcomeSummary,
} from '../models/portal.models';
import { PortalApi } from './portal-api';

/**
 * The portal against the real service.
 *
 * THIS FILE IS AN ADAPTER, and it had to be rewritten from scratch. The
 * version before it called ten endpoints that do not exist - /me/welcome,
 * /me/billing, /me/consents, /children/{id}/home, /progress, /home-programme,
 * /live, /sessions/{id}/moments, /stream-ticket - because it was written
 * against a contract that was imagined before the service was built. It had
 * never run: the portal shipped on fixtures, so nothing ever proved the
 * guesses wrong.
 *
 * The screens above are unchanged and keep their own vocabulary. Translating
 * between that vocabulary and the service's is this file's whole job, and
 * every place the two genuinely disagree is commented rather than smoothed
 * over, because the disagreements are where a wrong assumption would hide.
 *
 * THE SHAPE OF THE SERVICE, which explains most of what follows: there is no
 * "dashboard" endpoint and no "welcome" endpoint. There are lists, indexed by
 * child. A screen that wants six things asks for six things, in parallel, and
 * this file assembles them. That is more requests than one hand-built summary
 * endpoint, and it is the honest cost of not having invented one.
 */
@Injectable()
export class HttpPortalApi extends PortalApi {
  private readonly http = inject(HttpClient);
  private readonly avatars = inject(UserAvatars);
  private readonly base = `${inject(HBH_CONFIG).apiBaseUrl}/api/v1`;

  // =====================================================================
  // Identity and children
  // =====================================================================

  private me(): Observable<MeResponse> {
    return this.http.get<MeResponse>(`${this.base}/me`).pipe(tap(me => {
      if(this.avatars.viewer() !== me.user.user_id) this.avatars.reset(me.user.user_id);
    }));
  }

  private children(): Observable<readonly ChildRow[]> {
    return this.http
      .get<{ children?: readonly ChildRow[] }>(`${this.base}/children`)
      .pipe(map((body) => body.children ?? []));
  }

  /**
   * The welcome screen: who they are, their children, and what is waiting.
   *
   * `attention` is assembled here because no endpoint answers "what needs
   * this family's attention". It is built only from things actually counted -
   * money outstanding, activities not done - and never padded: an invented
   * line on this screen is a parent told to do something that does not exist.
   */
  family(): Observable<Pick<WelcomeSummary, 'guardian' | 'children'>> {
    return forkJoin({ me: this.me(), children: this.children() }).pipe(map(({ me, children }) => ({
      guardian: toGuardian(me),
      // The diary was not asked, which is not "nothing booked".
      children: children.map((child) => toChild(child, null, null, true)),
    })));
  }

  welcome(): Observable<WelcomeSummary> {
    return forkJoin({ me: this.me(), children: this.children() }).pipe(
      switchMap(({ me, children }) => {
        if (children.length === 0) {
          return of({
            guardian: toGuardian(me),
            children: [] as readonly Child[],
            attention: [] as readonly AttentionItem[],
          });
        }
        // Per child, the three things the welcome screen can actually say
        // something about. In parallel: a family with four children should
        // not wait four round trips deep.
        //
        // EVERY LEG HERE IS OPTIONAL, and each is wrapped on its own. The
        // screen is the guardian and their children - `me` and `children`
        // above are what it is ABOUT, and they stay bare so a failure there
        // is still a screen-level error. Everything below decorates a card.
        //
        // Unwrapped, one failing balance call cancelled its four siblings
        // AND every other child's four, and the parent got an empty page.
        // That was observed, not theorised. Now child B's card is unharmed
        // by child A's billing, and a missing balance is a card that says
        // so rather than a card that says nothing is owed.
        return forkJoin(children.map((child) => forkJoin({
          child: of(child),
          appointments: resilient(this.appointmentRows(child.child_id)),
          sessions: resilient(this.sessionRows(child.child_id)),
          balance: resilient(this.balanceOf(child.child_id)),
          activities: resilient(this.activityRows(child.child_id)),
        }))).pipe(map((parts) => ({
          guardian: toGuardian(me),
          children: parts.map((part) => toChild(
            part.child,
            // A diary that did not load is not "no appointment booked", so
            // the card is told which of the two it is.
            part.appointments.state === 'ok'
              ? nextAppointment(part.appointments.data) : null,
            part.sessions.state === 'ok'
              ? liveSessionIdOf(part.sessions.data) : null,
            part.appointments.state === 'failed',
          )),
          attention: attentionFrom(parts),
        })));
      }),
    );
  }

  // =====================================================================
  // One child's dashboard
  // =====================================================================

  home(childId: Uuid): Observable<HomeSummary> {
    const id = Number(childId);
    // `child` is what this screen IS - without it there is nothing to draw
    // and a screen-level error is the honest answer. The other five each
    // fill one section, so each survives on its own.
    return forkJoin({
      child: this.http.get<ChildRow>(`${this.base}/children/${id}`),
      appointments: resilient(this.appointmentRows(id)),
      sessions: resilient(this.sessionRows(id)),
      balance: resilient(this.balanceOf(id)),
      activities: resilient(this.activityRows(id)),
      reports: resilient(this.reportRows(id)),
    }).pipe(map((parts) => {
      const appointments = dataOr(parts.appointments, [] as readonly AppointmentRow[]);
      const sessions = dataOr(parts.sessions, [] as readonly SessionRow[]);
      const activities = dataOr(parts.activities, [] as readonly ActivityRow[]);
      const reports = dataOr(parts.reports, [] as readonly ReportRow[]);
      const upcoming = upcomingOnly(appointments);
      return {
        child: toChild(parts.child, upcoming[0] ?? null, liveSessionIdOf(sessions),
          parts.appointments.state === 'failed'),
        nextAppointment: upcoming[0] ?? null,
        scheduleUnavailable: parts.appointments.state === 'failed',
        activitiesUnavailable: parts.activities.state === 'failed',
        reportsUnavailable: parts.reports.state === 'failed',
        live: liveSessionFrom(sessions, parts.child),
        upcoming: upcoming.slice(0, 3),
        // Not done yet. The service has no "open" flag on an activity, so
        // this is derived from the log the same way the home programme
        // screen derives it - one rule, one place.
        openActivityCount: activities.filter((row) => !row.done_today).length,

        // The three below cost nothing extra: sessions, reports and
        // activities are already being fetched for the counts above.
        lastSession: lastCompletedSession(sessions),
        // Reports come back newest first from the service; the first is the
        // most recent thing the therapist chose to publish.
        latestUpdate: reports.length ? toReport(reports[0]) : null,
        todayActivity: firstOpenActivity(activities),
        // The service has no read/unread state and no table that could hold
        // one. Every published report counts as something to look at rather
        // than pretending to know what this parent has already read.
        unreadReportCount: reports.length,
        // NULL, NOT ZERO. `dueAmount: 0` and "we could not read the balance"
        // are different sentences, and only one of them is safe to show a
        // family. The card reads null as "unavailable" and says so.
        dueAmount: parts.balance.state === 'ok'
          ? Number(parts.balance.data.outstanding_amt) : null,
        currency: parts.balance.state === 'ok' ? parts.balance.data.currency_code : '',
        balanceUnavailable: parts.balance.state === 'failed',
      };
    }));
  }

  // =====================================================================
  // Appointments
  // =====================================================================

  /**
   * The child's diary, split the way the screen asks for it.
   *
   * "upcoming" and "past" are the PORTAL's words. The service takes `from`
   * and `to` as instants and knows nothing about either, so the split happens
   * here - and it must, because sending the word through was the defect this
   * replaced: `?from=upcoming` came back 400 and the screen bounced the
   * parent to the welcome page with "could not load".
   *
   * A cancelled or missed appointment counts as past whatever its clock says:
   * nobody is waiting for it.
   */
  appointments(
    childId: Uuid, scope: 'upcoming' | 'past',
  ): Observable<readonly AppointmentSummary[]> {
    return this.appointmentRows(Number(childId)).pipe(map((rows) => {
      if (scope === 'upcoming') {
        return upcomingOnly(rows);
      }
      const now = Date.now();
      return rows
        .filter((row) => Date.parse(row.starts_at) < now
          || ['CANCELLED', 'NO_SHOW', 'COMPLETED'].includes(row.status))
        .sort((a, b) => Date.parse(b.starts_at) - Date.parse(a.starts_at))
        .map(toAppointment);
    }));
  }

  private appointmentRows(id: number): Observable<readonly AppointmentRow[]> {
    return this.http
      .get<{ appointments?: readonly AppointmentRow[] }>(
        `${this.base}/children/${id}/appointments`)
      .pipe(map((body) => body.appointments ?? []));
  }

  private sessionRows(id: number): Observable<readonly SessionRow[]> {
    return this.http
      .get<{ sessions?: readonly SessionRow[] }>(`${this.base}/children/${id}/sessions`)
      .pipe(map((body) => body.sessions ?? []));
  }

  // =====================================================================
  // Progress
  // =====================================================================

  /**
   * The plan and its goals.
   *
   * The service returns every plan; the screen shows one. The ACTIVE plan is
   * chosen, falling back to the most recent - a child between plans should
   * see the work that was done, not an empty screen.
   *
   * The measurement series behind each goal is NOT fetched. hbh.v_goal_progress
   * gives the latest percentage and a count, and there is no endpoint that
   * returns the points. The chart draws what it has; it does not invent a
   * curve between two numbers.
   */
  progress(childId: Uuid): Observable<ProgressOverview> {
    const id = Number(childId);
    return forkJoin({
      plans: this.http
        .get<{ plans?: readonly PlanRow[] }>(`${this.base}/children/${id}/plans`)
        .pipe(map((body) => body.plans ?? [])),
      reports: this.reportRows(id),
    }).pipe(map(({ plans, reports }) => {
      const plan = plans.find((row) => row.status === 'ACTIVE') ?? plans[0] ?? null;
      return {
        planTitle: plan?.title_ar ?? '',
        goals: (plan?.goals ?? []).map((goal) => ({
          id: String(goal.goal_id),
          title: goal.title_ar,
          // No fallback to the baseline. `latest_pct` is null until somebody
          // measures, and null is what the screen must be told: the baseline
          // is where the goal started, and passing it off as the current
          // figure told parents their child had made progress that had never
          // been assessed.
          currentPercent: goal.latest_pct ?? null,
          baselinePercent: goal.baseline_pct ?? null,
          targetPercent: goal.target_pct ?? 100,
          measurementCount: goal.measurement_count ?? 0,
          lastMeasuredAt: goal.latest_measured_on ?? null,
          series: [],
        })),
        latestReport: reports.length ? toReport(reports[0]) : null,
      };
    }));
  }

  // =====================================================================
  // Home programme
  // =====================================================================

  homeProgramme(childId: Uuid): Observable<HomeProgramme> {
    const id = Number(childId);
    return this.http
      .get<{ activities?: readonly ActivityRow[] }>(`${this.base}/children/${id}/activities`)
      .pipe(map((body) => {
        const activities = body.activities ?? [];
        const done = activities.filter((row) => row.done_today).length;
        return {
          // The service scopes the programme itself; these bounds exist for
          // the heading and are the week the person is looking at.
          weekStart: startOfWeek(),
          weekEnd: endOfWeek(),
          completed: done,
          total: activities.length,
          activities: activities.map((row) => ({
            id: String(row.child_activity_id),
            title: row.title_ar ?? '',
            // The therapist's own instruction for this child, and the
            // library's standing how-to, kept SEPARATE. They used to collapse
            // with ?? - so a child with a specific instruction never showed
            // the method, and the two could never appear together.
            instructions: row.instructions_ar ?? '',
            howTo: row.how_to_ar ?? '',
            timesPerWeek: row.times_per_week ?? 0,
            minutesEach: row.minutes_each ?? 0,
            dueOn: row.end_date ?? '',
            completedAt: row.done_today ? (row.last_done_at || new Date().toISOString()) : null,
          })),
        };
      }));
  }

  /**
   * Logging an activity is one-way: the service records that it was done.
   *
   * There is no endpoint that un-does it, so `done: false` is refused here
   * rather than sent and silently ignored. A tick that appears to come back
   * off and then returns on the next load is worse than one that never moved.
   */
  setActivityDone(childId: Uuid, activityId: Uuid, done: boolean): Observable<void> {
    if (!done) {
      return throwError(() => new Error('Activity logs cannot be undone'));
    }
    return this.http.post<void>(
      `${this.base}/children/${Number(childId)}/activities/${Number(activityId)}/log`, {});
  }

  // =====================================================================
  // Reports
  // =====================================================================

  /**
   * The published record: reports under one tab, session notes under the other.
   *
   * The scope used to be accepted and then dropped, so the notes tab quietly
   * showed reports and no screen in the portal ever read a note. A clinician
   * could publish one and it landed nowhere.
   *
   * Nothing is filtered here. GET /children/{id}/notes returns what the policy
   * admits, and for a guardian that is PARENT-visible, not a draft, approved -
   * so an internal note never reaches this code to be filtered out of. A
   * filter in a screen is not a boundary.
   */
  reports(childId: Uuid, scope: 'reports' | 'notes' = 'reports'): Observable<readonly ReportSummary[]> {
    if (scope === 'notes') {
      return this.http
        .get<{ notes?: readonly NoteRow[] }>(`${this.base}/children/${Number(childId)}/notes`)
        .pipe(map((body) => (body.notes ?? []).map(toNote)));
    }
    return this.reportRows(Number(childId)).pipe(map((rows) => rows.map(toReport)));
  }

  /**
   * One report, opened.
   *
   * GET /reports/{id} carries the whole thing - summary and the state of each
   * goal at the time - and RLS admits a guardian only to a PUBLISHED one, so
   * there is no status check to repeat here. A draft answers 404 and is
   * recorded as a denial in the audit trail.
   */
  report(reportId: Uuid): Observable<ReportDetail> {
    return this.http
      .get<ReportDetailRow>(`${this.base}/reports/${Number(reportId)}`)
      .pipe(map((row) => ({
        id: String(row.report_id),
        number: row.report_no,
        title: reportDisplayTitle(row.title_ar, row.report_id),
        summary: row.summary_ar ?? '',
        periodStart: row.period_start ?? null,
        periodEnd: row.period_end ?? null,
        publishedAt: row.published_at ?? null,
        goals: (row.goals_snapshot ?? []).map((goal) => ({
          title: goal.title_ar,
          // Same rule as the progress screen: an unmeasured goal has no
          // percentage, and the baseline is not one.
          latestPercent: goal.latest_pct ?? null,
          baselinePercent: goal.baseline_pct ?? null,
          targetPercent: goal.target_pct ?? null,
        })),
      })));
  }

  private reportRows(id: number): Observable<readonly ReportRow[]> {
    return this.http
      .get<{ reports?: readonly ReportRow[] }>(`${this.base}/children/${id}/reports`)
      .pipe(map((body) => body.reports ?? []));
  }

  // =====================================================================
  // Billing
  // =====================================================================

  /**
   * Billing is per child in this service, and the screen is per family.
   *
   * So it is fetched for every child and merged. `dueAmount` is a sum of
   * sums the SERVICE calculated - each child's own outstanding total - never
   * a total this client assembled from a page of invoice rows.
   */
  billing(
    sections: ReadonlySet<'balance' | 'packages' | 'invoices'> = new Set(['balance', 'packages', 'invoices']),
  ): Observable<BillingOverview> {
    // A section not asked for is not requested. Its placeholder is an
    // empty success, never a failure - but the screen must not read it
    // either way (see features/billing/billing-sections.ts).
    const skip = <T>(value: T): Observable<Result<T>> => of(ok(value));
    return this.children().pipe(switchMap((children) => {
      if (children.length === 0) {
        return of({ dueAmount: 0, currency: '', packages: [], invoices: [],
          balanceUnavailable: false, packagesUnavailable: false, invoicesUnavailable: false });
      }
      // Three independent sections, wrapped independently. This is the
      // aggregate the audit watched blank the screen: one child's balance
      // erroring cancelled that child's invoices and packages AND every
      // other child's, and a family with an unpaid invoice saw "تعذّر تحميل
      // البيانات" instead of the money they owed.
      return forkJoin(children.map((child) => forkJoin({
        balance: sections.has('balance')
          ? resilient(this.balanceOf(child.child_id))
          : skip<BalanceRow>({ outstanding_amt: '0', currency_code: '', open_invoice_count: 0 }),
        invoices: sections.has('invoices')
          ? resilient(this.http
            .get<{ invoices?: readonly InvoiceRow[] }>(
              `${this.base}/children/${child.child_id}/invoices`)
            .pipe(map((body) => body.invoices ?? [])))
          : skip<readonly InvoiceRow[]>([]),
        packages: sections.has('packages')
          ? resilient(this.http
            .get<{ packages?: readonly PackageRow[] }>(
              `${this.base}/children/${child.child_id}/packages`)
            .pipe(map((body) => body.packages ?? [])))
          : skip<readonly PackageRow[]>([]),
      }))).pipe(map((parts) => {
        // A TOTAL IS ONLY A TOTAL IF EVERY PART ARRIVED. Summing the
        // balances that happened to load would show a family a smaller
        // number than they owe - the one arithmetic mistake on this screen
        // that could cost somebody money. If any child's balance is
        // missing, the figure is withheld rather than understated.
        const balances = parts.map((part) => part.balance);
        const allBalances = balances.every((b) => b.state === 'ok');
        return {
          dueAmount: allBalances
            ? balances.reduce((sum, b) => sum + Number(
                (b as { state: 'ok'; data: BalanceRow }).data.outstanding_amt), 0)
            : null,
          currency: balances.find((b) => b.state === 'ok')
            ? (balances.find((b) => b.state === 'ok') as
                { state: 'ok'; data: BalanceRow }).data.currency_code
            : '',
          balanceUnavailable: !allBalances,
          // Each list is the union of what loaded, and says whether any
          // child's list is missing. An empty list with no failure means
          // there genuinely are none - which is a different sentence.
          packages: parts.flatMap((part) =>
            dataOr(part.packages, [] as readonly PackageRow[]).map(toPackage)),
          packagesUnavailable: parts.some((part) => part.packages.state === 'failed'),
          invoices: parts.flatMap((part) =>
            dataOr(part.invoices, [] as readonly InvoiceRow[]).map(toInvoice)),
          invoicesUnavailable: parts.some((part) => part.invoices.state === 'failed'),
        };
      }));
    }));
  }

  private balanceOf(id: number): Observable<BalanceRow> {
    return this.http.get<BalanceRow>(`${this.base}/children/${id}/balance`);
  }

  private activityRows(id: number): Observable<readonly ActivityRow[]> {
    return this.http
      .get<{ activities?: readonly ActivityRow[] }>(`${this.base}/children/${id}/activities`)
      .pipe(map((body) => body.activities ?? []));
  }

  // =====================================================================
  // Requests
  // =====================================================================

  requests(): Observable<readonly ParentRequest[]> {
    return this.children().pipe(switchMap((children) => {
      if (children.length === 0) {
        return of([] as readonly ParentRequest[]);
      }
      return forkJoin(children.map((child) => this.http
        .get<{ requests?: readonly RequestRow[] }>(
          `${this.base}/children/${child.child_id}/requests`)
        .pipe(map((body) => body.requests ?? []))))
        .pipe(map((lists) => lists.flat().map(toRequest)));
    }));
  }

  /** The selected child is explicit; the server checks the guardian's access. */
  submitRequest(request: NewRequest): Observable<ParentRequest> {
    return this.http.post<RequestRow>(
        `${this.base}/children/${Number(request.childId)}/requests`,
        {
          kind_code: request.kind,
          body_ar: request.note,
          appointment_id: request.appointmentId ? Number(request.appointmentId) : undefined,
        },
      ).pipe(map(toRequest));
  }

  // =====================================================================
  // Profile and consents
  // =====================================================================

  profile(): Observable<Guardian> {
    return this.me().pipe(map(toGuardian));
  }

  /**
   * One therapist, and the services they practise.
   *
   * TWO CALLS, because the service keeps them apart for a reason: the
   * therapist row is a person, and therapist_services is keyed on the PAIR
   * (therapist, service) with no surrogate id, so it cannot hang off /{id}
   * the way a column would.
   *
   * The service names are resolved against the catalogue, which a guardian
   * may read. A service the catalogue does not return is dropped rather than
   * shown as its number: an identifier on a parent's screen is noise.
   *
   * The mobile is not requested and has nowhere to land. The service already
   * withholds it from a guardian; this is the second wall, not the first.
   */
  therapist(therapistId: Uuid): Observable<TherapistProfile> {
    const id = Number(therapistId);
    return forkJoin({
      person: this.http.get<TherapistRow>(`${this.base}/therapists/${id}`),
      links: this.http
        .get<Record<string, unknown>>(`${this.base}/therapists/${id}/services`)
        .pipe(map((body) => firstArray(body))),
      catalogue: this.http
        .get<{ services?: readonly ServiceRow[] }>(`${this.base}/services`)
        .pipe(map((body) => body.services ?? [])),
      languages: this.http
        .get<{ languages?: readonly LanguageRow[] }>(`${this.base}/therapists/${id}/languages`)
        .pipe(map((body) => body.languages ?? [])),
      certificates: this.http
        .get<{ certificates?: readonly CertificateRow[] }>(
          `${this.base}/therapists/${id}/certificates`)
        .pipe(map((body) => body.certificates ?? [])),
      qualifications: this.http
        .get<Record<string, unknown>>(`${this.base}/therapist-qualifications`)
        .pipe(map((body) => firstArray(body) as readonly QualificationRow[])),
    }).pipe(map((parts) => {
      const names = new Map(parts.catalogue.map((row) => [row.service_id, row.name_ar]));
      const published = parts.person.profile_status === 'PUBLISHED';
      return {
        id: String(parts.person.therapist_id),
        fullName: parts.person.full_name_ar,
        title: parts.person.title_ar ?? '',
        status: parts.person.status,
        services: parts.links
          .map((link) => names.get(Number((link as { service_id?: number }).service_id)))
          .filter((name): name is string => !!name),

        published,
        // The biography and the practice year are on the therapist ROW, and
        // the service sends them to a family even while the profile is a
        // DRAFT - unlike the languages and certificates, which it correctly
        // withholds until publication. Withheld here as well, because the
        // whole point of the state is that nothing about a named person
        // reaches a third party before that person has agreed.
        // Reported; this is the client half of the fix, not the fix.
        bio: published ? parts.person.bio_ar ?? '' : '',
        yearsOfPractice: published ? yearsSince(parts.person.practice_since_year) : null,
        ageFromMonths: published ? parts.person.age_from_mon ?? null : null,
        ageToMonths: published ? parts.person.age_to_mon ?? null : null,

        // These three the SERVICE already gates, and they arrive empty on a
        // draft. Mapped as they come.
        languages: parts.languages.map((row) => ({
          code: row.lang_code,
          runsSessions: !!row.runs_sessions,
          isNative: !!row.is_native,
          levelCode: row.level_code ?? '',
        })),
        qualifications: parts.qualifications
          .filter((row) => Number(row.therapist_id) === id)
          .map((row) => ({
            id: String(row.qualification_id),
            year: row.year_awarded ?? null,
            title: row.title_ar,
            issuer: row.issuer_ar ?? '',
          })),
        certificates: parts.certificates.map((row) => ({
          id: String(row.certificate_id),
          title: row.title_ar,
          issuer: row.issuer_ar ?? '',
          year: row.year_awarded ?? null,
          hasImage: !!row.has_image,
          // Null unless the image was published AND this reader may open it.
          // The service decides; nothing here re-derives that.
          attachmentId: row.attachment_id ? String(row.attachment_id) : null,
        })),
      };
    }));
  }

  /**
   * Consents are READ ONLY, and that is the service's design rather than an
   * omission here.
   *
   * They live as flags on the guardian-child link - can_view_live,
   * can_view_reports - and arrive on each child. There is no endpoint that
   * writes them, deliberately: watching a child in therapy needs a recorded
   * consent (D-24), and a toggle a guardian can flip for themselves is not a
   * recorded consent. The centre grants it.
   *
   * ONE ROW PER CHILD for live viewing, because the flag is per child.
   *
   * It was collapsed to one family-wide answer at first - granted only if it
   * held for every child - which looks like the cautious reading and is not:
   * a family permitted to watch one child and not their sibling would have
   * been shown a closed door for BOTH, and the permission the centre
   * deliberately granted would have been invisible. The safe direction is
   * still the wrong answer when it contradicts a decision somebody made.
   *
   * The two below it have no counterpart anywhere in the schema. They are
   * shown off rather than hidden, so that a family is not left believing the
   * centre holds a preference it has no way to record.
   */
  consents(): Observable<readonly Consent[]> {
    return this.children().pipe(map((children) => [
      ...children.map((child) => ({
        key: 'live_view' as ConsentKey,
        granted: !!child.link?.can_view_live,
        childId: String(child.child_id),
        childName: child.full_name_ar,
        decidedAt: null,
      })),
    ]));
  }

  /**
   * Refused, because there is nothing to call.
   *
   * Kept fail-closed for callers of the abstract API. The profile displays
   * recorded access and does not offer this unsupported operation.
   */
  setConsent(): Observable<Consent> {
    return new Observable<Consent>((subscriber) =>
      subscriber.error({ status: 405, error: { error: { code: 'FORBIDDEN' } } }));
  }

  /**
   * How to reach the centre.
   *
   * The site-contact resource returns a LIST of one - the table holds one
   * row per centre and the policy narrows it to the caller's - so the
   * first row is taken and an empty list becomes null. Null is a real
   * answer: a centre that has not published a contact row yet, and the
   * screen says that instead of drawing a call button that dials nothing.
   *
   * Wrapped in catchError for the same reason: a family reading their
   * profile must not lose the page because one card could not load.
   */
  centreContact(): Observable<CentreContact | null> {
    return this.http
      .get<{ 'site-contact'?: readonly ContactRow[] }>(`${this.base}/site-contact`)
      .pipe(
        map((body) => {
          const row = (body['site-contact'] ?? [])[0];
          return row ? toCentreContact(row) : null;
        }),
        catchError(() => of<CentreContact | null>(null)),
      );
  }

  /** The two fields a parent owns. See GuardianContact for what is absent. */
  contact(): Observable<GuardianContact> {
    return this.http.get<GuardianContact>(`${this.base}/me/contact`);
  }

  setContact(value: GuardianContact): Observable<GuardianContact> {
    // Both fields, always. An empty one clears the column - the service
    // reads it that way on purpose - so the screen sends exactly what it
    // is showing rather than trying to guess which of the two changed.
    return this.http.patch<GuardianContact>(`${this.base}/me/contact`, {
      email: value.email,
      city: value.city,
    });
  }

  // =====================================================================
  // Live view
  // =====================================================================

  liveSession(childId: Uuid): Observable<LiveSession | null> {
    const id = Number(childId);
    return forkJoin({
      child: this.http.get<ChildRow>(`${this.base}/children/${id}`),
      sessions: this.sessionRows(id),
    }).pipe(map(({ child, sessions }) => liveSessionFrom(sessions, child)));
  }

  /**
   * Opens the stream. The answer carries NO token, and that is the design.
   *
   * The credential is set as an HttpOnly cookie scoped to the playback path,
   * so the browser sends it and no script can read it. `withCredentials`
   * because in development the portal and the service are different origins
   * and the browser would otherwise drop the cookie.
   */
  requestStreamTicket(sessionId: Uuid): Observable<StreamTicket> {
    return this.http
      .post<StreamGrantRow>(
        `${this.base}/sessions/${Number(sessionId)}/stream`, {}, { withCredentials: true })
      .pipe(map((grant) => ({
        expiresAt: grant.expires_at,
        playbackUrl: `${this.base.replace(/\/api\/v1$/, '')}${grant.playback_path}`,
      })));
  }

  /**
   * Refused. A guardian cannot write on a session.
   *
   * hbh.can_edit_session admits the clinician who ran the session, holding
   * SESSION.NOTES.EDIT - a permission the seed gives to THERAPIST alone. A
   * parent has PORTAL.VIEW, REPORT.VIEW and REQUEST.SUBMIT. Sending this
   * would produce a 403 every time; refusing here says so without the trip.
   *
   * If the centre wants a parent to be able to flag a moment, that is a new
   * endpoint and a new permission, not a call this file can make.
   */
  markMoment(): Observable<void> {
    return new Observable<void>((subscriber) =>
      subscriber.error({ status: 403, error: { error: { code: 'FORBIDDEN' } } }));
  }

  /**
   * Opens the consultation. Unlike the stream above, the answer DOES carry a
   * credential - see MeetingPass for why it has to and what narrows it.
   *
   * No `withCredentials`, because there is no cookie in this exchange: the
   * session cookie for our own service is already attached by the
   * interceptor, and the provider's credential travels in the body. Passing
   * it would widen the request for nothing.
   *
   * The response is mapped field by field rather than cast. The wire shape
   * is snake_case and the model is not, and a cast would have quietly
   * produced an object whose every property was undefined - which reads, on
   * screen, as a provider that failed rather than a mapping that was never
   * written.
   */
  enterConsultation(appointmentId: Uuid): Observable<MeetingPass> {
    return this.http
      .post<MeetingPassRow>(
        `${this.base}/appointments/${Number(appointmentId)}/consultation`, {})
      .pipe(map((row) => ({
        provider: row.provider,
        domain: row.domain,
        room: row.room,
        // Absent for a provider with no tokens. Not a refusal - a refusal
        // is a status code, and this call would not have resolved.
        token: row.token ?? '',
        displayName: row.display_name,
        moderator: row.moderator,
        expiresAt: row.expires_at,
      })));
  }

  /**
   * ONE CALL, and that is the whole point of it.
   *
   * Every other aggregate on this screen fans out per child, because the
   * service has no endpoint that crosses them. The feed does: it is addressed
   * to a PERSON, so `/notifications` answers the whole family in one request
   * whatever number of children they have. No forkJoin, so nothing here needs
   * C4's Result wrapping - there is no partial state to preserve when a single
   * call fails.
   */
  notifications(limit = 30, offset = 0): Observable<NotificationFeed> {
    return this.http
      .get<NotificationFeedResponse>(`${this.base}/notifications?limit=${limit}${offset ? `&offset=${offset}` : ''}`)
      .pipe(map((body) => ({
        rows: (body.rows ?? []).map(toNotification),
        unread: body.unread ?? 0,
        total: body.total ?? 0,
      })));
  }

  markNotificationRead(id: string): Observable<void> {
    return this.http.post<void>(`${this.base}/notifications/${id}/read`, {});
  }

  markAllNotificationsRead(): Observable<number> {
    return this.http
      .post<{ marked?: number }>(`${this.base}/notifications/read-all`, {})
      .pipe(map((body) => body.marked ?? 0));
  }
}

// =====================================================================
// The service's row shapes. Named, not inlined, so a change to one of
// them is a compile error here rather than an undefined on a screen.
// =====================================================================

interface MeResponse {
  readonly user: { readonly user_id: number; readonly full_name_ar: string; readonly mobile?: string };
}

interface ChildLink {
  readonly relationship_code?: string;
  readonly is_primary?: boolean;
  readonly can_view_live: boolean;
  readonly can_view_reports: boolean;
}

interface ChildRow {
  readonly child_id: number;
  readonly child_no: string;
  readonly full_name_ar: string;
  readonly birth_date: string;
  readonly gender?: string | null;
  readonly link?: ChildLink;
  /** Absent from a service older than migration 0139. */
  readonly attendance_month?: { readonly attended?: unknown; readonly missed?: unknown } | null;
}

interface Named {
  readonly name_ar?: string;
  readonly full_name_ar?: string;
  readonly therapist_id?: number;
}

interface AppointmentRow {
  readonly appointment_id: number;
  readonly starts_at: string;
  readonly ends_at: string;
  readonly status: string;
  /**
   * Optional here and required in the model, on purpose.
   *
   * The service has sent this since the consultation work landed, but a
   * browser holding a cached bundle can still be talking to an older build
   * in either direction. Absent is read as IN_PERSON below, which is the
   * answer that draws no door - the safe way round. Typing it required
   * would not make the field arrive; it would make the compiler stop
   * asking what happens when it does not.
   */
  readonly delivery_mode?: string;
  readonly service?: Named;
  readonly therapist?: Named;
  readonly room?: Named;
}

interface SessionRow {
  readonly session_id: number;
  readonly started_at: string;
  readonly status: string;
  readonly service?: Named;
  readonly therapist?: Named;
  readonly room?: Named;
}

interface GoalRow {
  readonly goal_id: number;
  readonly title_ar: string;
  readonly baseline_pct?: number;
  readonly target_pct?: number;
  readonly latest_pct?: number;
  readonly latest_measured_on?: string;
  readonly measurement_count?: number;
}

interface PlanRow {
  readonly plan_id: number;
  readonly title_ar: string;
  readonly status: string;
  readonly goals?: readonly GoalRow[];
}

interface ReportDetailRow {
  readonly report_id: number;
  readonly report_no: string;
  readonly title_ar: string;
  readonly summary_ar?: string;
  readonly period_start?: string;
  readonly period_end?: string;
  readonly published_at?: string;
  readonly goals_snapshot?: readonly {
    readonly title_ar: string;
    readonly latest_pct?: number | null;
    readonly baseline_pct?: number | null;
    readonly target_pct?: number | null;
  }[];
}

interface ReportRow {
  readonly report_id: number;
  readonly title_ar: string;
  readonly published_at?: string;
  readonly published_by?: { readonly full_name_ar?: string };
}

/**
 * One session note as the service sends it.
 *
 * visibility is on the row but is not read here: a guardian is only ever sent
 * PARENT notes, so branching on it in the portal would be a second copy of a
 * rule the policy already applies - and the weaker copy would be this one.
 */
interface NoteRow {
  readonly note_id: number;
  readonly body_ar: string;
  readonly created_at?: string;
  readonly approved_at?: string;
  readonly author_ar?: string;
}

interface InvoiceRow {
  readonly invoice_id: number;
  readonly invoice_no: string;
  readonly issue_date: string;
  readonly total_amt: string;
  /** Already paid against this invoice. The service sends it; the screen
      used to drop it, which is why a 1,000 invoice marked "partly paid"
      showed no sign of the 400 that had been paid. */
  readonly paid_amt: string;
  readonly currency_code: string;
  readonly status: string;
}

interface PackageRow {
  readonly child_package_id: number;
  readonly name_ar: string;
  readonly sessions_used: number;
  readonly sessions_total: number;
  readonly expires_on?: string;
}

interface BalanceRow {
  readonly currency_code: string;
  readonly open_invoice_count: number;
  readonly outstanding_amt: string;
}

interface RequestRow {
  readonly request_id: number;
  readonly kind_code: string;
  readonly status: string;
  readonly body_ar?: string;
  readonly decision_note_ar?: string;
  readonly created_at: string;
}

interface ActivityRow {
  readonly child_activity_id: number;
  readonly title_ar?: string;
  readonly instructions_ar?: string;
  readonly how_to_ar?: string;
  readonly times_per_week?: number;
  readonly minutes_each?: number;
  readonly end_date?: string;
  readonly done_today?: boolean;
  readonly last_done_at?: string;
}

interface TherapistRow {
  readonly therapist_id: number;
  readonly full_name_ar: string;
  readonly title_ar?: string;
  readonly status: string;
  readonly profile_status?: string;
  readonly bio_ar?: string;
  readonly practice_since_year?: number;
  readonly age_from_mon?: number;
  readonly age_to_mon?: number;
}

interface LanguageRow {
  readonly lang_code: string;
  readonly level_code?: string;
  readonly is_native?: boolean;
  readonly runs_sessions?: boolean;
}

interface CertificateRow {
  readonly certificate_id: number;
  readonly title_ar: string;
  readonly issuer_ar?: string;
  readonly year_awarded?: number;
  readonly has_image?: boolean;
  readonly attachment_id?: number | null;
}

interface QualificationRow {
  readonly qualification_id: number;
  readonly therapist_id: number;
  readonly year_awarded?: number;
  readonly title_ar: string;
  readonly issuer_ar?: string;
}

interface ServiceRow {
  readonly service_id: number;
  readonly name_ar: string;
}

interface StreamGrantRow {
  readonly playback_path: string;
  readonly expires_at: string;
}

/** The wire shape of domain.MeetingPass. `token` is absent, not empty, when the provider has none. */
interface MeetingPassRow {
  readonly provider: string;
  readonly domain: string;
  readonly room: string;
  readonly token?: string;
  readonly display_name: string;
  readonly moderator: boolean;
  readonly expires_at: string;
}

// =====================================================================
// Translation between the two vocabularies
// =====================================================================

/**
 * Years of practice, DERIVED from the year they began.
 *
 * Never a stored count: a number written down as "eleven years" is wrong on
 * the next anniversary and silently wrong every year after it.
 */
function yearsSince(year?: number): number | null {
  if (!year) {
    return null;
  }
  const years = new Date().getUTCFullYear() - year;
  return years >= 0 ? years : null;
}

/** The one array inside a wrapped list response. */
function firstArray(body: Record<string, unknown>): readonly unknown[] {
  for (const value of Object.values(body ?? {})) {
    if (Array.isArray(value)) {
      return value as readonly unknown[];
    }
  }
  return [];
}

const named = (value?: Named): string => value?.name_ar ?? value?.full_name_ar ?? '';

function toGuardian(me: MeResponse): Guardian {
  return { id: String(me.user.user_id), fullName: me.user.full_name_ar, phone: me.user.mobile ?? '' };
}

function toChild(
  row: ChildRow, next: AppointmentSummary | null, liveSessionId: string | null,
  scheduleUnavailable = false,
): Child {
  return {
    scheduleUnavailable,
    id: String(row.child_id),
    fullName: row.full_name_ar,
    childNo: row.child_no,
    birthDate: row.birth_date,
    // Only the two the schema records, and '' for everything else -
    // absent, null, or a value this build has not met. Guessing would
    // put a boy's picture on a girl's card, which is worse than the
    // neutral one this falls back to.
    gender: row.gender === 'M' || row.gender === 'F' ? row.gender : '',
    // The service does not list a child's services on the child row, and
    // deriving them from the plan would need a call per child on a screen
    // that already makes several. Left empty rather than half-filled.
    services: [],
    liveSessionId,
    nextAppointment: next,
    attendanceMonth: attendanceOf(row.attendance_month),
  };
}

/**
 * The two counts, or null when they are not two whole non-negative numbers.
 *
 * Checked rather than trusted: a service older than 0139 sends nothing, and
 * a malformed value turned into 0 would print "0 of 0" - a statement about
 * the child - where the truth is that nothing was counted.
 */
function attendanceOf(
  value: ChildRow['attendance_month'],
): Child['attendanceMonth'] {
  const whole = (n: unknown): n is number =>
    typeof n === 'number' && Number.isInteger(n) && n >= 0;
  return value && whole(value.attended) && whole(value.missed)
    ? { attended: value.attended, missed: value.missed }
    : null;
}

/** Arrival does not mean a clinical session has started. Preserve both states. */
function toAppointment(row: AppointmentRow): AppointmentSummary {
  const status = row.status as AppointmentStatus;
  return {
    id: String(row.appointment_id),
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    serviceName: named(row.service),
    therapistId: row.therapist?.therapist_id ? String(row.therapist.therapist_id) : null,
    therapistName: named(row.therapist),
    roomName: named(row.room),
    deliveryMode: row.delivery_mode === 'ONLINE' ? 'ONLINE' : 'IN_PERSON',
    status,
  };
}

/** Future first, soonest first. The service returns newest first. */
/**
 * The last session that actually took place.
 *
 * COMPLETED only. An aborted session is not one a parent should be told
 * "happened", and one still in progress is the live card's business.
 */
function lastCompletedSession(rows: readonly SessionRow[]): LastSession | null {
  const done = rows
    .filter((row) => row.status === 'COMPLETED')
    .sort((a, b) => Date.parse(b.started_at) - Date.parse(a.started_at));
  const latest = done[0];
  if (!latest) {
    return null;
  }
  return {
    at: latest.started_at,
    therapistName: latest.therapist?.full_name_ar ?? '',
    serviceName: latest.service?.name_ar ?? '',
  };
}

/**
 * The first activity not yet marked done today.
 *
 * The order is the service's, which is the order the therapist set. Picking
 * "the first one left" rather than inventing a priority keeps the home screen
 * and the home-programme screen agreeing about which activity is next.
 */
function firstOpenActivity(rows: readonly ActivityRow[]): HomeActivity | null {
  const row = rows.find((entry) => !entry.done_today);
  if (!row) {
    return null;
  }
  return {
    id: String(row.child_activity_id),
    title: row.title_ar ?? '',
    instructions: row.instructions_ar ?? '',
    howTo: row.how_to_ar ?? '',
    timesPerWeek: row.times_per_week ?? 0,
    minutesEach: row.minutes_each ?? 0,
    dueOn: row.end_date ?? '',
    completedAt: row.last_done_at ?? null,
  };
}

function upcomingOnly(rows: readonly AppointmentRow[]): readonly AppointmentSummary[] {
  const now = Date.now();
  return rows
    .filter((row) => Date.parse(row.starts_at) >= now
      && !['CANCELLED', 'NO_SHOW', 'COMPLETED'].includes(row.status))
    .sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at))
    .map(toAppointment);
}

function nextAppointment(rows: readonly AppointmentRow[]): AppointmentSummary | null {
  return upcomingOnly(rows)[0] ?? null;
}

function liveSessionIdOf(rows: readonly SessionRow[]): string | null {
  const live = rows.find((row) => row.status === 'IN_PROGRESS');
  return live ? String(live.session_id) : null;
}

function liveSessionFrom(rows: readonly SessionRow[], child: ChildRow): LiveSession | null {
  const live = rows.find((row) => row.status === 'IN_PROGRESS');
  if (!live) {
    return null;
  }
  return {
    sessionId: String(live.session_id),
    childName: child.full_name_ar,
    serviceName: named(live.service),
    therapistName: named(live.therapist),
    roomName: named(live.room),
    startedAt: live.started_at,
  };
}

/**
 * A report the family can see is a published one, and the service only ever
 * sends those to a guardian - the visibility ladder is in the policy, not
 * here. `kind` and `unread` have no counterpart at all: every report from
 * this endpoint is a progress report, and nothing records what was read.
 */
/**
 * A published session note, shaped like a report so one list renders both.
 *
 * A note carries no title of its own, so the body is the title - that is the
 * whole of a note, and inventing a heading for it would put words in a
 * clinician's mouth. approved_at is when the family could first read it, which
 * is the date that matters to them, not when it was drafted.
 */
function toNote(row: NoteRow): ReportSummary {
  return {
    id: String(row.note_id),
    kind: 'SESSION_NOTE',
    title: row.body_ar,
    authorName: row.author_ar ?? '',
    publishedAt: row.approved_at ?? row.created_at ?? '',
    unread: false,
  };
}

function toReport(row: ReportRow): ReportSummary {
  return {
    id: String(row.report_id),
    kind: 'PROGRESS',
    title: reportDisplayTitle(row.title_ar, row.report_id),
    authorName: row.published_by?.full_name_ar ?? '',
    publishedAt: row.published_at ?? '',
    unread: false,
  };
}

/**
 * The service has five invoice statuses and the portal's model has four.
 *
 * DRAFT never reaches a guardian - the policy withholds it - so it is not
 * mapped. The rest line up, and CANCELLED is the portal's VOID.
 */
function toInvoice(row: InvoiceRow): Invoice {
  const status: InvoiceStatus =
    row.status === 'PAID' ? 'PAID'
      : row.status === 'PARTIALLY_PAID' ? 'PARTIAL'
        : row.status === 'CANCELLED' ? 'VOID' : 'DUE';
  return {
    id: String(row.invoice_id),
    number: row.invoice_no,
    issuedAt: row.issue_date,
    // A decimal string on the wire, a number for display only. It is never
    // summed here - the service's own balance is what the screen totals.
    amount: Number(row.total_amt),
    paidAmount: Number(row.paid_amt ?? 0),
    currency: row.currency_code,
    description: '',
    status,
  };
}

function toPackage(row: PackageRow): ServicePackage {
  return {
    id: String(row.child_package_id),
    title: row.name_ar,
    used: row.sessions_used,
    total: row.sessions_total,
    expiresAt: row.expires_on ?? '',
  };
}

/**
 * The service has three request states and the portal's model has four.
 * UNDER_REVIEW has no counterpart: nothing in the schema records that
 * somebody started looking. NEW maps to SUBMITTED, which is what is true.
 */
function toRequest(row: RequestRow): ParentRequest {
  const status: RequestStatus =
    row.status === 'ACCEPTED' ? 'ACCEPTED'
      : row.status === 'REJECTED' ? 'DECLINED' : 'SUBMITTED';
  return {
    id: String(row.request_id),
    kind: row.kind_code as ParentRequest['kind'],
    subject: row.body_ar ?? '',
    outcome: row.decision_note_ar ?? null,
    submittedAt: row.created_at,
    status,
  };
}

/**
 * Something waiting for this family, built only from things actually counted.
 *
 * Never padded to fill the panel: a line here tells a parent to go and do
 * something, and an invented one sends them looking for what is not there.
 */
/**
 * "What needs your attention" is built ONLY from what actually arrived.
 *
 * A failed balance produces no line, and that is right: this list says
 * "there is something to do", and a request that did not answer is not
 * evidence that there is - nor evidence that there is not. Inventing a
 * zero-money line would be worse than silence, and so would inventing a
 * reassuring absence. The card that owns the number says it is missing;
 * this list stays quiet about it.
 */
function attentionFrom(parts: readonly {
  child: ChildRow;
  balance: Result<BalanceRow>;
  activities: Result<readonly ActivityRow[]>;
}[]): readonly AttentionItem[] {
  const items: AttentionItem[] = [];
  for (const part of parts) {
    if (part.balance.state === 'ok' && Number(part.balance.data.outstanding_amt) > 0) {
      items.push({
        kind: 'INVOICE',
        childId: String(part.child.child_id),
        titleKey: 'attention.invoice',
        amount: Number(part.balance.data.outstanding_amt),
        currency: part.balance.data.currency_code,
        count: null,
        childName: part.child.full_name_ar,
      });
    }
    const open = part.activities.state === 'ok'
      ? part.activities.data.filter((row) => !row.done_today).length : 0;
    if (open > 0) {
      items.push({
        kind: 'ACTIVITY',
        childId: String(part.child.child_id),
        titleKey: 'attention.activities',
        amount: null,
        currency: null,
        count: open,
        childName: part.child.full_name_ar,
      });
    }
  }
  return items;
}

/** The centre's week, for the home-programme heading. */
function startOfWeek(now = new Date()): string {
  const date = new Date(now);
  date.setUTCDate(date.getUTCDate() - date.getUTCDay());
  return date.toISOString();
}

function endOfWeek(now = new Date()): string {
  const date = new Date(now);
  date.setUTCDate(date.getUTCDate() + (6 - date.getUTCDay()));
  return date.toISOString();
}

// =====================================================================
// THE NOTIFICATION FEED
// =====================================================================

interface NotificationRow {
  readonly notification_id: number;
  readonly kind_code: string;
  readonly title_ar: string;
  readonly body_ar: string | null;
  readonly child_id: number | null;
  readonly child_name: string | null;
  readonly link_kind: string | null;
  readonly link_id: number | null;
  readonly created_at: string;
  readonly read_at: string | null;
}

interface NotificationFeedResponse {
  readonly rows?: readonly NotificationRow[];
  readonly unread?: number;
  readonly total?: number;
}

/**
 * WHERE A NOTIFICATION LEADS IS DECIDED HERE, NOT IN THE DATABASE.
 *
 * The schema stores WHAT the notification is about - an entity kind and an
 * id - and nothing about this application's routes. That is deliberate and
 * CLAUDE.md is explicit about the cost of the alternative: a URL written into
 * a row is a capability that keeps working wherever it is forwarded, and no
 * policy in that schema reaches it there. It would also mean the parent
 * portal's routing table lived in two places, one of which needs a migration
 * to change.
 *
 * A kind with no useful destination gets NULL rather than a guess. An item
 * that navigates somewhere unrelated is worse than one that does not
 * navigate: the parent has lost their place and learned nothing.
 */
function notificationTarget(row: NotificationRow): readonly string[] | null {
  switch (row.link_kind) {
    case 'CHAT': return ['/requests'];
    case 'REPORT':
      return row.link_id === null ? null : ['/reports', String(row.link_id)];
    case 'APPOINTMENT':
      return ['/schedule'];
    case 'INVOICE':
      return ['/billing'];
    case 'REQUEST':
      return ['/requests'];
    // Notes share the progress hub and require its notes tab.
    case 'NOTE':
      return ['/progress'];
    case 'CHILD':
      return ['/home'];
    default:
      return null;
  }
}

function toNotification(row: NotificationRow): PortalNotification {
  return {
    id: String(row.notification_id),
    kind: row.kind_code,
    title: row.title_ar,
    body: row.body_ar,
    childId: row.child_id === null ? null : String(row.child_id),
    childName: row.child_name,
    createdAt: row.created_at,
    read: row.read_at !== null,
    target: notificationTarget(row),
    targetQuery: row.link_kind==='CHAT' && row.link_id ? {tab:'messages',peer:String(row.link_id)} : row.link_kind === 'NOTE' ? { tab: 'notes' } : undefined,
  };
}

/** The site-contact row as the service returns it. */
interface ContactRow {
  readonly phone?: string | null;
  readonly landline?: string | null;
  readonly email?: string | null;
  readonly address_ar?: string | null;
  readonly map_url?: string | null;
  readonly hours_ar?: string | null;
  readonly weekend_ar?: string | null;
  readonly arrival_ar?: string | null;
}

/**
 * The row, as the screen needs it.
 *
 * WHATSAPP IS NOT MAPPED even though the column is right there. The
 * owner's list defers WhatsApp and SMS entirely, and a mapped field
 * invites a button - which would be the feature arriving through the
 * back door of a data mapping.
 */
function toCentreContact(row: ContactRow): CentreContact {
  return {
    phone: (row.phone ?? '').trim(),
    landline: (row.landline ?? '').trim(),
    email: (row.email ?? '').trim(),
    addressAr: (row.address_ar ?? '').trim(),
    mapUrl: (row.map_url ?? '').trim(),
    hoursAr: (row.hours_ar ?? '').trim(),
    weekendAr: (row.weekend_ar ?? '').trim(),
    arrivalAr: (row.arrival_ar ?? '').trim(),
  };
}
