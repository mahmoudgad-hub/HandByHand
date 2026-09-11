import { Observable } from 'rxjs';

import {
  BillingOverview,
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

  abstract billing(): Observable<BillingOverview>;

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
   * The notification feed: what the centre has told this family, newest
   * first.
   *
   * NO GUARDIAN ID IS PASSED AND NONE MUST BE. The policy on the table is
   * `user_id = current_user_id()`, so the service returns the caller's own
   * rows and nobody else's. An argument here would be a second copy of that
   * rule - and one an attacker could change.
   */
  abstract notifications(limit?: number): Observable<NotificationFeed>;

  /**
   * Mark one read. UI state only: nothing in the schema branches on it, and
   * nothing should - a report is published whether or not its notification
   * was opened.
   */
  abstract markNotificationRead(id: string): Observable<void>;
}
