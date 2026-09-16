/**
 * What the parent portal reads. These are read models over the secured views,
 * not the tables: the portal never sees a raw row, and every one of these
 * arrives already filtered to this guardian by the server's policies.
 *
 * Rules that show through the shapes below:
 *   - Every instant is a UTC ISO-8601 string. There is no local-time field.
 *   - One child per session. There is no participant list anywhere.
 *   - Live only, never recorded. There is no recording id, clip, or offset;
 *     a marked moment is a timestamped clinical note and nothing else.
 *   - Status is a closed set, because the server drives a state machine and
 *     the portal must not invent a value it could then display.
 */

export type Uuid = string;

/** UTC ISO-8601, e.g. "2026-09-02T13:30:00Z". Converted for display only. */
export type Utc = string;

// ---------------------------------------------------------------------------
// Guardian and children
// ---------------------------------------------------------------------------

export interface Guardian {
  readonly id: Uuid;
  readonly fullName: string;
  /** Already masked by the server where policy requires it. */
  readonly phone: string;
}

export interface Child {
  readonly id: Uuid;
  readonly fullName: string;
  /** The centre's own reference, as printed on the file: "CH-00021". */
  readonly childNo: string;
  /** Date of birth. The age is derived for display and never stored. */
  readonly birthDate: Utc;
  /**
   * 'M', 'F', or '' when the centre has not recorded it.
   *
   * Carried ONLY so the card can draw the right stand-in picture. It is
   * not shown as a word anywhere and must not be: a family reads their
   * own child's file, and printing a gender letter beside a name adds
   * nothing they do not know.
   *
   * The empty string is a real third case and not a missing value to be
   * defaulted away - many files are opened before anybody asks.
   */
  readonly gender: 'M' | 'F' | '';
  /** Service names in the child's plan, for the card's second line. */
  readonly services: readonly string[];
  /** Present only while a session of this child is running right now. */
  readonly liveSessionId: Uuid | null;
  readonly nextAppointment: AppointmentSummary | null;

  /**
   * The diary could not be read, so `nextAppointment` means NOTHING here.
   *
   * Without this the card had one way to say "null" and two things to mean
   * by it, and it chose the reassuring one: "لا توجد جلسة قادمة محجوزة" to a
   * family whose appointment simply failed to load. A parent who then does
   * not turn up was told so by this screen.
   */
  readonly scheduleUnavailable: boolean;

  /**
   * Sessions attended and missed since the 1st of this month, as the
   * SERVICE counted them - null when it sent nothing.
   *
   * Counts, not a percentage: the portal divides them for display and
   * decides nothing else. Which statuses count is hbh.child_attendance_month's
   * rule, and a copy of it here would be the one that drifts.
   *
   * Null and {0, 0} are different sentences. Null is "not told"; zero and
   * zero is "no session has happened yet this month" - and neither of them
   * is a percentage, which is why the card shows no ring for either.
   */
  readonly attendanceMonth: { readonly attended: number; readonly missed: number } | null;
}

export type ConsentKey = 'live_view' | 'sms_notifications' | 'activity_photos';

/**
 * One consent. `live_view` is PER CHILD, and that is not a detail.
 *
 * can_view_live_flg lives on the (guardian, child) link, so a family can be
 * permitted to watch one child and not another. This carried no child at
 * first, which forced the question "is it granted?" to be answered for the
 * whole family at once - and the safe-looking answer, "only if it holds for
 * every child", denies a family the child they WERE granted. Failing closed
 * in the wrong place is still failing.
 */
export interface Consent {
  readonly key: ConsentKey;
  readonly granted: boolean;
  /** The child it is about, when it is about one. Null for family-wide. */
  readonly childId: Uuid | null;
  readonly childName: string | null;
  /** When the guardian last changed it, for the audit trail the centre keeps. */
  readonly decidedAt: Utc | null;
}

// ---------------------------------------------------------------------------
// Appointments and sessions
// ---------------------------------------------------------------------------

export type AppointmentStatus =
  | 'BOOKED'
  | 'CHECKED_IN'
  | 'CONFIRMED'
  | 'IN_PROGRESS'
  | 'COMPLETED'
  | 'CANCELLED'
  | 'NO_SHOW';

/**
 * In the centre, or on a video call.
 *
 * It is a separate fact from the status, and the two are often confused: a
 * CONFIRMED appointment may be either, and an ONLINE one is not "a booking
 * without a room" - it is a booking whose room is a video call. The schema
 * binds them with a CHECK (ck_appointments_room_mode), so exactly one of
 * `roomName` and a consultation door is meaningful on any given row.
 */
export type DeliveryMode = 'IN_PERSON' | 'ONLINE';

export interface AppointmentSummary {
  readonly id: Uuid;
  readonly startsAt: Utc;
  readonly endsAt: Utc;
  readonly serviceName: string;
  /**
   * Carried alongside the name so the name can be a LINK.
   *
   * A parent looking at "who am I booked with" has nowhere to go from a
   * name, and the person is the thing they actually want to know about.
   */
  readonly therapistId: Uuid | null;
  readonly therapistName: string;
  /** Empty when `deliveryMode` is ONLINE - there is no room to name. */
  readonly roomName: string;
  readonly deliveryMode: DeliveryMode;
  readonly status: AppointmentStatus;
}

/**
 * A therapist as a FAMILY is allowed to see them.
 *
 * The mobile number is absent because the service withholds it: the same row
 * serves staff and guardians and the projection mask is the control, so a
 * guardian is sent `mobile: null` (migration 0031). This interface has no
 * field for it, so there is nowhere for one to arrive.
 *
 * What the static design asks for and the schema has no column for - a
 * biography, languages, qualifications, certificates, a photograph, years of
 * practice - is absent rather than blank. It is requested; see the screen.
 */
export interface TherapistLanguage {
  readonly code: string;
  /** Whether they can run a whole session in it - not merely read it. */
  readonly runsSessions: boolean;
  readonly isNative: boolean;
  readonly levelCode: string;
}

export interface TherapistQualification {
  readonly id: Uuid;
  readonly year: number | null;
  readonly title: string;
  readonly issuer: string;
}

export interface TherapistCertificate {
  readonly id: Uuid;
  readonly title: string;
  readonly issuer: string;
  readonly year: number | null;
  /**
   * Whether a scan exists AT ALL - true even when this reader may not open
   * it. The distinction is deliberate: "a certificate, no image shown" is
   * honest, while a family unable to tell "no scan" from "a scan not for
   * you" rings the centre asking for something they will not be given.
   */
  readonly hasImage: boolean;
  /** Set only when the image is published AND this reader may open it. */
  readonly attachmentId: Uuid | null;
}

export interface TherapistProfile {
  readonly id: Uuid;
  readonly fullName: string;
  /** "أخصائية تخاطب". The one line of description that always exists. */
  readonly title: string;
  readonly status: string;
  /** The services they actually practise, by name. */
  readonly services: readonly string[];

  /**
   * DRAFT until the therapist has consented and somebody published it.
   *
   * A family must see nothing of the profile before that: the whole reason
   * the state exists is that this page goes out to third parties about a
   * named person, with their recorded agreement.
   */
  readonly published: boolean;
  readonly bio: string;
  /**
   * DERIVED from the year they began practising, never stored. A stored
   * count of years is wrong on the first anniversary and silently wrong
   * every year after.
   */
  readonly yearsOfPractice: number | null;
  /** The age range they work with, in months as the schema stores it. */
  readonly ageFromMonths: number | null;
  readonly ageToMonths: number | null;

  readonly languages: readonly TherapistLanguage[];
  readonly qualifications: readonly TherapistQualification[];
  readonly certificates: readonly TherapistCertificate[];
}

// ---------------------------------------------------------------------------
// Progress
// ---------------------------------------------------------------------------

export interface Measurement {
  readonly takenAt: Utc;
  /** Percentage, 0..100, already scaled by the server. */
  readonly value: number;
}

export interface Goal {
  readonly id: Uuid;
  readonly title: string;

  /**
   * The latest MEASURED percentage, or null when nobody has measured yet.
   *
   * NULL IS THE POINT OF THIS FIELD. It used to fall back to the baseline -
   * `latest_pct ?? baseline_pct ?? 0` - and the screen drew the result as
   * progress. A parent whose child had never been assessed was shown "20%"
   * beside "0 measurements": the twenty was the starting point the therapist
   * recorded when the goal was written, presented as if it were an
   * achievement. The two numbers on screen contradicted each other, and the
   * one people read was the wrong one.
   */
  readonly currentPercent: number | null;

  /** Where this goal started, as the therapist recorded it. Never progress. */
  readonly baselinePercent: number | null;

  readonly targetPercent: number;
  readonly measurementCount: number;
  readonly lastMeasuredAt: Utc | null;

  /**
   * The series behind the chart, oldest first - and always empty today.
   *
   * There is no endpoint that returns the points: the plan read carries the
   * latest percentage and a count, nothing more. This is a gap in the
   * SERVICE, not in the data, and it is why the screen cannot show a change
   * against the previous assessment. It is left as a field rather than
   * removed because the chart is written against it and the day an endpoint
   * exists it fills in.
   */
  readonly series: readonly Measurement[];
}

export interface ProgressOverview {
  readonly planTitle: string;
  readonly goals: readonly Goal[];
  readonly latestReport: ReportSummary | null;
}

// ---------------------------------------------------------------------------
// Home programme
// ---------------------------------------------------------------------------

export interface HomeActivity {
  readonly id: Uuid;
  readonly title: string;

  /** What this therapist asked of THIS child, in their own words. */
  readonly instructions: string;

  /**
   * How the activity is done - the library's standing description, the same
   * for every child given it.
   *
   * The service has always sent this, and the screen has never shown it. A
   * parent was handed a title and a one-line instruction and left to work out
   * the rest, which is how a home programme quietly stops being done.
   */
  readonly howTo: string;

  /** Times a week and minutes each, as the therapist set them. Zero if unset. */
  readonly timesPerWeek: number;
  readonly minutesEach: number;

  readonly dueOn: Utc;
  readonly completedAt: Utc | null;
}

export interface HomeProgramme {
  readonly weekStart: Utc;
  readonly weekEnd: Utc;
  readonly completed: number;
  readonly total: number;
  readonly activities: readonly HomeActivity[];
}

// ---------------------------------------------------------------------------
// Reports and published notes
// ---------------------------------------------------------------------------

export type ReportKind = 'PROGRESS' | 'ASSESSMENT' | 'SESSION_NOTE';

export interface ReportSummary {
  readonly id: Uuid;
  readonly kind: ReportKind;
  readonly title: string;
  readonly authorName: string;
  readonly publishedAt: Utc;
  readonly unread: boolean;
}

/** One goal as it stood when the report was written. */
export interface ReportGoal {
  readonly title: string;
  /** Measured at the time, or null if it had never been measured. */
  readonly latestPercent: number | null;
  readonly baselinePercent: number | null;
  readonly targetPercent: number | null;
}

/**
 * A report, opened.
 *
 * The service has returned all of this from GET /reports/{id} the whole time.
 * The screen answered a tap with "opening a report file is not switched on
 * yet" - a sentence about a missing FEATURE, when what was missing was this
 * screen. Worse, it was said behind a green tick, so a parent was told an
 * absence had succeeded.
 *
 * There is no file and no attachment: a report here is a summary and the
 * state of each goal when it was written. Nothing is fetched to render it.
 */
export interface ReportDetail {
  readonly id: Uuid;
  readonly number: string;
  readonly title: string;
  readonly summary: string;
  readonly periodStart: string | null;
  readonly periodEnd: string | null;
  readonly publishedAt: Utc | null;
  readonly goals: readonly ReportGoal[];
}

// ---------------------------------------------------------------------------
// Billing
// ---------------------------------------------------------------------------

export type InvoiceStatus = 'DUE' | 'PAID' | 'PARTIAL' | 'VOID';

export interface Invoice {
  readonly id: Uuid;
  readonly number: string;
  readonly issuedAt: Utc;

  /** The invoice total. */
  readonly amount: number;

  /**
   * How much of it has been paid.
   *
   * The service has always sent this and the portal always dropped it, so a
   * 1,000 invoice marked "partly paid" showed one number and no sign of the
   * 400 already paid - while the summary above it said 600 outstanding. Two
   * true figures on one screen that appear to contradict each other are worse
   * than one: the parent has to do the arithmetic to find out they agree.
   */
  readonly paidAmount: number;

  readonly currency: string;
  readonly description: string;
  readonly status: InvoiceStatus;
}

export interface ServicePackage {
  readonly id: Uuid;
  readonly title: string;
  readonly used: number;
  readonly total: number;
  readonly expiresAt: Utc;
}

export interface BillingOverview {
  /**
   * NULL when any child's balance is missing. A total assembled from the
   * parts that happened to load would understate what a family owes, which
   * is the one wrong number on this screen with a cost attached.
   */
  readonly dueAmount: number | null;
  readonly currency: string;
  readonly packages: readonly ServicePackage[];
  readonly invoices: readonly Invoice[];

  /**
   * Three independent sections, three independent verdicts. An empty
   * `invoices` with `invoicesUnavailable === false` means the family really
   * has none; with `true` it means we could not find out.
   */
  readonly balanceUnavailable: boolean;
  readonly packagesUnavailable: boolean;
  readonly invoicesUnavailable: boolean;
}

// ---------------------------------------------------------------------------
// Requests to reception
// ---------------------------------------------------------------------------

export type RequestKind = 'RESCHEDULE' | 'CANCEL' | 'CALLBACK';
export type RequestStatus = 'SUBMITTED' | 'UNDER_REVIEW' | 'ACCEPTED' | 'DECLINED';

export interface ParentRequest {
  readonly id: Uuid;
  readonly kind: RequestKind;
  readonly subject: string;
  readonly outcome: string | null;
  readonly submittedAt: Utc;
  readonly status: RequestStatus;
}

export interface NewRequest {
  readonly childId: Uuid;
  readonly kind: RequestKind;
  readonly appointmentId: Uuid | null;
  readonly note: string;
}

// ---------------------------------------------------------------------------
// Live view
// ---------------------------------------------------------------------------

/**
 * What the portal is allowed to know about a running session. Note what is
 * absent: no camera URL, no address, no credential. The player is handed an
 * opaque ticket and the edge resolves it - a camera address must never reach
 * a client.
 */
export interface LiveSession {
  readonly sessionId: Uuid;
  readonly childName: string;
  readonly serviceName: string;
  readonly therapistName: string;
  readonly roomName: string;
  readonly startedAt: Utc;
}

/**
 * Permission to watch, and the address to watch at. NO TOKEN.
 *
 * This interface used to carry one, described as "opaque". It was still
 * wrong: the service never sends a token to a client at all. The credential
 * is set as an HttpOnly cookie scoped to the playback path, so the browser
 * attaches it and no script - including this one - can read it, and it never
 * appears in a URL where a proxy log or a browser history would keep it.
 *
 * A field for a token is an invitation to put one there. Removed.
 */
export interface StreamTicket {
  /** UTC. Short-lived by policy; the server, not the portal, enforces it. */
  readonly expiresAt: Utc;
  readonly playbackUrl: string;
}

/**
 * Permission to join a consultation - AND, unlike StreamTicket above, the
 * credential itself.
 *
 * Read the two interfaces together, because the difference between them is
 * the whole of this decision. Watching a session is one-way video the
 * service can stand in front of: it proxies the media and keeps the
 * credential in an HttpOnly cookie, so no script in this application can
 * read it. A consultation is two-way, and real-time media cannot be
 * proxied - the browser negotiates with the provider directly, so it has to
 * authenticate to the provider directly. There is no arrangement in which a
 * conference happens and the page holds nothing.
 *
 * What narrows it instead:
 *   - it expires in minutes, not hours, and there is no renewal. When it
 *     dies the page asks the door again and the door asks every one of its
 *     questions again.
 *   - it names a single room, a single person, and one role.
 *   - recording, livestreaming and transcription are switched OFF inside
 *     the signed token, so a host who finds the button cannot make one.
 *   - it never reaches localStorage, a URL of ours, or a log. It lives in
 *     one component's memory and dies with the screen.
 *
 * Migration 0120 records the decision and the owner who made it.
 */
export interface MeetingPass {
  /** Which company is carrying the call. The page loads its client. */
  readonly provider: string;
  /** The host the embedded client is loaded from. */
  readonly domain: string;
  /** The room AT THE PROVIDER, which is not the room's own secret. */
  readonly room: string;
  /** Empty for a provider that has none. Empty is NOT a refusal. */
  readonly token: string;
  /** The name the other side will see, so the family is not left guessing. */
  readonly displayName: string;
  /** Whether this pass runs the room. Decides what is drawn, never what is allowed. */
  readonly moderator: boolean;
  readonly expiresAt: Utc;
}

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------

/** The last session that actually happened. */
export interface LastSession {
  readonly at: Utc;
  readonly therapistName: string;
  readonly serviceName: string;
}

export interface HomeSummary {
  readonly child: Child;
  readonly nextAppointment: AppointmentSummary | null;
  readonly live: LiveSession | null;
  readonly upcoming: readonly AppointmentSummary[];

  /**
   * What has happened since, and what the therapist has said about it.
   *
   * Both are assembled from reads this screen already makes - the session
   * list and the report list - so neither costs a request. Neither is
   * invented: a child with no completed session and a therapist who has
   * published nothing produce two nulls and the section does not draw.
   *
   * The screen showed neither, and it is the thing a parent opens the portal
   * for. It knew the next appointment, the balance and a count of unread
   * reports; it could not say whether the last session had happened.
   */
  readonly lastSession: LastSession | null;
  readonly latestUpdate: ReportSummary | null;

  /** The first activity not yet marked done today, if any. */
  readonly todayActivity: HomeActivity | null;

  readonly openActivityCount: number;
  readonly unreadReportCount: number;

  /**
   * NULL means the balance could not be read - it does NOT mean zero.
   *
   * Typed nullable so the compiler makes every reader decide which it is.
   * The screen that showed "0 ج.م." to a family with an unpaid invoice did
   * so because the type could not tell the two apart.
   */
  readonly dueAmount: number | null;
  readonly currency: string;

  /** Per-section "this did not load", so each card degrades on its own. */
  readonly balanceUnavailable: boolean;
  readonly scheduleUnavailable: boolean;
  readonly activitiesUnavailable: boolean;
  readonly reportsUnavailable: boolean;
}

/** One line on the welcome screen: something waiting for the guardian. */
export type AttentionKind = 'INVOICE' | 'ACTIVITY' | 'REPORT' | 'REQUEST';

/**
 * One line on the welcome screen. Structured, not pre-worded.
 *
 * `title` used to be display text and `detail` a formatted string, which
 * forced whoever produced these to write Arabic and to format money - and the
 * HTTP implementation, which must do neither, produced "attention.invoice"
 * and "600.00 EGP" on screen: a raw key and an unformatted amount.
 *
 * So the item carries a KEY and the raw numbers, and the screen words and
 * formats them. Money in particular has one formatter in this app, and it is
 * not a template literal in an API adapter.
 */
export interface AttentionItem {
  readonly childId: Uuid | null;
  readonly kind: AttentionKind;
  readonly titleKey: string;
  /** Set for money. The currency travels with it and is never assumed. */
  readonly amount: number | null;
  readonly currency: string | null;
  /** Set when the line is about a number of things. */
  readonly count: number | null;
  readonly childName: string | null;
}

export interface WelcomeSummary {
  readonly guardian: Guardian;
  readonly children: readonly Child[];
  readonly attention: readonly AttentionItem[];
}

/**
 * One item in the notification feed.
 *
 * IT CARRIES NO CLINICAL TEXT, and that is decided upstream rather than here:
 * every notify_* function in the schema writes a title that says a thing
 * happened and a link that says where to look. The body, where there is one,
 * is an invoice number or a decision note - never a session note.
 *
 * `target` is worked out from `linkKind`/`linkId` in the API layer, so no
 * screen has to know the schema's vocabulary and no route is written into
 * the database. The database stores WHAT the notification is about; the
 * client decides where that lives in this app.
 */
export interface PortalNotification {
  readonly id: string;
  readonly kind: string;
  readonly title: string;
  readonly body: string | null;
  readonly childId: string | null;
  readonly childName: string | null;
  readonly createdAt: string;
  readonly read: boolean;
  /** Router path, or null when there is nothing useful to open. */
  readonly target: readonly string[] | null;
  readonly targetQuery?: Readonly<Record<string, string>>;
}

export interface NotificationFeed {
  readonly rows: readonly PortalNotification[];
  readonly unread: number;
  readonly total: number;
}

/**
 * The part of a guardian's own record they may change themselves.
 *
 * TWO FIELDS, and what is absent is the point. The mobile is the login -
 * the one-time code goes to it - so a parent who could change it from a
 * signed-in phone could move the account to another number, and so could
 * anyone holding an unlocked phone for half a minute. The name and the
 * national id are checked against a document at reception.
 *
 * Both are always sent and an empty one clears the field: "absent means
 * leave it" would give a parent a way to add an address and no way to
 * remove one.
 */
export interface GuardianContact {
  readonly email: string;
  readonly city: string;
}

/**
 * How a family reaches the centre.
 *
 * The same row the public website shows, and it is PUBLISHED - anonymous
 * visitors already read every field of it. Migration 0119 is what lets a
 * signed-in parent read it too; before that the portal had no phone
 * number at all and the "help" button raised a toast that said nothing.
 *
 * WHATSAPP IS DEFERRED and is deliberately absent from this interface,
 * even though the column exists. The owner's list defers WhatsApp and SMS
 * entirely; a field here would invite a button, and the button would be
 * the feature.
 */
export interface CentreContact {
  readonly phone: string;
  readonly landline: string;
  readonly email: string;
  readonly addressAr: string;
  /** Either a link or a "lat, lng" pair - the column holds both shapes. */
  readonly mapUrl: string;
  readonly hoursAr: string;
  readonly weekendAr: string;
  /** How to find the door: intercom, landmarks, which gate. */
  readonly arrivalAr: string;
}
