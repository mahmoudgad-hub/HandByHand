import { Observable } from 'rxjs';

import {
  BillingOverview,
  Consent,
  ConsentKey,
  Guardian,
  CentreContact,
  GuardianContact,
  HomeProgramme,
  HomeSummary,
  LiveSession,
  MeetingPass,
  NewRequest,
  ParentRequest,
  ProgressOverview,
  ReportSummary,
  ReportDetail,
  StreamTicket,
  TherapistProfile,
  Uuid,
  WelcomeSummary,
  AppointmentSummary,
  NotificationFeed,
} from '../models/portal.models';

/**
 * The whole surface the portal is allowed to touch. One abstract class, two
 * implementations: the HTTP one that talks to the Go service, and the fixture
 * one that stands in until the service exists. Screens depend on this and
 * never on either implementation, so the day the API lands nothing above this
 * line changes.
 *
 * A child id is passed as an argument, not carried in the URL of a screen.
 * The server re-checks the guardian's access to that child on every call:
 * the argument is a request, not a grant.
 */
export abstract class PortalApi {
  /** Welcome screen: who the guardian is, their children, what is waiting. */
  abstract welcome(): Observable<WelcomeSummary>;

  /**
   * The guardian and their children, and nothing about their day (#16).
   *
   * Two requests. For the callers that only need to know WHO: the child
   * guard resolving a remembered child after a reload, and the profile.
   * They used welcome(), which also fetches appointments, sessions, balance
   * and activities for every child - four requests per child, thrown away.
   * A child from here has no next appointment or live session loaded, and
   * says so (`scheduleUnavailable`).
   */
  abstract family(): Observable<Pick<WelcomeSummary, 'guardian' | 'children'>>;

  /** Home screen for one child. */
  abstract home(childId: Uuid): Observable<HomeSummary>;

  /** Schedule, both directions. Upcoming first, past on request. */
  abstract appointments(
    childId: Uuid,
    scope: 'upcoming' | 'past',
  ): Observable<readonly AppointmentSummary[]>;

  abstract progress(childId: Uuid): Observable<ProgressOverview>;

  abstract homeProgramme(childId: Uuid): Observable<HomeProgramme>;

  /**
   * Record that a home activity was done. The only write a parent makes about
   * clinical work, and it records their report, not a clinical judgement.
   */
  abstract setActivityDone(
    childId: Uuid,
    activityId: Uuid,
    done: boolean,
  ): Observable<void>;

  abstract reports(
    childId: Uuid,
    scope: 'reports' | 'notes',
  ): Observable<readonly ReportSummary[]>;

  /** One report, opened. The service has always answered this. */
  abstract report(reportId: Uuid): Observable<ReportDetail>;

  /**
   * The billing screen. `sections` names what to fetch - a retry under the
   * invoices fetches the invoices (#15). Sections not asked for come back as
   * placeholders and must not be read; the screen merges only what it asked.
   */
  abstract billing(
    sections?: ReadonlySet<'balance' | 'packages' | 'invoices'>,
  ): Observable<BillingOverview>;

  abstract requests(): Observable<readonly ParentRequest[]>;

  /**
   * Submit a request to reception. It does not move an appointment - reception
   * decides, and the appointment's own state machine is what moves it.
   */
  abstract submitRequest(request: NewRequest): Observable<ParentRequest>;

  abstract profile(): Observable<Guardian>;

  /**
   * One therapist, as a family may see them.
   *
   * The centre publishes very little about its staff today - a name, a
   * title, and the services they practise. That is still the answer to the
   * question a parent is actually asking: who am I booked with, and what do
   * they do.
   */
  abstract therapist(therapistId: Uuid): Observable<TherapistProfile>;

  abstract consents(): Observable<readonly Consent[]>;

  abstract setConsent(key: ConsentKey, granted: boolean): Observable<Consent>;

  /**
   * The two fields of their own record a parent may change.
   *
   * Not the mobile: it IS the login, and the one-time code goes to it. Not
   * the name or the national id: those are checked against a document at
   * reception. The service enforces all of that - this pair exists so the
   * screen stops showing four fields and offering none.
   */
  abstract contact(): Observable<GuardianContact>;

  abstract setContact(value: GuardianContact): Observable<GuardianContact>;

  /**
   * How to reach the centre: its number, address, hours and map.
   *
   * Null when the centre has not published a contact row yet - which is a
   * real state and not an error, and the screen says so rather than
   * drawing a call button that dials nothing.
   */
  abstract centreContact(): Observable<CentreContact | null>;

  /** The session running right now for this child, or null. */
  abstract liveSession(childId: Uuid): Observable<LiveSession | null>;

  /**
   * Ask for a viewing ticket. Every rule that matters lives behind this call:
   * the guardian's link to the child, the live consent, the session actually
   * being in progress, the short expiry, and the access being written to the
   * audit log. A refusal here is the control - the button is only paint.
   */
  abstract requestStreamTicket(sessionId: Uuid): Observable<StreamTicket>;

  /**
   * Flag a moment the parent found important. A timestamped clinical note
   * against the session - there is no recording for it to point into, and
   * there never will be.
   */
  abstract markMoment(sessionId: Uuid, note: string): Observable<void>;

  /**
   * Ask to be let into an online consultation.
   *
   * IT IS A WRITE, and the verb is not decoration. Every call mints a fresh
   * credential and records that it was minted, against this guardian, with
   * this address, at this minute. Nothing about it is cacheable and nothing
   * about it is safe to repeat on a whim - a screen that called this on
   * every change detection would be issuing passes into a child's
   * consultation for as long as the tab was open.
   *
   * Every rule lives behind it: is this appointment yours, is it a
   * consultation at all, has it been paid for, has the hour come, is the
   * room still open. The button is paint; this call is the door.
   */
  abstract enterConsultation(appointmentId: Uuid): Observable<MeetingPass>;

  /**
   * The notification feed: what the centre has told this family, newest
   * first.
   *
   * NO GUARDIAN ID IS PASSED AND NONE MUST BE. The policy on the table is
   * `user_id = current_user_id()`, so the service returns the caller's own
   * rows and nobody else's. An argument here would be a second copy of that
   * rule - and one an attacker could change.
   */
  abstract notifications(limit?: number, offset?: number): Observable<NotificationFeed>;

  /**
   * Mark one read. UI state only: nothing in the schema branches on it, and
   * nothing should - a report is published whether or not its notification
   * was opened.
   */
  abstract markNotificationRead(id: string): Observable<void>;
}
