import { OpsResource } from '../api/ops-api';

/**
 * What a screen needs to know about one resource.
 *
 * The service exposes fourteen resources with the same six verbs, so the
 * console has one screen and fourteen descriptions of a table rather than
 * fourteen screens. A new resource is a constant here, not a component - and
 * a fix to the list, the editor or the archive flow lands in all of them.
 *
 * These are descriptions of a form, not of the schema. The service owns the
 * columns; this says which of them a person edits and what to call them.
 */

/**
 * `textarea` is not a longer `text`. It is for a value whose LINE BREAKS
 * CARRY MEANING - the directions to the centre are three separate
 * instructions and the public page renders one per line. A single-line
 * input cannot hold a newline at all, so the editor would silently lose
 * the shape of what they typed and the page would show one run-on
 * sentence.
 */
/**
 * `combo` is a box to type in WITH the known answers offered in it, and it is
 * not a softer `select`. It is for a column where most rows are one of a few
 * recurring things and the rest are one-offs that cannot be listed in
 * advance.
 *
 * `nps_surveys.code` is the case. Most surveys are the centre's standing
 * questions - after a session, after a report - and typing those by hand is a
 * spelling test: PARENT-VISIT and PARENT_VISIT are two surveys under
 * `uq_nps_code`, and the results screen then reports one question as two. But
 * a survey also gets raised for one occasion - a release, an outage - and
 * that code is new every time, so a closed list would make the occasion
 * itself impossible to ask about.
 */
export type FieldKind =
  'text' | 'textarea' | 'number' | 'date' | 'time' | 'select' | 'combo' | 'switch' | 'ref';

export interface FieldSpec {
  /** The column name, exactly as the service sends and accepts it. */
  readonly name: string;
  readonly labelKey: string;
  readonly kind: FieldKind;
  /** Options for a select. `labelKey` is resolved through the bundle. */
  readonly options?: readonly { readonly value: string; readonly labelKey: string }[];

  /**
   * Where a `ref` field's readable name comes from.
   *
   * A foreign key is stored as a number and the service sends the number and
   * nothing else. Rendered raw, a therapist opening the plans list read:
   *
   *	خطة تخاطب — خريف ٢٠٢٦ · 122 · 66 · 46
   *
   * - a child, a service and a therapist, none of them named. Sixteen list
   * columns across the clinical screens looked like that.
   *
   * So the screen loads the referenced resource once and joins by id. The
   * number stays the value that is stored and sent. The same complete list
   * supplies named choices in the editor, with identifiers to disambiguate
   * equal names. Contextual parent references are prefilled by the child's file.
   */
  readonly ref?: {
    /** The resource to read the names from. */
    readonly resource: OpsResource;
    /** Its identifier column - what this field's value points at. */
    readonly idColumn: string;
    /** The column to show. */
    readonly labelColumn: string;
  };
  /** Identifiers and numbers read left to right even in an Arabic page. */
  readonly ltr?: boolean;

  /**
   * Shown, never sent.
   *
   * A column the service refuses on UPDATE still has to be READABLE, or the
   * row cannot be identified. hbh.site_sections is the case: its only
   * writable column is a yes/no flag, and a list of twelve rows reading
   * "نعم / نعم / لا" with no column saying WHICH section is not a screen.
   *
   * Putting `code` in `fields` without this would have sent it in the PATCH
   * body - and a key outside the service's allow list is a 400 that names
   * the field but not the reason. So the field is drawn in the list, drawn
   * disabled in the editor, and dropped from the body.
   *
   * It is not `editOnly` inverted. `editOnly` is about WHEN a field is
   * offered; this is about whether it is offered at all.
   */
  readonly readOnly?: boolean;
  /** Shown as a column in the list. Everything is shown in the editor. */
  readonly inList?: boolean;
  /** Refused by the form when empty, before the request is made. */
  readonly required?: boolean;

  /**
   * Hidden while creating, shown while editing.
   *
   * It exists for `status` on the website's content. Those resources accept
   * `status` on UPDATE and not on INSERT, deliberately: publishing is a
   * separate act from writing - it needs SITE.PUBLISH rather than SITE.EDIT,
   * and a testimonial or a certificate has to be looked at before it goes on
   * the open internet. Draft first, publish second, always.
   *
   * Without this the form offered "منشور" in the create dialogue and the
   * service refused the whole row - with "check the values you entered",
   * which names nothing and points at nothing. A control that cannot work is
   * worse than an absent one: somebody fills the form, picks the obvious
   * option, and is told their data is wrong.
   */
  readonly editOnly?: boolean;

  /**
   * Shown only while another field holds one of these values - and CLEARED
   * when it does not.
   *
   * This exists for a table that refuses half its own form. hbh.nps_surveys
   * carries ck_nps_shape:
   *
   *   (PERIOD AND period_days IS NOT NULL AND action_code IS NULL)
   *   OR (ACTION AND action_code IS NOT NULL AND period_days IS NULL)
   *
   * so "every N days" and "after event X" are not two fields that happen to
   * pair up, they are two mutually exclusive shapes of one row. The editor
   * drew both at once, and a select starts on its first option, so choosing
   * "every period" still sent action_code = SESSION_COMPLETED and the whole
   * row was refused - as "check the values you entered", which names nothing.
   *
   * Hiding alone would not have fixed it. A PATCH carries only what it names,
   * so a hidden field left unsent keeps its OLD value in the row, and the
   * constraint fires on a column the person can no longer see. Switching the
   * trigger was impossible in either direction. Hence `clears`: a field held
   * back by this rule is sent as an explicit null, so the shape the person
   * chose is the shape that reaches the table.
   *
   * Distinct from `editOnly`, which OMITS the field: the service refuses
   * `status` on INSERT, and sending null would be asking for it to be blank
   * rather than not asking at all.
   */
  readonly showWhen?: {
    readonly field: string;
    readonly equals: readonly string[];
  };
}

export interface ResourceSpec {
  readonly resource: OpsResource;
  readonly titleKey: string;
  readonly subKey: string;
  /** The primary key column - `child_id`, `room_id`, and so on. */
  readonly idColumn: string;
  /** Permission needed to open the list. */
  readonly viewPermission: string;
  /** Permission needed to create, edit and archive. */
  readonly writePermission: string;
  readonly fields: readonly FieldSpec[];
  /** Whether the list takes a `q` search parameter. */
  readonly searchable?: boolean;
  /**
   * The search box's placeholder: WHAT the term is matched against (#17).
   *
   * It must name the columns in `search` for this resource in
   * api/internal/store/crud.go, and nothing else. A placeholder is a promise:
   * "search by name or code" on therapists, who have no code searched, sends
   * a receptionist typing a code into a box that can never find it - and
   * reads the empty result as "no such therapist". Change both together.
   */
  readonly searchKey?: string;
  /**
   * The column carrying the row's own lifecycle status, if it has one. It is
   * NOT the archive flag: a child can be DISCHARGED and still be a live row,
   * while archiving is the centre hiding the record. Different questions.
   */
  readonly statusColumn?: string;
  readonly statusPrefix?: string;

  /**
   * The row set is the schema's, not the user's: no "add", no "archive".
   *
   * hbh.site_sections has one row per <section> in site/index.html and can
   * have no others. The database says so three times over - ck_ss_code
   * lists the codes, uq_site_sections forbids a second of each, and 0041
   * granted hbh_app UPDATE with no INSERT at all - so the add button here
   * could only ever produce an error message.
   *
   * Archiving is worse than useless on such a table, and quietly so. The
   * exporter reads `WHERE active_flg`, so an archived row simply leaves the
   * map; site/app.js hides a section only on an explicit `false`, and a
   * missing key is not false. Archiving a HIDDEN section therefore PUBLISHES
   * it - the opposite of what the button reads as, with nothing on screen
   * to say so.
   */
  readonly fixedRows?: boolean;

  /**
   * Where a row leads, when it leads somewhere.
   *
   * Only children have a file behind them today. A row that looks clickable
   * and is not is worse than a plain one, so this is opt-in per resource
   * rather than a link drawn on every table.
   */
  readonly rowLink?: (id: number) => readonly (string | number)[];
}

const GENDER = [
  { value: 'M', labelKey: 'gender.M' },
  { value: 'F', labelKey: 'gender.F' },
];

/** hbh.therapists.status - ck_therapists_status (0005_scheduling.up.sql:142). */
const THERAPIST_STATUS = [
  { value: 'ACTIVE', labelKey: 'status.therapist.ACTIVE' },
  { value: 'ON_LEAVE', labelKey: 'status.therapist.ON_LEAVE' },
  { value: 'RESIGNED', labelKey: 'status.therapist.RESIGNED' },
];

export const CHILDREN_SPEC: ResourceSpec = {
  resource: 'children',
  titleKey: 'children.children',
  subKey: 'children.sub',
  idColumn: 'child_id',
  viewPermission: 'CHILD.VIEW_ALL',
  writePermission: 'CHILD.EDIT',
  searchable: true,
  searchKey: 'search.children',
  statusColumn: 'status',
  statusPrefix: 'status.child.',
  rowLink: (id) => ['/children', id],
  fields: [
    // No photograph field here on purpose. A child's picture is not a text
    // box holding an address - it is an upload behind a recorded consent,
    // stored as an attachment and served from an authenticated route. It has
    // its own control on the child's card rather than a line in this form,
    // because a form field would let somebody paste a link and bypass the
    // consent the schema requires.
    { name: 'full_name_ar', labelKey: 'field.fullName', kind: 'text', inList: true, required: true },
    { name: 'child_no', labelKey: 'field.childNo', kind: 'text', ltr: true, inList: true },
    { name: 'birth_date', labelKey: 'field.birthDate', kind: 'date', ltr: true, inList: true, required: true },
    { name: 'gender', labelKey: 'field.gender', kind: 'select', options: GENDER, inList: true, required: true },
  ],
};

export const THERAPISTS_SPEC: ResourceSpec = {
  resource: 'therapists',
  titleKey: 'therapists.therapists',
  subKey: 'therapists.sub',
  idColumn: 'therapist_id',
  viewPermission: 'STAFF.MANAGE',
  writePermission: 'STAFF.MANAGE',
  searchable: true,
  searchKey: 'search.therapists',
  // The name opens the profile editor - biography, languages, certificates,
  // and the consent that lets any of it reach a family.
  rowLink: (id) => ['/therapists', id, 'profile'],
  fields: [
    // The columns the service will accept, and only those. A therapist has
    // no code and no email in this schema; asking for either produced a
    // VALIDATION naming a field the person could see filled in.
    { name: 'full_name_ar', labelKey: 'field.fullName', kind: 'text', inList: true, required: true },
    { name: 'title_ar', labelKey: 'field.jobTitle', kind: 'text', inList: true },
    { name: 'mobile', labelKey: 'field.mobile', kind: 'text', ltr: true, inList: true },
    { name: 'status', labelKey: 'field.status', kind: 'select', options: THERAPIST_STATUS, inList: false },
  ],
};

export const WORKING_HOURS_SPEC: ResourceSpec = {
  resource: 'working-hours',
  titleKey: 'therapists.workingHours',
  subKey: 'therapists.workingHoursSub',
  idColumn: 'working_hour_id',
  viewPermission: 'STAFF.MANAGE',
  writePermission: 'STAFF.MANAGE',
  fields: [
    { name: 'therapist_id', labelKey: 'field.therapist', kind: 'ref', ref: { resource: 'therapists', idColumn: 'therapist_id', labelColumn: 'full_name_ar' }, ltr: true, inList: true, required: true },
    // Egypt's weekend is Friday and Saturday, and that is a centre parameter,
    // not a constant - the day numbers come from the centre's weekend_days.
    { name: 'weekday', labelKey: 'field.weekday', kind: 'number', ltr: true, inList: true, required: true },
    { name: 'start_time', labelKey: 'field.from', kind: 'time', ltr: true, inList: true, required: true },
    { name: 'end_time', labelKey: 'field.to', kind: 'time', ltr: true, inList: true, required: true },
  ],
};

/**
 * Which therapist carries which child, for which service.
 *
 * Not an administrative nicety. hbh.start_session refuses with HB023 unless
 * this row exists for the appointment's therapist, child AND service - so
 * without a caseload the centre can book appointments and check children in
 * and never start a single session. It was missing from this console until a
 * session was actually started against a live service and refused.
 */
export const CASELOAD_SPEC: ResourceSpec = {
  resource: 'caseload',
  titleKey: 'therapists.caseload',
  subKey: 'therapists.caseloadSub',
  idColumn: 'caseload_id',
  viewPermission: 'STAFF.MANAGE',
  writePermission: 'STAFF.MANAGE',
  fields: [
    { name: 'therapist_id', labelKey: 'field.therapist', kind: 'ref', ref: { resource: 'therapists', idColumn: 'therapist_id', labelColumn: 'full_name_ar' }, ltr: true, inList: true, required: true },
    { name: 'child_id', labelKey: 'field.child', kind: 'ref', ref: { resource: 'children', idColumn: 'child_id', labelColumn: 'full_name_ar' }, ltr: true, inList: true, required: true },
    // The service is part of the key, not a detail: a therapist may carry a
    // child for speech and not for occupational therapy, and starting a
    // session checks all three.
    { name: 'service_id', labelKey: 'field.service', kind: 'ref', ref: { resource: 'services', idColumn: 'service_id', labelColumn: 'name_ar' }, ltr: true, inList: true, required: true },
    // Who carries this child for this service when more than one therapist
    // does. It is here because hbh.assign_therapist MOVES it - demoting the
    // previous holder in one statement and promoting this row in another -
    // and nothing in the schema enforces one primary per (child, service).
    // Without the field the one behaviour that makes the new route worth
    // having is unreachable from the screen (HBH-103).
    { name: 'is_primary_flg', labelKey: 'field.primaryTherapist', kind: 'switch', inList: true },
  ],
};

export const ROOMS_SPEC: ResourceSpec = {
  resource: 'rooms',
  titleKey: 'rooms.rooms',
  subKey: 'rooms.sub',
  idColumn: 'room_id',
  viewPermission: 'CATALOG.MANAGE',
  writePermission: 'CATALOG.MANAGE',
  searchable: true,
  searchKey: 'search.rooms',
  fields: [
    { name: 'name_ar', labelKey: 'field.name', kind: 'text', inList: true, required: true },
    { name: 'code', labelKey: 'field.code', kind: 'text', ltr: true, inList: true },
    // Not capacity: this centre runs one child per session, so a room's
    // capacity is not a number anybody books against. The column does not
    // exist and the service refused it.
    { name: 'notes_ar', labelKey: 'field.notes', kind: 'text' },
  ],
};

/**
 * Cameras carry no address, no credential and no gateway path - the service
 * strips them from every response, and this form never asks for one. A camera
 * here is a name and the room it is in; where it actually is stays between
 * the service and the streaming edge.
 */
export const CAMERAS_SPEC: ResourceSpec = {
  resource: 'cameras',
  titleKey: 'rooms.cameras',
  subKey: 'rooms.camerasSub',
  idColumn: 'camera_id',
  viewPermission: 'CATALOG.MANAGE',
  writePermission: 'CATALOG.MANAGE',
  fields: [
    { name: 'name_ar', labelKey: 'field.name', kind: 'text', inList: true, required: true },
    { name: 'room_id', labelKey: 'field.room', kind: 'ref', ref: { resource: 'rooms', idColumn: 'room_id', labelColumn: 'name_ar' }, ltr: true, inList: true, required: true },
  ],
};

export const SERVICES_SPEC: ResourceSpec = {
  resource: 'services',
  titleKey: 'catalog.services',
  subKey: 'catalog.servicesSub',
  idColumn: 'service_id',
  viewPermission: 'CATALOG.MANAGE',
  writePermission: 'CATALOG.MANAGE',
  searchable: true,
  searchKey: 'search.services',
  fields: [
    { name: 'name_ar', labelKey: 'field.name', kind: 'text', inList: true, required: true },
    { name: 'code', labelKey: 'field.code', kind: 'text', ltr: true, inList: true },
    { name: 'kind_code', labelKey: 'field.kind', kind: 'text', ltr: true, inList: true },
    /*
     * HOW LONG IT RUNS, which decides every slot the booking screen offers.
     *
     * The column has always existed and this form never showed it, so every
     * service created from the console took the default of 45 minutes and
     * there was no way to say otherwise without SQL. A thirty-minute
     * consultation could not be described at all.
     */
    { name: 'default_duration_min', labelKey: 'field.defaultDuration', kind: 'number',
      ltr: true, inList: true },
    /*
     * THE TWO FLAGS THAT MAKE A SERVICE A CONSULTATION.
     *
     * Off and off is a consultation: no therapy session is opened when it
     * starts, and the child is not added to the therapist's caseload for
     * it. That combination is also the ONLY one hbh.validate_slot will
     * accept without a room - it answers SERVICE_NEEDS_ROOM otherwise - so
     * until these were on this form, nobody could create a service that
     * could be held online, and the whole consultation feature had no way
     * in.
     *
     * ck_services_caseload_needs_session refuses "no session but yes
     * caseload", which is the one combination of the four that means
     * nothing: a child cannot be on a caseload for work that never opens a
     * session. The schema refuses it and the service answers 400; the
     * labels are written so the dependency reads in the order the switches
     * are drawn.
     */
    { name: 'creates_session_flg', labelKey: 'field.createsSession', kind: 'switch',
      inList: true },
    { name: 'needs_caseload_flg', labelKey: 'field.needsCaseload', kind: 'switch' },
  ],
};

export const PACKAGES_SPEC: ResourceSpec = {
  resource: 'service-packages',
  titleKey: 'catalog.packages',
  subKey: 'catalog.packagesSub',
  idColumn: 'package_id',
  viewPermission: 'CATALOG.MANAGE',
  writePermission: 'CATALOG.MANAGE',
  fields: [
    { name: 'name_ar', labelKey: 'field.name', kind: 'text', inList: true, required: true },
    { name: 'service_id', labelKey: 'field.service', kind: 'ref', ref: { resource: 'services', idColumn: 'service_id', labelColumn: 'name_ar' }, ltr: true, inList: true, required: true },
    { name: 'sessions_cnt', labelKey: 'field.sessions', kind: 'number', ltr: true, inList: true, required: true },
    // A decimal string, never a float. It is summed and compared against a
    // total, which is the one thing a float must not be used for.
    { name: 'price_amt', labelKey: 'field.price', kind: 'text', ltr: true, inList: true },
  ],
};

export const ACTIVITY_LIBRARY_SPEC: ResourceSpec = {
  resource: 'activity-library',
  titleKey: 'catalog.activities',
  subKey: 'catalog.activitiesSub',
  idColumn: 'activity_id',
  viewPermission: 'CATALOG.MANAGE',
  writePermission: 'CATALOG.MANAGE',
  searchable: true,
  searchKey: 'search.activity-library',
  fields: [
    { name: 'title_ar', labelKey: 'field.title', kind: 'text', inList: true, required: true },
    { name: 'code', labelKey: 'field.code', kind: 'text', ltr: true, inList: true },
    { name: 'how_to_ar', labelKey: 'field.instructions', kind: 'text' },
  ],
};

/** hbh.treatment_plans.status - ck_plans_status (0006:81). */
const PLAN_STATUS = [
  { value: 'DRAFT', labelKey: 'status.plan.DRAFT' },
  { value: 'ACTIVE', labelKey: 'status.plan.ACTIVE' },
  { value: 'COMPLETED', labelKey: 'status.plan.COMPLETED' },
  { value: 'CANCELLED', labelKey: 'status.plan.CANCELLED' },
];

/** hbh.plan_goals.status - ck_goals_status (0006:115). */
const GOAL_STATUS = [
  { value: 'OPEN', labelKey: 'status.goal.OPEN' },
  { value: 'MET', labelKey: 'status.goal.MET' },
  { value: 'DROPPED', labelKey: 'status.goal.DROPPED' },
];

/**
 * The treatment plan, and the three things hung off it.
 *
 * The child's file opens these same editors with the originating child,
 * plan or goal prefilled. Reference fields show names while preserving the
 * identifiers expected by CRUD; the server still checks every relationship.
 */
export const PLANS_SPEC: ResourceSpec = {
  resource: 'plans',
  titleKey: 'plans.plans',
  subKey: 'plans.sub',
  idColumn: 'plan_id',
  viewPermission: 'PLAN.MANAGE',
  writePermission: 'PLAN.MANAGE',
  statusColumn: 'status',
  statusPrefix: 'status.plan.',
  fields: [
    { name: 'title_ar', labelKey: 'field.title', kind: 'text', inList: true, required: true },
    { name: 'child_id', labelKey: 'field.child', kind: 'ref', ref: { resource: 'children', idColumn: 'child_id', labelColumn: 'full_name_ar' }, ltr: true, inList: true, required: true },
    { name: 'service_id', labelKey: 'field.service', kind: 'ref', ref: { resource: 'services', idColumn: 'service_id', labelColumn: 'name_ar' }, ltr: true, inList: true, required: true },
    { name: 'therapist_id', labelKey: 'field.therapist', kind: 'ref', ref: { resource: 'therapists', idColumn: 'therapist_id', labelColumn: 'full_name_ar' }, ltr: true, inList: true, required: true },
    { name: 'start_date', labelKey: 'field.from', kind: 'date', ltr: true, inList: true, required: true },
    { name: 'end_date', labelKey: 'field.to', kind: 'date', ltr: true },
  ],
};

export const GOALS_SPEC: ResourceSpec = {
  resource: 'goals',
  titleKey: 'plans.goals',
  subKey: 'plans.goalsSub',
  idColumn: 'goal_id',
  viewPermission: 'PLAN.MANAGE',
  writePermission: 'PLAN.MANAGE',
  statusColumn: 'status',
  statusPrefix: 'status.goal.',
  fields: [
    { name: 'plan_id', labelKey: 'field.plan', kind: 'ref', ref: { resource: 'plans', idColumn: 'plan_id', labelColumn: 'title_ar' }, ltr: true, inList: true, required: true },
    { name: 'title_ar', labelKey: 'field.title', kind: 'text', inList: true, required: true },
    { name: 'description_ar', labelKey: 'field.description', kind: 'text' },
    // Where the child started and where the plan is aiming. The progress the
    // family sees is measured between these two, so a goal without them has
    // a percentage with nothing to be a percentage OF.
    { name: 'baseline_pct', labelKey: 'field.baseline', kind: 'number', ltr: true, inList: true },
    { name: 'target_pct', labelKey: 'field.target', kind: 'number', ltr: true, inList: true },
    { name: 'status', labelKey: 'field.status', kind: 'select', options: GOAL_STATUS },
    { name: 'sort_order', labelKey: 'field.order', kind: 'number', ltr: true },
  ],
};

export const MEASUREMENTS_SPEC: ResourceSpec = {
  resource: 'measurements',
  titleKey: 'plans.measurements',
  subKey: 'plans.measurementsSub',
  idColumn: 'measurement_id',
  viewPermission: 'GOAL.MEASURE',
  writePermission: 'GOAL.MEASURE',
  fields: [
    { name: 'goal_id', labelKey: 'field.goal', kind: 'ref', ref: { resource: 'goals', idColumn: 'goal_id', labelColumn: 'title_ar' }, ltr: true, inList: true, required: true },
    { name: 'measured_on', labelKey: 'field.measuredOn', kind: 'date', ltr: true, inList: true, required: true },
    { name: 'value_pct', labelKey: 'field.valuePct', kind: 'number', ltr: true, inList: true, required: true },
    { name: 'trials_cnt', labelKey: 'field.trials', kind: 'number', ltr: true, inList: true },
    // The session it was taken in, when it was taken in one. Optional: a
    // measurement from an observation outside a session is still a
    // measurement.
    { name: 'session_id', labelKey: 'field.session', kind: 'number', ltr: true },
    { name: 'note_ar', labelKey: 'field.note', kind: 'text' },
  ],
};

export const CHILD_ACTIVITIES_SPEC: ResourceSpec = {
  resource: 'child-activities',
  titleKey: 'plans.homeProgramme',
  subKey: 'plans.homeProgrammeSub',
  idColumn: 'child_activity_id',
  viewPermission: 'PLAN.MANAGE',
  writePermission: 'PLAN.MANAGE',
  fields: [
    { name: 'child_id', labelKey: 'field.child', kind: 'ref', ref: { resource: 'children', idColumn: 'child_id', labelColumn: 'full_name_ar' }, ltr: true, inList: true, required: true },
    { name: 'activity_id', labelKey: 'field.activity', kind: 'ref', ref: { resource: 'activity-library', idColumn: 'activity_id', labelColumn: 'title_ar' }, ltr: true, inList: true, required: true },
    { name: 'plan_id', labelKey: 'field.plan', kind: 'number', ltr: true },
    { name: 'goal_id', labelKey: 'field.goal', kind: 'number', ltr: true },
    { name: 'times_per_week', labelKey: 'field.timesPerWeek', kind: 'number', ltr: true, inList: true },
    { name: 'minutes_each', labelKey: 'field.minutesEach', kind: 'number', ltr: true, inList: true },
    { name: 'instructions_ar', labelKey: 'field.instructions', kind: 'text' },
    { name: 'start_date', labelKey: 'field.from', kind: 'date', ltr: true },
    { name: 'end_date', labelKey: 'field.to', kind: 'date', ltr: true },
  ],
};

/**
 * The satisfaction survey the centre asks families.
 *
 * The QUESTION TEXT lives here as data, not in Angular, and that is not an
 * exception to "no UI text outside translation files": an error code is a
 * fixed vocabulary the front end words, while this is content the CENTRE
 * writes and changes without a release. A question compiled into the app
 * cannot be changed by the person who owns the question.
 *
 * `trigger_kind` and its partner are constrained in pairs by ck_nps_shape:
 * PERIOD needs period_days and no action, ACTION needs an action and no
 * period. The form offers both and the database refuses a mismatch - a rule
 * that lives there, and a refusal this screen shows rather than restates.
 */
const NPS_AUDIENCE = [
  { value: 'GUARDIAN', labelKey: 'nps.audience.GUARDIAN' },
  { value: 'STAFF', labelKey: 'nps.audience.STAFF' },
  { value: 'ALL', labelKey: 'nps.audience.ALL' },
];

const NPS_TRIGGER = [
  { value: 'ACTION', labelKey: 'nps.trigger.ACTION' },
  { value: 'PERIOD', labelKey: 'nps.trigger.PERIOD' },
];

/**
 * The centre's standing questions, offered in the code box - NOT the whole
 * set of codes it may use.
 *
 * These are the purposes that come back: one per audience and moment the
 * survey is asked at. They are offered so they are spelled the same way every
 * time, because `uq_nps_code` makes PARENT-VISIT and PARENT_VISIT two surveys
 * and the results screen then reports one question as two.
 *
 * WHAT IS NOT HERE, and why the box is a `combo` and not a `select`: a survey
 * raised for one occasion - a release, an outage, an apology - carries a code
 * nobody could have listed in advance, and it is used once. A closed list was
 * shipped here first and it made exactly that survey impossible to create:
 * every code on it is already taken by the standing survey that owns it.
 *
 * Adding a purpose here is a line and a label. Asking about an occasion needs
 * nothing from this file at all.
 */
const NPS_CODE = [
  { value: 'PARENT_SESSION', labelKey: 'nps.code.PARENT_SESSION' },
  { value: 'PARENT_REPORT', labelKey: 'nps.code.PARENT_REPORT' },
  { value: 'PARENT_INVOICE', labelKey: 'nps.code.PARENT_INVOICE' },
  { value: 'PARENT_WELCOME', labelKey: 'nps.code.PARENT_WELCOME' },
  { value: 'PARENT_PERIODIC', labelKey: 'nps.code.PARENT_PERIODIC' },
  { value: 'STAFF_PERIODIC', labelKey: 'nps.code.STAFF_PERIODIC' },
  { value: 'CENTER_PERIODIC', labelKey: 'nps.code.CENTER_PERIODIC' },
];

const NPS_ACTION = [
  { value: 'SESSION_COMPLETED', labelKey: 'nps.action.SESSION_COMPLETED' },
  { value: 'REPORT_PUBLISHED', labelKey: 'nps.action.REPORT_PUBLISHED' },
  { value: 'INVOICE_PAID', labelKey: 'nps.action.INVOICE_PAID' },
  { value: 'FIRST_LOGIN', labelKey: 'nps.action.FIRST_LOGIN' },
];

export const NPS_SURVEYS_SPEC: ResourceSpec = {
  resource: 'nps-surveys',
  titleKey: 'nps.surveys',
  subKey: 'nps.surveysSub',
  idColumn: 'survey_id',
  viewPermission: 'NPS.MANAGE',
  writePermission: 'NPS.MANAGE',
  searchable: true,
  searchKey: 'search.nps-surveys',
  fields: [
    { name: 'code', labelKey: 'field.code', kind: 'combo', options: NPS_CODE, ltr: true, inList: true, required: true },
    { name: 'name_ar', labelKey: 'field.name', kind: 'text', inList: true, required: true },
    { name: 'question_ar', labelKey: 'nps.question', kind: 'text', inList: true, required: true },
    { name: 'followup_question_ar', labelKey: 'nps.followup', kind: 'text' },
    { name: 'audience', labelKey: 'nps.audienceField', kind: 'select', options: NPS_AUDIENCE, inList: true },
    { name: 'trigger_kind', labelKey: 'nps.triggerField', kind: 'select', options: NPS_TRIGGER, inList: true },
    // One or the other, never both - ck_nps_shape refuses a row that names
    // an event and a period together, and refuses one that names neither.
    {
      name: 'action_code', labelKey: 'nps.actionField', kind: 'select',
      options: NPS_ACTION, showWhen: { field: 'trigger_kind', equals: ['ACTION'] },
    },
    {
      name: 'period_days', labelKey: 'nps.periodDays', kind: 'number', ltr: true,
      showWhen: { field: 'trigger_kind', equals: ['PERIOD'] },
    },
    // How long before the same person is asked again. Without it one family
    // is asked after every session they attend.
    { name: 'cooldown_days', labelKey: 'nps.cooldown', kind: 'number', ltr: true },
    { name: 'starts_on', labelKey: 'field.from', kind: 'date', ltr: true },
    { name: 'ends_on', labelKey: 'field.to', kind: 'date', ltr: true },
  ],
};

export const GUARDIANS_SPEC: ResourceSpec = {
  resource: 'guardians',
  titleKey: 'nav.guardians',
  subKey: 'guardians.sub',
  idColumn: 'guardian_id',
  viewPermission: 'GUARDIAN.MANAGE',
  writePermission: 'GUARDIAN.MANAGE',
  searchable: true,
  searchKey: 'search.guardians',
  fields: [
    { name: 'full_name_ar', labelKey: 'field.fullName', kind: 'text', inList: true, required: true },
    { name: 'mobile', labelKey: 'field.mobile', kind: 'text', ltr: true, inList: true },
    { name: 'email', labelKey: 'field.email', kind: 'text', ltr: true },
    { name: 'city', labelKey: 'field.city', kind: 'text' },
    { name: 'relationship', labelKey: 'field.relationship', kind: 'select', options: [
      { value: '', labelKey: 'guardian.unspecified' },
      { value: 'الأب', labelKey: 'relationship.FATHER' },
      { value: 'الأم', labelKey: 'relationship.MOTHER' },
      { value: 'وليّ أمر', labelKey: 'relationship.GUARDIAN' },
    ] },
    { name: 'national_id', labelKey: 'field.nationalId', kind: 'text', ltr: true },
  ],
};

/**
 * The public site's content.
 *
 * WHAT MAKES THESE FOUR DIFFERENT from every spec above: the words end up
 * on the open internet, not on a screen inside the centre. So they carry a
 * `status` field the editor can change, and the change is refused by the
 * database - a trigger checks SITE.PUBLISH, and a CHECK constraint makes a
 * published testimonial or photograph without a recorded consent impossible
 * to write at all.
 *
 * `writePermission` is SITE.EDIT and not SITE.PUBLISH. It decides what this
 * screen DRAWS, and drawing is all it decides: somebody who may edit but not
 * publish gets the form, tries to publish, and is refused by the server. That
 * is the right way round. A screen that hid the control would be enforcing a
 * permission in the one place this project says never to enforce one.
 */
const SITE_ICON = [
  { value: 'i1', labelKey: 'site.icon1' },
  { value: 'i2', labelKey: 'site.icon2' },
  { value: 'i3', labelKey: 'site.icon3' },
  { value: 'i4', labelKey: 'site.icon4' },
  { value: 'i5', labelKey: 'site.icon5' },
  { value: 'i6', labelKey: 'site.icon6' },
  { value: 'i7', labelKey: 'site.icon7' },
  { value: 'i8', labelKey: 'site.icon8' },
];

const SITE_STATUS = [
  { value: 'DRAFT', labelKey: 'site.status.DRAFT' },
  { value: 'PUBLISHED', labelKey: 'site.status.PUBLISHED' },
];

export const SITE_CONTACT_SPEC: ResourceSpec = {
  resource: 'site-contact',
  titleKey: 'site.contact',
  subKey: 'site.contactSub',
  idColumn: 'contact_id',
  viewPermission: 'SITE.EDIT',
  writePermission: 'SITE.EDIT',
  statusColumn: 'status',
  statusPrefix: 'site.status.',
  fields: [
    // Latin and left to right: a phone number is dialled, not read as prose.
    { name: 'phone', labelKey: 'field.mobile', kind: 'text', ltr: true, inList: true },
    // The fixed line, beside the mobile rather than instead of it. The row
    // the centre saved has a Cairo landline in `phone` and the mobile in
    // `whatsapp`, because there was only one field and the last thing typed
    // won. Which number is the main one is theirs to say.
    { name: 'landline', labelKey: 'site.landline', kind: 'text', ltr: true },
    { name: 'whatsapp', labelKey: 'site.whatsapp', kind: 'text', ltr: true },
    { name: 'email', labelKey: 'field.email', kind: 'text', ltr: true },
    { name: 'address_ar', labelKey: 'site.addressAr', kind: 'text', inList: true },
    // Written by hand, never translated from the Arabic: a translated street
    // name is a street name that does not find the building.
    { name: 'address_en', labelKey: 'site.addressEn', kind: 'text', ltr: true },
    // A link that OPENS a map application. Never an iframe: an embedded map
    // is a third party watching every visitor to a page about children's
    // therapy.
    { name: 'map_url', labelKey: 'site.mapUrl', kind: 'text', ltr: true },
    // Directions, one instruction per line - hence a textarea. Three lines
    // of this were literal text in site/index.html, which is text nobody at
    // the centre could correct.
    { name: 'arrival_ar', labelKey: 'site.arrivalAr', kind: 'textarea' },
    { name: 'arrival_en', labelKey: 'site.arrivalEn', kind: 'textarea', ltr: true },
    { name: 'hours_ar', labelKey: 'site.hours', kind: 'text' },
    { name: 'hours_en', labelKey: 'site.hoursEn', kind: 'text', ltr: true },
    // The weekend here is Friday and Saturday. It is editable because it is a
    // parameter, but whoever fills it in should not have to think about it.
    { name: 'weekend_ar', labelKey: 'site.weekend', kind: 'text' },
    { name: 'weekend_en', labelKey: 'site.weekendEn', kind: 'text', ltr: true },
    { name: 'status', labelKey: 'field.status', kind: 'select', options: SITE_STATUS, editOnly: true },
  ],
};

/**
 * The page's own words - headings, menu, footer, the accessibility
 * strings - keyed by the data-i18n attribute already on each element.
 *
 * SEARCHABLE, because eighty-two rows is a list nobody scrolls. The key
 * is how somebody finds "the sentence under the hero": they know where it
 * is on the page long before they know what it says.
 *
 * text_key IS SHOWN AND NOT EDITED. It is a position in the page rather
 * than a value - renaming one does not move a sentence, it orphans it:
 * the old key goes unanswered and falls back to what is written in
 * index.html, and the new key matches no element at all. The service
 * refuses the column on update; this keeps the form honest about that.
 *
 * ⚠ THE `svc.*` KEYS HAVE AN EXPIRY DATE, and it is not today.
 *
 * Sixteen of these rows are the eight service cards written into the page.
 * They are here because hbh.site_services is EMPTY, so nothing else answers
 * for those words and editing them works exactly as it appears to.
 *
 * The day somebody seeds the catalogue, the site draws its service cards
 * from hbh.services instead - and these sixteen rows become text nobody
 * reads. An editor will change one, publish, see no difference on the page,
 * and have nothing to tell them why. That is the failure this table was
 * designed to avoid everywhere else: one sentence, one source.
 *
 * So when site_services gains its first row, these sixteen are archived in
 * the same change. Written here because this is the screen somebody will be
 * looking at when it stops making sense.
 *
 * WHAT IS ABSENT: is_locked. The six live-streaming statements carry it,
 * and no screen may clear it - hbh.guard_site_text_locked refuses the
 * edit and the service does not accept the column. A row that cannot be
 * reworded still shows its words, because reading what the page says
 * about recording is exactly what an administrator should be able to do.
 */
export const SITE_TEXTS_SPEC: ResourceSpec = {
  resource: 'site-texts',
  titleKey: 'site.texts',
  subKey: 'site.textsSub',
  idColumn: 'text_id',
  viewPermission: 'SITE.EDIT',
  writePermission: 'SITE.EDIT',
  searchable: true,
  searchKey: 'search.site-texts',
  statusColumn: 'status',
  statusPrefix: 'site.status.',
  fields: [
    { name: 'text_key', labelKey: 'site.textKey', kind: 'text', ltr: true, inList: true, required: true },
    { name: 'text_ar', labelKey: 'site.textAr', kind: 'textarea', inList: true, required: true },
    // Optional, and it stays optional. The owner hid the language switch
    // on 2026-09-10 and the page is Arabic-only today; the English
    // dictionary is untouched behind one attribute. A required field here
    // would be filled with a copy of the Arabic to get past the form, and
    // the site would then show Arabic to an English reader while claiming
    // to be translated.
    { name: 'text_en', labelKey: 'site.textEn', kind: 'textarea', ltr: true },
    { name: 'status', labelKey: 'field.status', kind: 'select', options: SITE_STATUS, editOnly: true },
  ],
};

export const SITE_FAQ_SPEC: ResourceSpec = {
  resource: 'site-faq',
  titleKey: 'site.faq',
  subKey: 'site.faqSub',
  idColumn: 'faq_id',
  viewPermission: 'SITE.EDIT',
  writePermission: 'SITE.EDIT',
  statusColumn: 'status',
  statusPrefix: 'site.status.',
  fields: [
    { name: 'question_ar', labelKey: 'site.question', kind: 'text', inList: true, required: true },
    { name: 'answer_ar', labelKey: 'site.answer', kind: 'text', required: true },
    // English is optional everywhere and must stay optional. The site keeps
    // the Arabic for any key with no translation, so a row without English
    // degrades to correct Arabic - while a required field would be filled
    // with a copy of the Arabic to get past the form.
    { name: 'question_en', labelKey: 'site.questionEn', kind: 'text', ltr: true },
    { name: 'answer_en', labelKey: 'site.answerEn', kind: 'text', ltr: true },
    // Explicit, never alphabetical: the order of questions is an editorial
    // decision, and Arabic collation ordering shifts under you when the
    // collation changes.
    { name: 'sort_order', labelKey: 'site.order', kind: 'number', ltr: true, inList: true },
    { name: 'status', labelKey: 'field.status', kind: 'select', options: SITE_STATUS, inList: true, editOnly: true },
  ],
};

export const SITE_TEAM_SPEC: ResourceSpec = {
  resource: 'site-team',
  titleKey: 'site.team',
  subKey: 'site.teamSub',
  idColumn: 'member_id',
  viewPermission: 'SITE.EDIT',
  writePermission: 'SITE.EDIT',
  statusColumn: 'status',
  statusPrefix: 'site.status.',
  fields: [
    { name: 'name_ar', labelKey: 'field.fullName', kind: 'text', inList: true, required: true },
    { name: 'role_ar', labelKey: 'site.role', kind: 'text', inList: true, required: true },
    { name: 'name_en', labelKey: 'site.nameEn', kind: 'text', ltr: true },
    { name: 'role_en', labelKey: 'site.roleEn', kind: 'text', ltr: true },
    { name: 'sort_order', labelKey: 'site.order', kind: 'number', ltr: true },
    { name: 'status', labelKey: 'field.status', kind: 'select', options: SITE_STATUS, inList: true, editOnly: true },
  ],
};

export const SITE_REVIEWS_SPEC: ResourceSpec = {
  resource: 'site-reviews',
  titleKey: 'site.reviews',
  subKey: 'site.reviewsSub',
  idColumn: 'review_id',
  viewPermission: 'SITE.EDIT',
  writePermission: 'SITE.EDIT',
  statusColumn: 'status',
  statusPrefix: 'site.status.',
  fields: [
    // FREE TEXT, and the label says whose choice it is. It must never be
    // derived from the guardian's name in the system: "أم يوسف" is not
    // anonymous to anybody who knows the family, and a testimonial about a
    // child's progress beside anything that identifies them tells the
    // neighbourhood that the child attends a therapy centre.
    { name: 'display_name', labelKey: 'site.displayName', kind: 'text', inList: true, required: true },
    { name: 'body_ar', labelKey: 'site.reviewBody', kind: 'text', required: true },
    { name: 'body_en', labelKey: 'site.reviewBodyEn', kind: 'text', ltr: true },
    // Which family said it. Never published - the exporter writes the chosen
    // name and the words, nothing else - but recorded so the consent is
    // attributable and so a withdrawal later finds this row.
    { name: 'guardian_id', labelKey: 'site.guardian', kind: 'number', ltr: true },
    { name: 'sort_order', labelKey: 'site.order', kind: 'number', ltr: true },
    { name: 'status', labelKey: 'field.status', kind: 'select', options: SITE_STATUS, inList: true, editOnly: true },
  ],
};

/**
 * The site's services - marketing text for a row of the booking catalogue.
 *
 * `service_id` is a number field and not a picker, which is a gap worth
 * naming rather than hiding: whoever fills it needs the catalogue open
 * beside them. It is settable on creation only - moving a description from
 * one service to another is not an edit, it is a different description.
 *
 * THE SITE ADVERTISES EIGHT SERVICES AND THE CATALOGUE HOLDS THREE. Six of
 * them cannot be booked by the system that runs the centre. This screen
 * makes that visible instead of letting a second list paper over it: a
 * service with no catalogue row simply cannot be described here, and the
 * fix is to add it to the catalogue first.
 */
export const SITE_SERVICES_SPEC: ResourceSpec = {
  resource: 'site-services',
  titleKey: 'site.services',
  subKey: 'site.servicesSub',
  idColumn: 'site_service_id',
  viewPermission: 'SITE.EDIT',
  writePermission: 'SITE.EDIT',
  statusColumn: 'status',
  statusPrefix: 'site.status.',
  fields: [
    { name: 'service_id', labelKey: 'site.serviceId', kind: 'number', ltr: true, inList: true, required: true },
    { name: 'blurb_ar', labelKey: 'site.blurb', kind: 'text', inList: true, required: true },
    { name: 'blurb_en', labelKey: 'site.blurbEn', kind: 'text', ltr: true },
    { name: 'icon_key', labelKey: 'site.icon', kind: 'select', options: SITE_ICON },
    { name: 'sort_order', labelKey: 'site.order', kind: 'number', ltr: true },
    { name: 'status', labelKey: 'field.status', kind: 'select', options: SITE_STATUS, inList: true, editOnly: true },
  ],
};

/**
 * The twelve codes in ck_ss_code (migration 0040, widened by 0106).
 *
 * These are element ids in site/index.html, and they are shown through the
 * bundle rather than raw because "how" and "why" name nothing to somebody
 * reading an Arabic console. The VALUE is still the code - it is what the
 * table stores and what site/app.js looks up with getElementById.
 *
 * A code missing from this list still renders: `display` falls back to the
 * raw value when no option matches, so a thirteenth section added to the
 * constraint reads as "cta" rather than vanishing from its own row.
 */
const SITE_SECTION_CODE = [
  { value: 'home', labelKey: 'site.section.home' },
  { value: 'services', labelKey: 'site.section.services' },
  { value: 'programs', labelKey: 'site.section.programs' },
  { value: 'how', labelKey: 'site.section.how' },
  { value: 'why', labelKey: 'site.section.why' },
  { value: 'live', labelKey: 'site.section.live' },
  { value: 'portal', labelKey: 'site.section.portal' },
  { value: 'team', labelKey: 'site.section.team' },
  { value: 'reviews', labelKey: 'site.section.reviews' },
  { value: 'cta', labelKey: 'site.section.cta' },
  { value: 'contact', labelKey: 'site.section.contact' },
  { value: 'faq', labelKey: 'site.section.faq' },
];

/**
 * Which blocks of the public page are drawn at all.
 *
 * Until this existed, hiding a section meant a hand-written UPDATE in psql,
 * or - for the call-to-action band - an attribute in index.html that no
 * screen could see and no audit line recorded.
 *
 * `writePermission` IS SITE.PUBLISH HERE, and only here. The note above
 * SITE_CONTACT_SPEC says a site screen draws on SITE.EDIT and lets the
 * server refuse the publish, and that is right when a row has words to edit
 * and a status to publish: an editor gets real work done and is refused at
 * the last step. This row has NOTHING to edit. Its one writable column is
 * the flag, and trg_site_sections_publish refuses every change to it
 * without SITE.PUBLISH - so an editor would be handed a form in which no
 * possible input can succeed. That is the defect recorded above `editOnly`,
 * not an exception to the note. Naming the permission this screen's only
 * action actually needs is not enforcing it; the trigger still does that,
 * and still would if this line said otherwise.
 */
export const SITE_SECTIONS_SPEC: ResourceSpec = {
  resource: 'site-sections',
  titleKey: 'site.sections',
  subKey: 'site.sectionsSub',
  idColumn: 'section_id',
  viewPermission: 'SITE.EDIT',
  writePermission: 'SITE.PUBLISH',
  fixedRows: true,
  // No statusColumn: the table has none, and visibility is not a publish
  // state. A section that is showing is not "published" - its CONTENT has
  // its own status, on its own table, and conflating the two would let the
  // badge claim a draft testimonial is live because the reviews block is.
  fields: [
    { name: 'code', labelKey: 'site.sectionCode', kind: 'select',
      options: SITE_SECTION_CODE, inList: true, readOnly: true },
    { name: 'visible_flg', labelKey: 'site.visible', kind: 'switch', inList: true },
  ],
};

export const SITE_PROGRAMS_SPEC: ResourceSpec = {
  resource: 'site-programs',
  titleKey: 'site.programs',
  subKey: 'site.programsSub',
  idColumn: 'program_id',
  viewPermission: 'SITE.EDIT',
  writePermission: 'SITE.EDIT',
  statusColumn: 'status',
  statusPrefix: 'site.status.',
  fields: [
    { name: 'title_ar', labelKey: 'field.title', kind: 'text', inList: true, required: true },
    { name: 'desc_ar', labelKey: 'site.blurb', kind: 'text' },
    { name: 'detail_ar', labelKey: 'site.detail', kind: 'text' },
    { name: 'title_en', labelKey: 'site.titleEn', kind: 'text', ltr: true },
    { name: 'desc_en', labelKey: 'site.blurbEn', kind: 'text', ltr: true },
    { name: 'detail_en', labelKey: 'site.detailEn', kind: 'text', ltr: true },
    { name: 'icon_key', labelKey: 'site.icon', kind: 'select', options: SITE_ICON },
    { name: 'sort_order', labelKey: 'site.order', kind: 'number', ltr: true },
    { name: 'status', labelKey: 'field.status', kind: 'select', options: SITE_STATUS, inList: true, editOnly: true },
  ],
};

/**
 * One qualification claim per row.
 *
 * `member_id` is typed rather than picked, same gap as the services screen.
 * The rows carry no publish state of their own: they are part of the member
 * they belong to, and a qualification published while its owner is a draft
 * would be a claim about somebody the page does not show.
 */
export const SITE_TEAM_FACTS_SPEC: ResourceSpec = {
  resource: 'site-team-facts',
  titleKey: 'site.facts',
  subKey: 'site.factsSub',
  idColumn: 'fact_id',
  viewPermission: 'SITE.EDIT',
  writePermission: 'SITE.EDIT',
  fields: [
    { name: 'member_id', labelKey: 'site.memberId', kind: 'number', ltr: true, inList: true, required: true },
    { name: 'text_ar', labelKey: 'site.fact', kind: 'text', inList: true, required: true },
    { name: 'text_en', labelKey: 'site.factEn', kind: 'text', ltr: true },
    { name: 'sort_order', labelKey: 'site.order', kind: 'number', ltr: true },
  ],
};

/**
 * Scanned certificates on the public site.
 *
 * TWO SWITCHES, and they are not the same switch. Consent means the person
 * agreed to have THIS DOCUMENT published - agreeing to a photograph of your
 * face is not agreeing to a scan of a certificate. The redaction check means
 * somebody looked at the image and states it carries no national identity
 * number, no address and no telephone.
 *
 * Both are drawn as dates because that is what the service stores, and BOTH
 * ARE IGNORED ON THE WAY IN: the database stamps who and when from the
 * session. Typing a date here does not backdate anything, and the person
 * recorded is whoever is signed in - which is the point.
 *
 * The reason for two rather than one is a row we found today: a family
 * consented to publishing a testimonial, and the testimonial names their
 * child four times. Agreeing to publish is not an inspection of what is
 * published.
 */
export const SITE_CERTIFICATES_SPEC: ResourceSpec = {
  resource: 'site-team-certificates',
  titleKey: 'site.certificates',
  subKey: 'site.certificatesSub',
  idColumn: 'certificate_id',
  viewPermission: 'SITE.EDIT',
  writePermission: 'SITE.EDIT',
  statusColumn: 'status',
  statusPrefix: 'site.status.',
  fields: [
    { name: 'member_id', labelKey: 'site.memberId', kind: 'number', ltr: true, inList: true, required: true },
    // Changing this retracts the redaction check: a different image has
    // been looked at by nobody.
    { name: 'path', labelKey: 'site.certPath', kind: 'text', ltr: true, inList: true, required: true },
    // What the document IS, not whose it is. The heading above the card
    // already says whose, and repeating the name in every image's
    // description writes it into places read out of context.
    { name: 'caption_ar', labelKey: 'site.certCaption', kind: 'text', inList: true },
    { name: 'caption_en', labelKey: 'site.certCaptionEn', kind: 'text', ltr: true },
    { name: 'consent_given_at', labelKey: 'site.certConsent', kind: 'date', ltr: true },
    { name: 'redaction_checked_at', labelKey: 'site.certRedaction', kind: 'date', ltr: true },
    { name: 'sort_order', labelKey: 'site.order', kind: 'number', ltr: true },
    { name: 'status', labelKey: 'field.status', kind: 'select', options: SITE_STATUS, inList: true, editOnly: true },
  ],
};
