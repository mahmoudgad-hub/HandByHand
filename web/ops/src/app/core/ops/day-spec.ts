import { Observable } from 'rxjs';

import { FormatService } from '@hbh/shared/format/format.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { IconName } from '@hbh/shared/icon/icon';
import { Row } from '../api/ops-api';
import { DayApi, DayResource } from './day-api';

/**
 * A description of one operational screen: what its rows say, what may be
 * done to a row, and which permission each of those needs.
 *
 * Written as descriptions rather than five components for the reason the
 * resource screen already proved: the day one of them learns to handle a
 * refusal properly would be the day the other four do not. What differs
 * between an appointment and an invoice is the columns and the verbs, and
 * that is exactly what is written here.
 */

/** What a column reader is given. Rows are the service's own shape. */
export interface DayContext {
  readonly format: FormatService;
  readonly i18n: I18nService;
}

export interface DayColumn {
  readonly key: string;
  readonly labelKey: string;
  readonly read: (row: Row, ctx: DayContext) => string;
  /** Clock times, money and identifiers read left to right on an Arabic page. */
  readonly ltr?: boolean;
}

export type ActionFieldKind =
  | 'select' | 'text' | 'textarea' | 'money' | 'datetime' | 'lookup'
  // A list of windows the service says it would accept, asked for once the
  // service and the therapist are chosen. Picking one fills starts_at,
  // ends_at and room_id; it holds no value of its own and is never sent.
  | 'slots'
  // Type to search, server-side, instead of a dropdown holding the whole
  // table. `lookup` still names the resource - the difference is WHERE the
  // filtering happens, and that a page of 200 is no longer the ceiling on
  // which rows can be chosen at all.
  | 'search'
  // ONE choice that answers two questions: the service AND the therapist,
  // from the list of combinations the centre can actually deliver. It
  // holds no value the service ever sees - picking one writes service_id
  // and therapist_id, which are what get sent.
  //
  // It is not only a click saved. The old pair of controls could express
  // a combination that does not exist, and the whole of
  // /services/{id}/therapists was added to stop them; a list of valid
  // pairs makes the invalid one unrepresentable rather than discouraged.
  | 'pair';

/** A CRUD list a dialog draws its choices from. */
export type LookupResource =
  | 'children' | 'therapists' | 'rooms' | 'services' | 'service-packages';

export interface ActionOption {
  readonly value: string;
  readonly labelKey: string;
}

export interface ActionField {
  readonly name: string;
  readonly labelKey: string;
  readonly kind: ActionFieldKind;
  readonly required?: boolean;
  readonly options?: readonly ActionOption[];
  /**
   * Options that depend on the row - the legal next states of THIS
   * appointment. A fixed list would offer moves the database refuses, and a
   * button that is refused every time teaches people to distrust the screen.
   */
  readonly optionsFor?: (row: Row) => readonly ActionOption[];
  /**
   * NOTHING IS CHOSEN YET, said out loud.
   *
   * A select with this starts empty and draws this line as its first
   * option; without it the control opens on whichever row sorted first and
   * the form is already "answered" before anybody has read it.
   *
   * It exists because a select cannot simply be left empty: an empty one
   * still DISPLAYS its first option, so the screen would show a therapist's
   * name while holding nothing, and the service would answer REQUIRED about
   * a field the person can plainly see a value in. The placeholder is what
   * makes the empty state visible, so the model and the screen agree.
   *
   * Use it wherever picking the wrong row books, moves or charges something
   * real. Leave it off where the first option is a genuine default.
   */
  readonly placeholderKey?: string;
  /** Choices loaded from a CRUD list when the dialog opens. */
  readonly lookup?: LookupResource;
  /**
   * This lookup is NARROWED by the chosen service, and comes from
   * /services/{id}/therapists rather than from the full list.
   *
   * Named for the one relationship it describes instead of a general
   * "depends on this other field". A generic hook would read as though any
   * pair of fields could be wired up, and each pair needs an endpoint that
   * answers it - there is exactly one today.
   */
  readonly narrowedByService?: boolean;
  /** Shown only while another field in the same form holds one of these. */
  readonly onlyWhen?: { readonly field: string; readonly isOneOf: readonly string[] };
  /**
   * The heading this field sits under. Fields carrying the same key are
   * drawn as one group, in the order the spec lists them.
   *
   * Absent on every other action on purpose: a status change with two
   * fields does not need chapter headings, and adding them everywhere to
   * be consistent would make the small dialogs worse to make one better.
   */
  readonly section?: string;
  /**
   * Names that must hold a value before this field can be used.
   *
   * It DISABLES, it does not hide. A therapist picker that vanishes until
   * a service is chosen leaves a gap where somebody is looking for it and
   * cannot tell whether the screen is broken; one that is visibly greyed
   * with a reason teaches the order in a single glance.
   */
  readonly needs?: readonly string[];
  /**
   * Kept out of the main flow, behind a disclosure.
   *
   * For the fields that are legal and rare. Typing an exact instant is
   * still a valid booking - hbh.validate_slot accepts any window that
   * passes the rules, not only the ones the slot list offers - so the
   * control stays. It just stops being the first thing reception sees.
   */
  readonly secondary?: boolean;
  readonly ltr?: boolean;
  readonly hintKey?: string;
}

export interface DayAction {
  readonly key: string;
  readonly labelKey: string;
  readonly icon: IconName;
  readonly primary?: boolean;
  /** The server permission. The screen draws by it; the server enforces it. */
  readonly permission: string;
  /** Whether this row is in a state where the action means anything. */
  readonly when: (row: Row) => boolean;
  /** Collected before the call. No fields means a plain confirmation. */
  readonly fields?: readonly ActionField[];
  /** A sentence inside the dialog, when the consequence is not obvious. */
  readonly noteKey?: string;
  /**
   * A row action that GOES somewhere instead of doing something.
   *
   * When set, the action is drawn as a link and `run` is never called. It is
   * a separate field rather than a `run` that navigates, so that a reader can
   * tell at a glance which of these buttons change data and which only move
   * the screen - and so a navigation can never open the confirmation dialog.
   */
  readonly link?: (row: Row) => readonly (string | number)[];
  readonly run: (
    api: DayApi, row: Row, values: Record<string, string>, ctx: DayContext,
  ) => Observable<unknown>;
  readonly doneKey: string;
}

/** The create action, which belongs to the screen rather than to a row. */
export interface CreateAction extends Omit<DayAction, 'when' | 'run'> {
  readonly run: (
    api: DayApi, values: Record<string, string>, ctx: DayContext,
  ) => Observable<unknown>;
  /**
   * Show a read-back of everything chosen, immediately above the confirm.
   *
   * The booking form asks for six things and the sixth is a time; by then
   * the first is off the top of the dialog. A summary is how a receptionist
   * catches the wrong child before the family is told a wrong hour - which
   * is the one mistake on this screen that reaches a person outside it.
   */
  readonly reviewKey?: string;
  /**
   * Asks the service whether this would be accepted, without booking. The
   * answer is a 200 with ok:false when refused - a question answered, not a
   * failure - and it is what lets a receptionist learn the therapist is busy
   * WHILE choosing rather than after filling the whole form.
   */
  readonly check?: (
    api: DayApi, values: Record<string, string>, ctx: DayContext,
  ) => Observable<{ ok: boolean; reason: string }>;
}

export interface DaySpec {
  readonly resource: DayResource;
  readonly titleKey: string;
  readonly subKey: string;
  readonly idColumn: string;
  /**
   * How the window filter reads. A diary opens on a day; a ledger takes a
   * range of days; a queue takes no window at all, because the row that has
   * been waiting longest is the one that must not fall out of view.
   */
  readonly window: 'diary' | 'ledger' | 'queue';
  /** Whether the list offers an archived toggle. */
  readonly archivable?: boolean;
  readonly statusPrefix: string;
  readonly statusFilter: readonly string[];
  readonly kindPrefix?: string;
  readonly kindFilter?: readonly string[];
  readonly columns: readonly DayColumn[];
  readonly actions: readonly DayAction[];
  /**
   * Actions that belong to the SCREEN rather than to a row.
   *
   * A list, because billing has two of them - start an invoice, and sell a
   * package - and neither is about any particular row. Putting the second one
   * on a row would have shown it on every line and, worse, hidden it entirely
   * on a centre that has no invoices yet, which is exactly the centre that
   * needs to sell its first package.
   */
  readonly create?: readonly CreateAction[];
  readonly emptyKey: string;
  readonly emptyNoteKey: string;
  /** Which badge colour a status earns. */
  readonly tone: (status: string) => string;
}

// =====================================================================
// The state machines, copied from the schema and nowhere else
// =====================================================================

/**
 * hbh.legal_appointment_transition, verbatim (0005_scheduling.up.sql:422).
 *
 * It is here so a screen offers only the moves the database will accept. It
 * is NOT a rule being restated: the database refuses an illegal move with
 * 409 ILLEGAL_TRANSITION whatever this file says, and if the two ever
 * disagree the database is right. What this buys is a dropdown with three
 * real choices instead of six, two of which would always be refused.
 */
const APPOINTMENT_NEXT: Readonly<Record<string, readonly string[]>> = {
  BOOKED: ['CONFIRMED', 'CANCELLED', 'NO_SHOW'],
  CONFIRMED: ['CHECKED_IN', 'CANCELLED', 'NO_SHOW'],
  CHECKED_IN: ['COMPLETED', 'CANCELLED'],
  COMPLETED: [],
  CANCELLED: [],
  NO_SHOW: [],
};

/** hbh.legal_session_transition (0005_scheduling.up.sql:436). */
const SESSION_NEXT: Readonly<Record<string, readonly string[]>> = {
  IN_PROGRESS: ['COMPLETED', 'ABORTED'],
  COMPLETED: [],
  ABORTED: [],
};

/**
 * hbh.legal_enrolment_transition (0018), MINUS one.
 *
 * ENROLLED is legal in the schema and is deliberately absent here, because
 * PATCH cannot reach it: `ck_enr_converted` ties that status to the converted
 * guardian and child, and only hbh.convert_enrolment writes all three
 * together. Offering it in the dropdown would be a choice refused with 409
 * every time - checked against the running service, not assumed.
 *
 * Enrolling is therefore its own button, and it is refused from NEW: somebody
 * has to have spoken to the family before their child enters the record.
 */
const ENROLMENT_NEXT: Readonly<Record<string, readonly string[]>> = {
  NEW: ['CONTACTED', 'REJECTED', 'DUPLICATE'],
  CONTACTED: ['ASSESSMENT_BOOKED', 'REJECTED', 'DUPLICATE'],
  ASSESSMENT_BOOKED: ['REJECTED'],
  ENROLLED: [],
  REJECTED: [],
  DUPLICATE: [],
};

// =====================================================================
// Reading a row
// =====================================================================

const text = (row: Row, key: string): string => {
  const value = row[key];
  return value === null || value === undefined ? '' : String(value);
};

/** A nested reference - `child.full_name_ar` - or an empty string. */
const ref = (row: Row, group: string, key: string): string => {
  const nested = row[group] as Record<string, unknown> | undefined | null;
  const value = nested?.[key];
  return value === null || value === undefined ? '' : String(value);
};

/** "10:00 - 10:45" on one line, read left to right. */
/**
 * Directional isolates, named because they are invisible in the source.
 *
 * FSI (U+2068) opens a run whose direction is taken from its first strong
 * character; PDI (U+2069) closes it. Anything between them is laid out as one
 * unit and cannot reorder against what surrounds it.
 */
const FSI = '⁨';
const PDI = '⁩';

/**
 * "١١:٠٠ ص – ١١:٤٥ ص", and it stays in that order.
 *
 * IT DID NOT. The cell is `direction: ltr` (the column is `ltr: true`) and
 * each time mixes Latin digits with an Arabic ص/م. With nothing separating
 * them the bidi algorithm treats the whole string as one run and reorders it,
 * so the screen showed:
 *
 *	11:00 ص 11:45 – ص
 *
 * and when the cell wrapped, the two halves split across lines with the
 * meridiems on the wrong ones. Measured by glyph position, not guessed.
 *
 * ISOLATING EACH TIME IS THE FIX, not flipping the cell. The column is
 * left-to-right on purpose - a clock reads that way in both languages - and
 * turning it round would reorder the dash instead. What was missing is that
 * "11:00 ص" is ONE thing, and the isolates say so.
 */
const clockRange = (row: Row, ctx: DayContext): string => {
  const from = text(row, 'starts_at');
  const to = text(row, 'ends_at');
  if (!from) {
    return '';
  }
  const one = (at: string): string => `${FSI}${ctx.format.time(at)}${PDI}`;
  return to ? `${one(from)} – ${one(to)}` : one(from);
};

const nextOptions = (
  table: Readonly<Record<string, readonly string[]>>, prefix: string,
) => (row: Row): readonly ActionOption[] =>
  (table[text(row, 'status')] ?? []).map((value) => ({
    value, labelKey: `${prefix}${value}`,
  }));

const idOf = (row: Row, column: string): number => Number(row[column]);

// =====================================================================
// Shared field definitions
// =====================================================================

const REASON_FIELD: ActionField = {
  name: 'reason', labelKey: 'field.reason', kind: 'text',
  // Required only where it is: a cancellation without a reason is a row
  // nobody can explain later, and the family will ask.
  onlyWhen: { field: 'status', isOneOf: ['CANCELLED', 'NO_SHOW', 'ABORTED'] },
};

// =====================================================================
// APPOINTMENTS
// =====================================================================

export const APPOINTMENTS_SPEC: DaySpec = {
  resource: 'appointments',
  titleKey: 'nav.appointments',
  subKey: 'appointments.sub',
  idColumn: 'appointment_id',
  window: 'diary',
  statusPrefix: 'status.appointment.',
  statusFilter: ['BOOKED', 'CONFIRMED', 'CHECKED_IN', 'COMPLETED', 'CANCELLED', 'NO_SHOW'],
  emptyKey: 'appointments.empty',
  emptyNoteKey: 'appointments.emptyNote',
  tone: (status) => {
    if (status === 'CANCELLED' || status === 'NO_SHOW') {
      return 'hbh-badge--muted';
    }
    if (status === 'COMPLETED') {
      return 'hbh-badge--success';
    }
    return status === 'CHECKED_IN' ? 'hbh-badge--progress' : 'hbh-badge--info';
  },
  columns: [
    { key: 'time', labelKey: 'field.time', read: clockRange, ltr: true },
    { key: 'child', labelKey: 'field.child', read: (row) => ref(row, 'child', 'full_name_ar') },
    { key: 'childNo', labelKey: 'field.childNo', read: (row) => ref(row, 'child', 'child_no'), ltr: true },
    { key: 'service', labelKey: 'field.service', read: (row) => ref(row, 'service', 'name_ar') },
    { key: 'therapist', labelKey: 'field.therapist', read: (row) => ref(row, 'therapist', 'full_name_ar') },
    { key: 'room', labelKey: 'field.room', read: (row) => ref(row, 'room', 'name_ar') },
  ],
  create: [{
    key: 'book',
    labelKey: 'appointments.book',
    icon: 'ic-cal-plus',
    primary: true,
    permission: 'APPOINTMENT.BOOK',
    noteKey: 'appointments.bookNote',
    fields: [
      /*
       * TYPE THE CHILD'S NAME, do not scroll to them.
       *
       * This was a <select> filled with ONE PAGE of children - `limit: 200`
       * - and the two things wrong with it get worse in opposite
       * directions. On a small centre it is merely long. On a centre with
       * nine hundred children, the seven hundred past that page ARE NOT
       * BOOKABLE AT ALL, and nothing on screen says so: a dropdown looks
       * complete whether or not it is.
       *
       * The search is the service's (`?q=`, over full_name_ar and
       * child_no), so the ceiling moves from "the first page" to "every
       * child the policy lets this person see".
       *
       * AND NOTHING IS PRESELECTED ANY MORE. The old select opened on
       * whichever child sorted first, so a mis-click on save booked a real
       * appointment for a family nobody had chosen. An empty box refuses
       * until somebody names the child.
       */
      {
        name: 'child_id', labelKey: 'field.child', kind: 'search',
        lookup: 'children', required: true, hintKey: 'field.childSearchHint',
        section: 'appointments.sec.child',
      },
      /*
       * AND THE SAME RULE AS THE CHILD ABOVE, for the same reason.
       *
       * That box was emptied because "a mis-click on save booked a real
       * appointment for a family nobody had chosen". These three were left
       * on their first option, so the mis-click survived in a quieter form:
       * the right child, at a real hour, with a service, a therapist and a
       * room that nobody picked - whichever row happened to sort first.
       * That books a clinician into an hour they never agreed to, and
       * afterwards it is indistinguishable from a deliberate booking.
       *
       * validate_slot still checks the combination; it was never the thing
       * at issue. What it cannot know is that nobody meant to choose this.
       */
      /*
       * THE SERVICE AND THE THERAPIST, ASKED ONCE.
       *
       * Two controls became one because the two answers are not
       * independent: only certain pairs exist. Asking separately meant a
       * second question whose answer could contradict the first, and
       * /services/{id}/therapists exists because it did. A list of the
       * pairs the centre can deliver ends that - an impossible
       * combination is not discouraged here, it cannot be expressed.
       *
       * IT SENDS NOTHING. Picking one writes service_id and therapist_id,
       * the two fields below, which are what reach the service. They stay
       * in the form - behind the disclosure - so somebody who needs to
       * change one alone still can, and so the read-back can name both.
       */
      {
        name: 'service_therapist', labelKey: 'field.serviceTherapist', kind: 'pair',
        required: true, section: 'appointments.sec.care',
        hintKey: 'appointments.pairHint',
      },
      {
        name: 'service_id', labelKey: 'field.service', kind: 'lookup',
        lookup: 'services', required: true, section: 'appointments.sec.care',
        placeholderKey: 'field.chooseService', secondary: true,
      },
      /*
       * ONLY THE THERAPISTS WHO OFFER THE CHOSEN SERVICE.
       *
       * The list used to be everybody, and hbh.validate_slot answered
       * THERAPIST_SERVICE_MISMATCH afterwards - a refusal about a fact the
       * service knew before the choice was made. The service still answers
       * it; nothing here is a substitute for that check. What changed is
       * that the wrong answer is no longer offered.
       */
      {
        name: 'therapist_id', labelKey: 'field.therapist', kind: 'lookup',
        lookup: 'therapists', narrowedByService: true, required: true,
        section: 'appointments.sec.care', needs: ['service_id'], secondary: true,
        placeholderKey: 'field.chooseTherapist',
      },
      /*
       * THE FREE WINDOWS, and the room comes WITH them.
       *
       * room_id is NOT NULL on hbh.appointments, so every booking needs
       * one - but reception should not be choosing it from a list of every
       * room and discovering at check time that it was occupied. Each slot
       * carries a room the service has just confirmed is free for exactly
       * that window, so picking a time picks the room.
       *
       * The picker is `needs` the service and the therapist: asking for
       * free windows before either is chosen is asking "when is nobody
       * free", and the honest answer - nothing - reads as a full day.
       */
      {
        name: 'slot', labelKey: 'appointments.freeSlots', kind: 'slots',
        section: 'appointments.sec.when', needs: ['service_id', 'therapist_id'],
      },
      /*
       * THE THREE FIELDS A SLOT FILLS IN, kept and demoted.
       *
       * They are not vestigial. The slot list is drawn at the centre's
       * granularity, and a window between two of its offers is still a
       * legal booking that hbh.validate_slot accepts - so removing these
       * would narrow what the centre may book in order to tidy a screen.
       * A therapist who agrees to stay twenty minutes late is a real
       * booking, and it must not need a developer.
       *
       * What changed is which path is the ordinary one. They sit behind a
       * disclosure, and in the common booking nobody opens it.
       */
      {
        name: 'starts_at', labelKey: 'field.startsAt', kind: 'datetime', required: true,
        hintKey: 'appointments.timeHint',
        section: 'appointments.sec.when', secondary: true,
      },
      {
        name: 'ends_at', labelKey: 'field.endsAt', kind: 'datetime', required: true,
        section: 'appointments.sec.when', secondary: true,
        hintKey: 'appointments.endHint',
      },
      {
        name: 'room_id', labelKey: 'field.room', kind: 'lookup', lookup: 'rooms',
        required: true, section: 'appointments.sec.where', secondary: true,
        hintKey: 'appointments.roomHint',
        // Picking a slot still fills this, and that is the ordinary path.
        // The placeholder only covers the other one - a booking typed by
        // hand, where an unpicked room would otherwise arrive as whichever
        // room sorts first and send a family to the wrong door.
        placeholderKey: 'field.chooseRoom',
      },
      { name: 'note_ar', labelKey: 'field.note', kind: 'textarea',
        section: 'appointments.sec.note' },
    ],
    reviewKey: 'appointments.review',
    check: (api, values, ctx) => api.validateSlot(bookingBody(values, ctx)),
    run: (api, values, ctx) => api.book(bookingBody(values, ctx)),
    doneKey: 'appointments.booked',
  }],
  actions: [
    {
      key: 'status',
      labelKey: 'appointments.changeStatus',
      icon: 'ic-check-circle',
      // Cancelling needs APPOINTMENT.CANCEL and every other move needs
      // APPOINTMENT.BOOK (0016_operational_writes.up.sql:68). The dropdown is
      // drawn for whoever holds the broader of the two, and the server keeps
      // the distinction - it refuses a cancel from someone who may only book.
      permission: 'APPOINTMENT.BOOK',
      when: (row) => (APPOINTMENT_NEXT[text(row, 'status')] ?? []).length > 0,
      fields: [
        {
          name: 'status', labelKey: 'field.newStatus', kind: 'select', required: true,
          optionsFor: nextOptions(APPOINTMENT_NEXT, 'status.appointment.'),
          // A move through the state machine, so the same rule as the
          // booking fields and with more reason: the legal next states of a
          // BOOKED appointment begin with CONFIRMED and include CANCELLED,
          // and opening on the first of them meant the dialog was already
          // proposing a move before anybody read it. The history table
          // records whatever is confirmed here, under the name of whoever
          // pressed it.
          placeholderKey: 'field.chooseStatus',
        },
        REASON_FIELD,
      ],
      run: (api, row, values) => api.setAppointmentStatus(
        idOf(row, 'appointment_id'), values['status'], values['reason'] ?? ''),
      doneKey: 'appointments.statusChanged',
    },
    {
      key: 'start',
      labelKey: 'sessions.start',
      icon: 'ic-play',
      primary: true,
      permission: 'SESSION.START',
      // A session starts from CHECKED_IN and from nothing else - the schema
      // says so in words (0005_scheduling.up.sql:741). Offering it earlier
      // would produce NOT_CHECKED_IN every time.
      //
      // And once from that state, not twice. The appointment STAYS
      // CHECKED_IN while its session runs, so the status test alone left
      // the button on screen after a successful start - and pressing it
      // again could only ever return HB022 "لهذا الموعد جلسة بالفعل".
      // session_id comes from the centre-indexed read for exactly this.
      when: (row) => text(row, 'status') === 'CHECKED_IN' && row['session_id'] == null,
      noteKey: 'sessions.startNote',
      run: (api, row) => api.startSession(idOf(row, 'appointment_id')),
      doneKey: 'sessions.started',
    },
  ],
};

/** The booking body, with wall-clock times converted to UTC instants. */
function bookingBody(values: Record<string, string>, ctx: DayContext) {
  return {
    child_id: Number(values['child_id']),
    therapist_id: Number(values['therapist_id']),
    room_id: Number(values['room_id']),
    service_id: Number(values['service_id']),
    // The picker collects the centre's wall clock. Everything crosses the
    // wire as UTC.
    starts_at: ctx.format.toUtc(values['starts_at']),
    ends_at: ctx.format.toUtc(values['ends_at']),
    note_ar: values['note_ar'] ?? '',
  };
}

// =====================================================================
// SESSIONS
// =====================================================================

export const SESSIONS_SPEC: DaySpec = {
  resource: 'sessions',
  titleKey: 'nav.sessions',
  subKey: 'sessions.sub',
  idColumn: 'session_id',
  window: 'diary',
  statusPrefix: 'status.session.',
  statusFilter: ['IN_PROGRESS', 'COMPLETED', 'ABORTED'],
  emptyKey: 'sessions.empty',
  emptyNoteKey: 'sessions.emptyNote',
  tone: (status) => {
    if (status === 'IN_PROGRESS') {
      return 'hbh-badge--progress';
    }
    return status === 'COMPLETED' ? 'hbh-badge--success' : 'hbh-badge--muted';
  },
  columns: [
    {
      key: 'started', labelKey: 'field.startedAt', ltr: true,
      read: (row, ctx) => ctx.format.time(text(row, 'started_at')),
    },
    {
      key: 'ended', labelKey: 'field.endedAt', ltr: true,
      read: (row, ctx) => {
        const ended = text(row, 'ended_at');
        // A running session has no end time, and it says so with a dash.
        //
        // It showed an elapsed counter here at first, which was wrong twice:
        // a duration under a column headed "end" reads as a clock time, and
        // nothing on this screen re-renders on a timer, so the figure froze
        // at the second the page loaded and then lied. The status badge next
        // to it already says the session is running.
        return ended ? ctx.format.time(ended) : '—';
      },
    },
    { key: 'child', labelKey: 'field.child', read: (row) => ref(row, 'child', 'full_name_ar') },
    { key: 'service', labelKey: 'field.service', read: (row) => ref(row, 'service', 'name_ar') },
    { key: 'therapist', labelKey: 'field.therapist', read: (row) => ref(row, 'therapist', 'full_name_ar') },
    { key: 'room', labelKey: 'field.room', read: (row) => ref(row, 'room', 'name_ar') },
  ],
  actions: [
    {
      key: 'watch',
      labelKey: 'live.watch',
      icon: 'ic-video',
      permission: 'LIVE.VIEW',
      // Only while it is running. There is no recording, so a finished
      // session has nothing to watch - offering the button afterwards would
      // promise a replay this system deliberately does not have.
      when: (row) => text(row, 'status') === 'IN_PROGRESS',
      link: (row) => ['/sessions', idOf(row, 'session_id'), 'live'],
      run: () => {
        throw new Error('watch is a link; run is never called');
      },
      doneKey: '',
    },
    {
      key: 'note',
      labelKey: 'sessions.note',
      icon: 'ic-edit',
      // SESSION.NOTES.EDIT, and the seed gives it to THERAPIST alone -
      // withheld from CENTER_ADMIN on purpose, because a clinical note is
      // authored by the clinician who ran the session and by nobody else
      // (0006_plans_and_notes.up.sql:263). Gated on SESSION.START at first,
      // which drew the button for an administrator who was then refused
      // every single time. The gate does not grant anything: the function
      // also checks that this is the caller's own session.
      permission: 'SESSION.NOTES.EDIT',
      when: (row) => text(row, 'status') !== '',
      // Said before the box, not after. A therapist writing what they think
      // a parent will read, into a field the parent cannot see, is a
      // misunderstanding with clinical consequences.
      noteKey: 'sessions.noteInternal',
      fields: [
        { name: 'body_ar', labelKey: 'field.note', kind: 'textarea', required: true },
      ],
      run: (api, row, values) => api.writeNote(idOf(row, 'session_id'), values['body_ar']),
      doneKey: 'sessions.noteSaved',
    },
    {
      key: 'close',
      labelKey: 'sessions.close',
      icon: 'ic-check-circle',
      primary: true,
      permission: 'SESSION.COMPLETE',
      when: (row) => text(row, 'status') === 'IN_PROGRESS',
      fields: [
        {
          name: 'status', labelKey: 'field.outcome', kind: 'select', required: true,
          optionsFor: nextOptions(SESSION_NEXT, 'status.session.'),
          // The outcome of a session that happened, so it is asked for
          // rather than assumed. IN_PROGRESS offers COMPLETED and ABORTED,
          // and the dialog opened on COMPLETED - which is the answer most
          // of the time and exactly why it must not be the default. A
          // session that was cut short would be recorded as finished by
          // somebody agreeing with a box they never read, in the clinical
          // history, under their own name.
          placeholderKey: 'field.chooseOutcome',
        },
        REASON_FIELD,
      ],
      run: (api, row, values) => api.closeSession(
        idOf(row, 'session_id'), values['status'], values['reason'] ?? ''),
      doneKey: 'sessions.closed',
    },
  ],
};

// =====================================================================
// REPORTS
// =====================================================================

export const REPORTS_SPEC: DaySpec = {
  resource: 'reports',
  titleKey: 'nav.reports',
  subKey: 'reports.sub',
  idColumn: 'report_id',
  window: 'ledger',
  statusPrefix: 'status.report.',
  statusFilter: ['DRAFT', 'PUBLISHED'],
  emptyKey: 'reports.empty',
  emptyNoteKey: 'reports.emptyNote',
  tone: (status) => (status === 'PUBLISHED' ? 'hbh-badge--success' : 'hbh-badge--muted'),
  columns: [
    { key: 'no', labelKey: 'field.reportNo', read: (row) => text(row, 'report_no'), ltr: true },
    { key: 'title', labelKey: 'field.title', read: (row) => text(row, 'title_ar') },
    { key: 'child', labelKey: 'field.child', read: (row) => ref(row, 'child', 'full_name_ar') },
    {
      key: 'period', labelKey: 'field.period',
      // An open-ended period is a period, not a blank. See the same repair in
      // child-profile.ts: `from && to ? … : ''` renders the ordinary state of
      // a running plan as an empty cell.
      read: (row, ctx) => {
        const from = text(row, 'period_start');
        const to = text(row, 'period_end');
        if (from && to) {
          return `${ctx.format.dayMonthYear(from)} – ${ctx.format.dayMonthYear(to)}`;
        }
        if (from) {
          return ctx.i18n.translate('field.periodFrom', { d: ctx.format.dayMonthYear(from) });
        }
        if (to) {
          return ctx.i18n.translate('field.periodUntil', { d: ctx.format.dayMonthYear(to) });
        }
        return '';
      },
    },
    {
      key: 'publishedAt', labelKey: 'field.publishedAt',
      read: (row, ctx) => {
        const at = text(row, 'published_at');
        return at ? ctx.format.shortDate(at) : '';
      },
    },
  ],
  actions: [
    {
      key: 'publish',
      labelKey: 'reports.publish',
      icon: 'ic-send',
      primary: true,
      permission: 'REPORT.PUBLISH',
      when: (row) => text(row, 'status') === 'DRAFT',
      // Publishing is the moment a family can read this. It is the one
      // action on these five screens that cannot be taken back from here.
      noteKey: 'reports.publishNote',
      run: (api, row) => api.publishReport(idOf(row, 'report_id')),
      doneKey: 'reports.published',
    },
  ],
};

// =====================================================================
// INVOICES
// =====================================================================

export const INVOICES_SPEC: DaySpec = {
  resource: 'invoices',
  titleKey: 'nav.billing',
  subKey: 'billing.sub',
  idColumn: 'invoice_id',
  window: 'ledger',
  statusPrefix: 'status.invoice.',
  statusFilter: ['DRAFT', 'ISSUED', 'PARTIALLY_PAID', 'PAID', 'CANCELLED'],
  emptyKey: 'billing.empty',
  emptyNoteKey: 'billing.emptyNote',
  tone: (status) => {
    if (status === 'PAID') {
      return 'hbh-badge--success';
    }
    if (status === 'CANCELLED' || status === 'DRAFT') {
      return 'hbh-badge--muted';
    }
    return status === 'PARTIALLY_PAID' ? 'hbh-badge--progress' : 'hbh-badge--info';
  },
  columns: [
    { key: 'no', labelKey: 'field.invoiceNo', read: (row) => text(row, 'invoice_no'), ltr: true },
    { key: 'child', labelKey: 'field.child', read: (row) => ref(row, 'child', 'full_name_ar') },
    {
      key: 'issue', labelKey: 'field.issueDate',
      read: (row, ctx) => {
        const day = text(row, 'issue_date');
        return day ? ctx.format.shortDate(day) : '';
      },
    },
    {
      key: 'due', labelKey: 'field.dueDate',
      read: (row, ctx) => {
        const day = text(row, 'due_date');
        return day ? ctx.format.shortDate(day) : '';
      },
    },
    {
      key: 'total', labelKey: 'field.total', ltr: true,
      // The currency travels with the amount and is never assumed - a centre
      // in another country is a row, not a release.
      read: (row, ctx) => ctx.format.money(
        Number(text(row, 'total_amt')), text(row, 'currency_code') || undefined),
    },
    {
      key: 'paid', labelKey: 'field.paid', ltr: true,
      read: (row, ctx) => ctx.format.money(
        Number(text(row, 'paid_amt')), text(row, 'currency_code') || undefined),
    },
  ],
  /**
   * Selling a package belongs here rather than nowhere.
   *
   * It is a billing act - it creates the child's entitlement to a run of
   * sessions - and this console has no child profile to sell it from. Put on
   * the invoices screen because that is where whoever sells it already is.
   *
   * The service answers 409 REFUSED when the caller may not do this, not
   * 403: the schema uses one error code for "needs BILLING.MANAGE" and for
   * "this record no longer accepts changes", and the API chose the less
   * presumptuous of the two statuses rather than guess.
   */
  create: [{
    key: 'newInvoice',
    labelKey: 'billing.newInvoice',
    icon: 'ic-receipt',
    primary: true,
    permission: 'BILLING.MANAGE',
    // The invoice starts empty and in DRAFT, then lines are added to it, then
    // it is issued. That order is the schema's: once issued the figures are
    // frozen because the family has been told a number to pay.
    noteKey: 'billing.newInvoiceNote',
    fields: [
      // The same search, for the same reason. The backlog named the
      // booking screen; this field is the identical control on the
      // identical table, and leaving it a 200-row dropdown would mean a
      // centre that can book a child it cannot invoice.
      {
        name: 'child_id', labelKey: 'field.child', kind: 'search',
        lookup: 'children', required: true, hintKey: 'field.childSearchHint',
      },
      { name: 'due_date', labelKey: 'field.dueDate', kind: 'datetime', hintKey: 'billing.dueHint' },
      { name: 'note_ar', labelKey: 'field.note', kind: 'text' },
    ],
    run: (api, values) => api.createInvoice(
      Number(values['child_id']),
      // A due date is a DAY, not an instant: an invoice is not due at 14:32.
      values['due_date'] ? values['due_date'].slice(0, 10) : undefined,
      values['note_ar'] ?? ''),
    doneKey: 'billing.invoiceCreated',
  }, {
    key: 'sell',
    labelKey: 'billing.sellPackage',
    icon: 'ic-tag',
    permission: 'BILLING.MANAGE',
    noteKey: 'billing.sellNote',
    fields: [
      {
        name: 'child_id', labelKey: 'field.child', kind: 'search',
        lookup: 'children', required: true, hintKey: 'field.childSearchHint',
      },
      {
        name: 'package_id', labelKey: 'field.package', kind: 'lookup',
        lookup: 'service-packages', required: true,
        // Selling a package charges a family for a number of sessions at a
        // price. The child above is typed; the thing being sold was
        // whichever package sorted first, so the two halves of one sentence
        // were held to different standards.
        placeholderKey: 'field.choosePackage',
      },
    ],
    run: (api, values) => api.sellPackage(
      Number(values['child_id']), Number(values['package_id'])),
    doneKey: 'billing.packageSold',
  }],
  actions: [
    {
      key: 'addLine',
      labelKey: 'billing.addLine',
      icon: 'ic-plus',
      permission: 'BILLING.MANAGE',
      // Only while it is a draft. The service refuses afterwards with 409,
      // and offering the button would be a promise it always breaks.
      when: (row) => text(row, 'status') === 'DRAFT',
      noteKey: 'billing.addLineNote',
      fields: [
        { name: 'description_ar', labelKey: 'field.description', kind: 'text', required: true },
        { name: 'qty', labelKey: 'field.qty', kind: 'money', required: true, ltr: true },
        {
          name: 'unit_amt', labelKey: 'field.unitPrice', kind: 'money', required: true, ltr: true,
          hintKey: 'billing.unitHint',
        },
      ],
      run: (api, row, values) => api.addInvoiceLine(
        idOf(row, 'invoice_id'), values['description_ar'],
        values['qty'], values['unit_amt']),
      doneKey: 'billing.lineAdded',
    },
    {
      key: 'issue',
      labelKey: 'billing.issue',
      icon: 'ic-receipt',
      permission: 'BILLING.MANAGE',
      when: (row) => text(row, 'status') === 'DRAFT',
      noteKey: 'billing.issueNote',
      run: (api, row) => api.issueInvoice(idOf(row, 'invoice_id')),
      doneKey: 'billing.issued',
    },
    {
      key: 'pay',
      labelKey: 'billing.addPayment',
      icon: 'ic-money',
      primary: true,
      permission: 'BILLING.MANAGE',
      when: (row) => ['ISSUED', 'PARTIALLY_PAID'].includes(text(row, 'status')),
      fields: [
        {
          name: 'amount', labelKey: 'field.amount', kind: 'money', required: true, ltr: true,
          hintKey: 'billing.amountHint',
        },
        {
          name: 'method_code', labelKey: 'field.method', kind: 'select', required: true,
          // CASH is the commonest method at this desk, and "commonest" is
          // not "what happened". The amount beside it is typed every time;
          // the method was pre-answered, so a card payment recorded in a
          // hurry reads as cash and the till will not reconcile - a
          // discrepancy nobody can trace back to a dropdown.
          placeholderKey: 'field.chooseMethod',
          options: [
            { value: 'CASH', labelKey: 'pay.CASH' },
            { value: 'CARD', labelKey: 'pay.CARD' },
            { value: 'TRANSFER', labelKey: 'pay.TRANSFER' },
            { value: 'WALLET', labelKey: 'pay.WALLET' },
            { value: 'OTHER', labelKey: 'pay.OTHER' },
          ],
        },
        { name: 'note_ar', labelKey: 'field.note', kind: 'text' },
      ],
      run: (api, row, values) => api.addPayment(
        idOf(row, 'invoice_id'), values['amount'],
        values['method_code'], values['note_ar'] ?? ''),
      doneKey: 'billing.paymentAdded',
    },
  ],
};

// =====================================================================
// REQUESTS
// =====================================================================

export const REQUESTS_SPEC: DaySpec = {
  resource: 'requests',
  titleKey: 'nav.requests',
  subKey: 'requests.sub',
  idColumn: 'request_id',
  window: 'ledger',
  statusPrefix: 'status.request.',
  statusFilter: ['NEW', 'ACCEPTED', 'REJECTED'],
  kindPrefix: 'kind.request.',
  kindFilter: ['RESCHEDULE', 'CANCEL', 'CALLBACK'],
  emptyKey: 'requests.empty',
  emptyNoteKey: 'requests.emptyNote',
  tone: (status) => {
    if (status === 'ACCEPTED') {
      return 'hbh-badge--success';
    }
    return status === 'REJECTED' ? 'hbh-badge--muted' : 'hbh-badge--progress';
  },
  columns: [
    { key: 'no', labelKey: 'field.requestNo', read: (row) => text(row, 'request_no'), ltr: true },
    {
      key: 'kind', labelKey: 'field.kind',
      read: (row, ctx) => {
        const kind = text(row, 'kind_code');
        return kind ? ctx.i18n.translate(`kind.request.${kind}`) : '';
      },
    },
    { key: 'child', labelKey: 'field.child', read: (row) => ref(row, 'child', 'full_name_ar') },
    { key: 'guardian', labelKey: 'field.guardian', read: (row) => ref(row, 'guardian', 'full_name_ar') },
    {
      // The number reception rings back on. It arrives now because the
      // service stopped hanging the guardian off the account: a family with
      // no portal login - one converted from an application, or entered from
      // paper - used to reach this screen with no guardian at all.
      key: 'guardianMobile', labelKey: 'field.mobile', ltr: true,
      read: (row) => ref(row, 'guardian', 'mobile'),
    },
    { key: 'body', labelKey: 'field.body', read: (row) => text(row, 'body_ar') },
    {
      key: 'preferred', labelKey: 'field.preferredAt',
      read: (row, ctx) => {
        const at = text(row, 'preferred_at');
        return at ? `${ctx.format.shortDate(at)} · ${ctx.format.time(at)}` : '';
      },
    },
    {
      key: 'created', labelKey: 'field.createdAt',
      read: (row, ctx) => {
        const at = text(row, 'created_at');
        return at ? ctx.format.shortDate(at) : '';
      },
    },
  ],
  actions: [
    {
      key: 'decide',
      labelKey: 'requests.decide',
      icon: 'ic-check-circle',
      primary: true,
      permission: 'REQUEST.MANAGE',
      when: (row) => text(row, 'status') === 'NEW',
      // Deciding a request does not move the appointment it is about. A
      // reschedule that is accepted still needs the booking changed, and
      // saying so here is cheaper than a family who thinks it was.
      noteKey: 'requests.decideNote',
      fields: [
        {
          name: 'status', labelKey: 'field.decision', kind: 'select', required: true,
          // THE WORST OF THE SET, and the reason is the word "decision".
          // The dialog opened on ACCEPTED, so a family's request was one
          // unread click from being granted - and hbh.decide_request
          // notifies the family, so the mistake leaves the building before
          // anybody notices it. A decision is the one thing a screen must
          // never make on somebody's behalf.
          placeholderKey: 'field.chooseDecision',
          options: [
            { value: 'ACCEPTED', labelKey: 'status.request.ACCEPTED' },
            { value: 'REJECTED', labelKey: 'status.request.REJECTED' },
          ],
        },
        { name: 'note_ar', labelKey: 'field.decisionNote', kind: 'textarea' },
      ],
      run: (api, row, values) => api.decideRequest(
        idOf(row, 'request_id'), values['status'], values['note_ar'] ?? ''),
      doneKey: 'requests.decided',
    },
  ],
};

// =====================================================================
// ENROLMENT APPLICATIONS
// =====================================================================

/**
 * The queue of families who have never been here.
 *
 * Every field on these rows is UNTRUSTED TEXT - a name, a mobile, a paragraph
 * about a child, typed by whoever found the login page. The row is not a
 * child and not a guardian: it sits in its own table until somebody at the
 * centre reads it, rings the family, and converts it. That is why this screen
 * exists, and why "convert" is a separate button from every status change.
 *
 * `main_concern_ar` is WHAT THE FAMILY SAID, never a diagnosis. The column
 * heading says so, because the same sentence read as clinical would follow
 * the child into their record.
 */
export const ENROLMENTS_SPEC: DaySpec = {
  resource: 'enrolments',
  titleKey: 'nav.enrolments',
  subKey: 'enrolments.sub',
  idColumn: 'application_id',
  window: 'queue',
  archivable: true,
  statusPrefix: 'status.enrolment.',
  statusFilter: ['NEW', 'CONTACTED', 'ASSESSMENT_BOOKED', 'ENROLLED', 'REJECTED', 'DUPLICATE'],
  emptyKey: 'enrolments.empty',
  emptyNoteKey: 'enrolments.emptyNote',
  tone: (status) => {
    if (status === 'ENROLLED') {
      return 'hbh-badge--success';
    }
    if (status === 'REJECTED' || status === 'DUPLICATE') {
      return 'hbh-badge--muted';
    }
    return status === 'NEW' ? 'hbh-badge--progress' : 'hbh-badge--info';
  },
  columns: [
    { key: 'no', labelKey: 'field.applicationNo', read: (row) => text(row, 'application_no'), ltr: true },
    {
      key: 'submitted', labelKey: 'field.submittedAt',
      read: (row, ctx) => {
        const at = text(row, 'submitted_at');
        return at ? `${ctx.format.shortDate(at)} · ${ctx.format.time(at)}` : '';
      },
    },
    { key: 'parent', labelKey: 'field.parentName', read: (row) => text(row, 'parent_name_ar') },
    // The number reception rings. It is the point of the row.
    { key: 'mobile', labelKey: 'field.mobile', read: (row) => text(row, 'parent_mobile'), ltr: true },
    { key: 'childName', labelKey: 'field.childName', read: (row) => text(row, 'child_name_ar') },
    {
      key: 'age', labelKey: 'field.age',
      // The age, not the birth date. Whether a two-year-old or a nine-year-old
      // is waiting changes who should call them back, and a date makes the
      // reader do that arithmetic sixty times down a list.
      read: (row, ctx) => {
        const born = text(row, 'child_birth_date');
        return born ? ctx.i18n.plural('child.age', ctx.format.ageYears(born)) : '';
      },
    },
    {
      key: 'concern', labelKey: 'field.mainConcern',
      read: (row) => text(row, 'main_concern_ar'),
    },
    {
      key: 'source', labelKey: 'field.source',
      read: (row, ctx) => {
        const source = text(row, 'source_code');
        return source ? ctx.i18n.translate(`source.${source}`) : '';
      },
    },
  ],
  actions: [
    {
      key: 'status',
      labelKey: 'enrolments.changeStatus',
      icon: 'ic-check-circle',
      permission: 'ENROLMENT.MANAGE',
      when: (row) => (ENROLMENT_NEXT[text(row, 'status')] ?? []).length > 0,
      fields: [
        {
          name: 'status', labelKey: 'field.newStatus', kind: 'select', required: true,
          optionsFor: nextOptions(ENROLMENT_NEXT, 'status.enrolment.'),
          // NEW offers CONTACTED, REJECTED and DUPLICATE, and the dialog
          // opened on CONTACTED - a claim that somebody rang this family.
          // Marked in error it is close to invisible: the application
          // leaves the "not yet called" pile, and the family waits for a
          // call the system already believes it made.
          placeholderKey: 'field.chooseStatus',
        },
        { name: 'note_ar', labelKey: 'field.note', kind: 'textarea' },
      ],
      run: (api, row, values) => api.setEnrolmentStatus(
        idOf(row, 'application_id'), values['status'], values['note_ar'] ?? ''),
      doneKey: 'enrolments.statusChanged',
    },
    {
      key: 'convert',
      labelKey: 'enrolments.convert',
      icon: 'ic-user-plus',
      primary: true,
      permission: 'ENROLMENT.MANAGE',
      // Refused from NEW by the database, so not offered from NEW here.
      when: (row) => ['CONTACTED', 'ASSESSMENT_BOOKED'].includes(text(row, 'status')),
      // Said before the button is pressed, because two of the three sentences
      // are things people get wrong: this creates real records, and it does
      // NOT create permission to watch the child in a session.
      noteKey: 'enrolments.convertNote',
      fields: [
        { name: 'note_ar', labelKey: 'field.note', kind: 'textarea' },
      ],
      run: (api, row, values) => api.convertEnrolment(
        idOf(row, 'application_id'), values['note_ar'] ?? ''),
      doneKey: 'enrolments.converted',
    },
  ],
};

/** What a lookup list is keyed and labelled by. */
export const LOOKUP_SHAPE: Readonly<Record<LookupResource, { id: string; label: string }>> = {
  children: { id: 'child_id', label: 'full_name_ar' },
  therapists: { id: 'therapist_id', label: 'full_name_ar' },
  rooms: { id: 'room_id', label: 'name_ar' },
  services: { id: 'service_id', label: 'name_ar' },
  'service-packages': { id: 'package_id', label: 'name_ar' },
};

export { text as readText, ref as readRef };
