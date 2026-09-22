import { ArchiveSwitch } from '@hbh/shared/ui/archive-switch';
import { BillingLedger } from './billing-ledger';
import { BillingOverview } from './billing-overview';
import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute, RouterLink } from '@angular/router';
import {
  Observable, Subject, catchError, debounceTime, distinctUntilChanged, forkJoin,
  of, switchMap, map,
} from 'rxjs';

import { NgTemplateOutlet } from '@angular/common';
import { ModalDialog } from '@hbh/shared/a11y/modal-dialog';
import { FormatService } from '@hbh/shared/format/format.service';
import { HbhNumberPipe, HbhPluralPipe } from '@hbh/shared/format/format.pipes';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { OpsApi, Page, Row } from '../../core/api/ops-api';
import { readRefusal, refusalKey } from '../../core/api/ops-error';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { EmbeddedAction } from '../../core/ops/action-request';
import { DayApi, DayQuery, DeliveryMode, Slot } from '../../core/ops/day-api';
import { DrawerEntity, RESOURCE_OF } from '../../core/ops/record-drawer';
import { RecordDrawerService } from '../../core/ops/record-drawer.service';
import {
  ActionField, ActionOption, CreateAction, DayAction, DayContext, DaySpec,
  LOOKUP_SHAPE, LookupResource, readText,
} from '../../core/ops/day-spec';

/** The dialog that is open, if any: a row action or the screen's create. */
interface OpenAction {
  readonly action: DayAction | CreateAction;
  /** Null for create, which belongs to the screen and not to a row. */
  readonly row: Row | null;
  readonly fields: readonly ActionField[];
}

/**
 * One screen for the five operational reads.
 *
 * Appointments, sessions, reports, invoices and requests are all the same
 * shape of page - a window, some filters, rows the centre acts on - and they
 * differ in their columns and their verbs. Both of those are written in
 * day-spec.ts, so this file is the behaviour and holds no knowledge of any
 * one of the five.
 *
 * The rule it exists to keep: a status is never edited as a field. Every move
 * goes through the service's own verb, which goes through the state machine
 * in the schema. A screen that PATCHed a status column directly would write
 * a row the history table never saw.
 */
@Component({
  selector: 'hbh-day-screen',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [ArchiveSwitch, BillingLedger, BillingOverview, NgTemplateOutlet, RouterLink, Icon, TranslatePipe, HbhNumberPipe, HbhPluralPipe, Skeleton, EmptyState, ErrorNote, ModalDialog],
  templateUrl: './day-screen.html',
  styleUrl: './day-screen.css',
})
export class DayScreen {
  private readonly api = inject(DayApi);
  private readonly crud = inject(OpsApi);
  private readonly route = inject(ActivatedRoute);
  private readonly destroyRef = inject(DestroyRef);
  private readonly toast = inject(ToastService);
  private readonly i18n = inject(I18nService);
  private readonly drawer = inject(RecordDrawerService);
  protected readonly auth = inject(OpsAuthService);
  protected readonly format = inject(FormatService);

  protected readonly spec: DaySpec = this.route.snapshot.data['spec'] as DaySpec;

  /**
   * Set when this instance exists only to draw ONE action's dialog for a
   * caller elsewhere (ActionDialogHost, through ActionDialogService). No
   * list, no filters, no reads of its own: the dialog opens at once on the
   * row it was given and reports back through `onClose`. The dialog's
   * fields, checks and submit are the same code paths as on the list -
   * that is the whole reason for embedding this component rather than
   * writing a second dialog.
   */
  protected readonly embedded: EmbeddedAction | null =
    (this.route.snapshot.data['embedded'] as EmbeddedAction | undefined) ?? null;
  /** True between a successful confirm and the close that follows it. */
  private completed = false;

  /**
   * "My day" by default for an account that has a day of its own and no
   * diary of the centre's: a therapist holds SESSION.START and not
   * APPOINTMENT.BOOK, and /appointments without `?view=` used to hand
   * them the whole centre's diary to search their six rows in. The
   * default narrows and never widens - `?view=all` is still honoured, and
   * reception, who books, keeps the centre's diary.
   */
  private readonly mineByDefault: boolean =
    this.route.snapshot.queryParamMap.get('view') === null
    && this.spec.resource === 'appointments'
    && !this.auth.can('APPOINTMENT.BOOK')
    && this.auth.me()?.therapistId !== undefined;
  private readonly viewMine: boolean =
    this.route.snapshot.queryParamMap.get('view') === 'mine' || this.mineByDefault;

  /**
   * The heading, which the ROUTE may override.
   *
   * One spec can be read by two audiences. APPOINTMENTS_SPEC serves
   * reception on /appointments and the clinician on /my-day, and the
   * spec's own subtitle - "حجز وتأكيد وإلغاء" - names three verbs a
   * therapist does not hold. A heading that promises what the screen
   * will not offer is worse than a generic one.
   *
   * An override, not a second spec: the columns, the actions and the
   * state machine are the same screen and must stay one definition.
   */
  protected readonly headTitleKey: string =
    this.viewMine ? 'nav.myDay'
    : (this.route.snapshot.data['titleKey'] as string | undefined) ?? this.spec.titleKey;
  protected readonly headSubKey: string =
    this.viewMine ? 'myDay.sub'
    : (this.route.snapshot.data['subKey'] as string | undefined) ?? this.spec.subKey;

  /**
   * Overridable for the same reason the heading is: one spec, two audiences.
   * An empty PERSONAL day says something different from an empty centre
   * day - "no appointments today" on the clinician's view reads as "the
   * centre is closed", when a colleague may be busy.
   */
  protected readonly emptyKey: string =
    this.viewMine ? 'myDay.empty'
    : (this.route.snapshot.data['emptyKey'] as string | undefined) ?? this.spec.emptyKey;
  protected readonly emptyNoteKey: string =
    this.viewMine ? 'myDay.emptyNote'
    : (this.route.snapshot.data['emptyNoteKey'] as string | undefined) ?? this.spec.emptyNoteKey;

  private readonly ctx: DayContext = { format: this.format, i18n: this.i18n };

  protected readonly rows = signal<readonly Row[]>([]);
  protected readonly total = signal(0);
  protected readonly limit = signal(0);
  protected readonly pageSize = signal(10);
  protected changePageSize(value: string): void {
    const size=Number(value); if (![10,20,30,50].includes(size)) return;
    this.pageSize.set(size); this.page.set(1); this.load();
  }
  protected readonly page = signal(1);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);

  /**
   * A diary opens on a day; a ledger opens on everything.
   *
   * The day is the CENTRE's day, read from its clock. Taking it from the
   * browser would open the diary on tomorrow every evening after nine in
   * Cairo, which is exactly the hour reception is still working.
   */
  protected readonly day = signal(
    this.spec.window === 'diary'
      ? (/^\d{4}-\d{2}-\d{2}$/.test(this.route.snapshot.queryParamMap.get('date') ?? '')
        ? this.route.snapshot.queryParamMap.get('date')! : this.format.today()) : '');
  protected readonly from = signal('');
  protected readonly to = signal('');
  /**
   * Seeded from the address, because something linked here already filtered.
   *
   * The dashboard tiles count rows under a filter and then link to this
   * screen carrying it. Without reading the parameter the link would show a
   * count of two and open a list of forty - the screen quietly disagreeing
   * with the number that sent somebody to it.
   *
   * A value the spec does not declare is ignored rather than sent on: the
   * filter comes off the address bar, and a status this resource has never
   * heard of would be a 400 for the person who typed it.
   */
  protected readonly status = signal(this.seed('status', this.spec.statusFilter));
  protected readonly kind = signal(this.seed('kind', this.spec.kindFilter ?? []));
  protected readonly showArchived = signal(false);

  private seed(name: string, allowed: readonly string[]): string {
    const value = this.route.snapshot.queryParamMap.get(name) ?? '';
    return allowed.includes(value) ? value : '';
  }

  // ---- the open dialog ----
  protected readonly open = signal<OpenAction | null>(null);
  protected readonly values = signal<Record<string, string>>({});
  protected readonly saving = signal(false);
  protected readonly formError = signal('');
  protected readonly badField = signal<string | null>(null);

  /** Options loaded from the CRUD lists, for the booking form. */
  protected readonly lookups = signal<Record<string, readonly ActionOption[]>>({});
  protected readonly lookupsLoading = signal(false);

  /**
   * The answer to the last slot check, or null.
   *
   * Kept apart from formError: a refused slot is not an error, it is an
   * answer, and it arrives as a 200. Showing it in the red error line would
   * say the screen failed when nothing did.
   */
  protected readonly slotCheck = signal<{ ok: boolean; reason: string } | null>(null);
  protected readonly checking = signal(false);

  /**
   * The free windows for the chosen service, therapist and day.
   *
   * THE SCREEN USED TO HAVE ONLY THE OPPOSITE QUESTION. A receptionist typed
   * two instants and pressed "check", and finding the one free hour in a
   * busy therapist's day meant being refused over and over - a guess with a
   * validator attached.
   *
   * These come from the service, which runs every candidate through the same
   * hbh.validate_slot the booking goes through, so nothing here can be
   * offered and then refused for the therapist or the room. The CHILD is not
   * part of the question - they are chosen after - so a family already
   * booked at that hour is still refused at confirm, with CHILD_BUSY.
   */
  protected readonly slots = signal<readonly Slot[]>([]);
  protected readonly slotsState = signal<'idle' | 'loading' | 'ready' | 'failed' | 'denied'>('idle');
  /** The day the slot list is for. Its own, so browsing it does not move the diary behind. */
  protected readonly slotDate = signal('');
  /** Which slot is currently filled into the form, by its start instant. */
  protected readonly pickedSlot = signal('');

  /** True while the therapist list is being narrowed to the chosen service. */
  protected readonly narrowing = signal(false);

  // ---- the child search ----
  //
  // A <select> held ONE PAGE of children. On a centre with nine hundred,
  // the seven hundred past it could not be chosen at all, and the control
  // gave no sign of it - a dropdown looks complete whether or not it is.
  //
  // The filtering is the SERVICE's (`?q=` over full_name_ar and child_no),
  // not a filter over rows already fetched. That is the whole point: what
  // can be found is what the policy lets this person see, rather than what
  // happened to fit in the first page.
  protected readonly childTerm = signal('');
  protected readonly childHits = signal<readonly Row[]>([]);
  protected readonly childState = signal<'idle' | 'short' | 'searching' | 'ready' | 'failed'>('idle');
  /** The chosen child's name, shown once the box is closed. */
  protected readonly childPicked = signal('');
  protected readonly childOpen = signal(false);
  /** Which hit the arrow keys are on, -1 for none. */
  protected readonly childActive = signal(-1);
  private readonly childTyped = new Subject<string>();
  /** Asked-for service; the pipeline keeps only the latest answer. */
  private readonly therapistsFor = new Subject<number>();
  private readonly slotsFor = new Subject<
    { therapistId: number; serviceId: number; date: string; mode: DeliveryMode }>();

  /**
   * How long each service runs, by service_id.
   *
   * Read from the services lookup rows the dialog already fetches, so the
   * end time can be derived instead of typed. A service with no duration
   * is NOT given a default here: inventing forty-five minutes for a
   * service somebody forgot to configure books the wrong length of
   * appointment and looks deliberate. The screen says the configuration
   * is missing and leaves the field to be filled by hand.
   */
  protected readonly serviceMinutes = signal<Record<string, number>>({});

  /** The end the chosen service implies for the start now in the form. */
  protected readonly derivedEnd = computed(() => {
    const start = this.values()['starts_at'] ?? '';
    const minutes = this.serviceMinutes()[this.values()['service_id'] ?? ''];
    if (!start || !minutes) {
      return '';
    }
    const at = new Date(`${start}:00`);
    if (Number.isNaN(at.getTime())) {
      return '';
    }
    at.setMinutes(at.getMinutes() + minutes);
    const pad = (n: number) => String(n).padStart(2, '0');
    return `${at.getFullYear()}-${pad(at.getMonth() + 1)}-${pad(at.getDate())}`
      + `T${pad(at.getHours())}:${pad(at.getMinutes())}`;
  });

  /** Minutes for the chosen service, or 0 when it has none configured. */
  protected readonly chosenMinutes = computed(
    () => this.serviceMinutes()[this.values()['service_id'] ?? ''] ?? 0);

  /**
   * The (service, therapist) combinations the centre can deliver.
   *
   * Loaded once when a dialog with a pair field opens. The value of an
   * option is "<service_id>:<therapist_id>" - a compound key, because the
   * control answers two questions and neither alone identifies a choice.
   */
  protected readonly pairs = signal<readonly ActionOption[]>([]);
  protected readonly pairsState = signal<'idle' | 'loading' | 'ready' | 'failed'>('idle');

  /** Which pair the two underlying fields currently amount to. */
  protected readonly pairValue = computed(() => {
    const s = this.values()['service_id'] ?? '';
    const t = this.values()['therapist_id'] ?? '';
    return s && t ? `${s}:${t}` : '';
  });

  private loadPairs(): void {
    this.pairs.set([]);
    this.pairsState.set('loading');
    this.api.servicePairs()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (rows) => {
          this.pairs.set(rows.map((row) => ({
            value: `${row['service_id']}:${row['therapist_id']}`,
            labelKey: `${row['service_name_ar']} — ${row['therapist_name_ar']}`,
          })));
          // The durations come with the pairs, so a manually typed start
          // still derives its end even when the services lookup is not
          // loaded (it is secondary now, and may never be opened).
          const minutes: Record<string, number> = { ...this.serviceMinutes() };
          for (const row of rows) {
            const value = Number(row['duration_min']);
            if (value > 0) {
              minutes[String(row['service_id'])] = value;
            }
          }
          this.serviceMinutes.set(minutes);
          this.pairsState.set('ready');
        },
        error: () => this.pairsState.set('failed'),
      });
  }

  /**
   * Takes one choice and answers two questions.
   *
   * It writes service_id and therapist_id directly rather than through
   * setValue for the service: setValue('service_id') kicks off the
   * narrowing, and the narrowing's own callback would then decide which
   * therapist to keep - racing the one just chosen here. Both are set
   * first, and the narrowing is asked afterwards, so it finds the
   * therapist already in place and leaves it alone.
   */
  protected setPair(name: string, raw: string): void {
    const [service, therapist] = raw.split(':');
    this.values.update((current) => ({
      ...current,
      // The control's OWN value too, not only the two it derives.
      //
      // Without it the confirm stayed disabled on a completely filled
      // form: the pair is a required field, and `canConfirm` asks whether
      // every required field holds something. The review block read
      // perfectly the whole time, because it reads service_id and
      // therapist_id - so the screen looked finished and refused to
      // submit, which is the worst shape a form can take.
      [name]: raw,
      service_id: service ?? '',
      therapist_id: therapist ?? '',
    }));
    this.slotCheck.set(null);
    this.pickedSlot.set('');
    this.slots.set([]);
    this.slotsState.set('idle');
    if (!service || !therapist) {
      return;
    }
    // Refreshes the (secondary) therapist dropdown for this service, and
    // asks for the free windows once it settles.
    this.loadTherapistsForService(service);
  }

  protected readonly pageCount = computed(() => {
    const size = this.limit();
    return size > 0 ? Math.max(1, Math.ceil(this.total() / size)) : 1;
  });
  protected readonly hasMorePages = computed(() => this.pageCount() > 1);

  /** The screen-level actions this account may use. */
  protected readonly creates = computed(
    () => (this.spec.create ?? []).filter((item) => this.auth.can(item.permission)));

  constructor() {
    if (this.embedded) {
      // Open on the given row, with the caller's pre-filled values laid over
      // the defaults the dialog computes. A pre-filled status is still a
      // select the person sees and can change before confirming.
      this.openDialog(this.embedded.action, this.embedded.row);
      const prefill = this.embedded.request.prefill;
      if (prefill) {
        this.values.update((current) => ({ ...current, ...prefill }));
      }
      // A picker that shows a name rather than a number reads its label
      // from the caller: the child's file already knows whose file it is.
      const childLabel = this.embedded.request.prefillLabels?.['child_id'];
      if (prefill?.['child_id'] && childLabel) {
        this.childPicked.set(childLabel);
        this.childTerm.set(childLabel);
      }
    } else {
      this.load();
      if (this.spec.window === 'diary') this.loadFilterOptions();
      // A row changed from the record drawer beside this list: the list is
      // read again so its badge agrees with the drawer. Only this resource;
      // the embedded instance above has no list to refresh.
      this.drawer.changed$
        .pipe(takeUntilDestroyed(this.destroyRef))
        .subscribe((target) => {
          if (RESOURCE_OF[target.entity] === this.spec.resource) {
            this.load();
          }
        });
    }

    /*
     * The child search, one pipeline.
     *
     * switchMap, not mergeMap: typing "أحمد" fires on several prefixes and
     * only the LAST answer is wanted. With mergeMap a slow reply to "أح"
     * can land after the reply to "أحمد" and overwrite it, so the list
     * disagrees with the box - the classic autocomplete defect, and one
     * that shows up only under a slow connection.
     *
     * Two characters minimum. A single letter matches most of a centre and
     * costs a query to say so.
     *
     * A FAILED SEARCH IS NOT AN EMPTY ONE. catchError maps to null rather
     * than an empty page, because "nobody by that name" and "we could not
     * ask" send a receptionist to two different places.
     */
    this.wireNarrowing();
    this.wireSlots();

    this.childTyped.pipe(
      debounceTime(250),
      distinctUntilChanged(),
      switchMap((term) => {
        const q = term.trim();
        if (q.length < 2) {
          return of<Page | null>({ rows: [], total: 0, limit: 0, offset: 0 });
        }
        this.childState.set('searching');
        return this.crud.list('children', { q, limit: 8 })
          .pipe(catchError(() => of<Page | null>(null)));
      }),
      takeUntilDestroyed(this.destroyRef),
    ).subscribe((page) => {
      if (!page) {
        this.childHits.set([]);
        this.childState.set('failed');
        return;
      }
      this.childHits.set(page.rows);
      this.childActive.set(-1);
      this.childState.set(
        this.childTerm().trim().length < 2 ? 'short' : 'ready');
    });
  }

  // =====================================================================
  // Reading
  // =====================================================================

  /**
   * MY day, when the route says so.
   *
   * /my-day and /appointments are the same screen on the same spec, and
   * that is right - the columns, the actions and the state machine are one
   * definition. What differed was only that nobody told this one whose day
   * it was, so a therapist opening it got the whole centre's diary and had
   * to find their six appointments by working the therapist dropdown.
   *
   * ASKED FOR BY NAME, not seeded as a filter value. The screen sends
   * `mine=1` and the SERVICE resolves which therapist that is, from the
   * session. An earlier attempt put the caller's own therapist_id into the
   * ordinary therapist filter, which reads the same on a good day and is
   * not the same thing: it makes the client the author of the word "my",
   * and it has nothing to say when the account has no therapist row - the
   * filter goes empty and an empty filter means the whole centre. A
   * personal screen that silently widens to everybody is the failure this
   * route was reported for.
   *
   * See store.OpsQuery.MineOnly: an account with no therapist profile, or
   * with a deactivated one, gets an empty day and never the centre's.
   */
  protected readonly isMyDay =
    this.route.snapshot.data['navKey'] === 'my-day' || this.viewMine;

  /**
   * A row somebody was sent to. The task inbox links here with `?focus=`
   * and the row is marked and scrolled into view once the list arrives -
   * display only; nothing is opened on the person's behalf.
   */
  protected readonly focusId = this.route.snapshot.queryParamMap.get('focus') ?? '';

  /**
   * Whether this account can have a personal day at all.
   *
   * Undefined therapistId is not zero and not "nobody": it is reception or
   * an administrator, who legitimately hold SESSION.START on /my-day's
   * route but are nobody's clinician. They are told so, rather than shown
   * a day that is not theirs.
   */
  protected readonly hasTherapistProfile =
    computed(() => this.auth.me()?.therapistId !== undefined);

  protected readonly therapistFilter = signal('');
  protected readonly roomFilter = signal('');
  protected readonly serviceFilter = signal('');
  protected readonly filterOptions = signal<Record<string, readonly ActionOption[]>>({});
  protected readonly filtersFailed = signal(false);
  protected loadFilterOptions(): void {
    this.filtersFailed.set(false);
    const names: LookupResource[] = this.spec.resource === 'appointments' ? ['therapists', 'rooms', 'services'] : ['therapists', 'rooms'];
    for (const name of names) this.crud.list(name, {limit: 100}).pipe(switchMap(first => {
      const count = Math.ceil(first.total / Math.max(1, first.limit));
      return (count > 1 ? forkJoin(Array.from({length: count - 1}, (_, n) => this.crud.list(name, {limit: 100, page: n + 2}))) : of([]))
        .pipe(map(rest => [first, ...rest].flatMap(p => p.rows)));
    }), takeUntilDestroyed(this.destroyRef)).subscribe({next: rows => {
      const shape = LOOKUP_SHAPE[name];
      this.filterOptions.update(old => ({...old, [name]: rows.map(row => ({value: String(row[shape.id]), labelKey: String(row[shape.label])}))}));
    }, error: () => this.filtersFailed.set(true)});
  }
  /**
   * The filters every read of this diary shares - the list, the counters
   * and the week.
   *
   * `mine` lives HERE rather than at each call site on purpose. The defect
   * this screen was reported for was not that a query was wrong; it was
   * that two queries behind one screen disagreed - the list asked for one
   * therapist's day and the attention counters asked for the centre's, so
   * the heading said one appointment was waiting and the list underneath
   * said there were none. Both were answering honestly. They had been
   * asked different questions.
   *
   * One place to write the scope is what stops them drifting apart again.
   */
  private diaryFilters(): DayQuery {
    return {mine: this.isMyDay || undefined,
      therapist_id: this.isMyDay ? undefined : Number(this.therapistFilter()) || undefined,
      room_id: Number(this.roomFilter()) || undefined,
      service_id: this.spec.resource === 'appointments' ? Number(this.serviceFilter()) || undefined : undefined};
  }
  protected readonly exporting = signal(false);
  protected readonly exportError = signal('');
  protected exportInvoices(): void {
    if (this.exporting()) return;
    this.exporting.set(true); this.exportError.set('');
    const query: DayQuery = {from: this.from() || undefined, to: this.to() || undefined, status: this.status() || undefined, limit: 100};
    this.api.list('invoices', query).pipe(switchMap(first => {
      const count = Math.ceil(first.total / Math.max(1, first.limit));
      return (count > 1 ? forkJoin(Array.from({length: count - 1}, (_, n) => this.api.list('invoices', {...query, page: n + 2}))) : of([]))
        .pipe(map(rest => [first, ...rest].flatMap(p => p.rows)));
    }), takeUntilDestroyed(this.destroyRef)).subscribe({next: rows => {this.downloadCSV(rows, 'invoices-filtered.csv'); this.exporting.set(false);},
      error: () => {this.exporting.set(false); this.exportError.set('billing.exportFailed');}});
  }
  protected readonly billingTab = signal('invoices');
  protected readonly appointmentAttention = signal<readonly Row[]>([]);
  protected readonly attentionFailed = signal(false);
  protected readonly attentionLoading = signal(false);
  private attentionVersion = 0;
  protected readonly pendingAppointments = computed(() => this.appointmentAttention().filter(r => r['status'] === 'BOOKED'));
  protected readonly appointmentConflicts = computed(() => {
    const active = this.appointmentAttention().filter(r => ['BOOKED','CONFIRMED','CHECKED_IN'].includes(String(r['status'])));
    const pairs: {first:Row;second:Row}[] = [];
    for(let i=0;i<active.length;i++)for(let j=i+1;j<active.length;j++){
      const a=active[i],b=active[j];
      const same=(key:string,id:string)=>{const x=a[key] as Row|undefined,y=b[key] as Row|undefined;return x?.[id]!=null&&x[id]===y?.[id]};
      if(new Date(String(a['starts_at']))<new Date(String(b['ends_at']))&&new Date(String(b['starts_at']))<new Date(String(a['ends_at']))&&(same('therapist','therapist_id')||same('room','room_id')))pairs.push({first:a,second:b});
    }return pairs;
  });
  protected appointmentName(row:Row):string{return String((row['child'] as Row|undefined)?.['full_name_ar']??'موعد');}
  private loadAppointmentAttention():void {
    const version=++this.attentionVersion;this.attentionLoading.set(true);this.attentionFailed.set(false);
    // ...diaryFilters() is the fix for the counter that disagreed with the
    // list. It was absent here and present everywhere else, so on /my-day
    // this one read counted every therapist's appointments and the list
    // beside it counted one therapist's.
    const query:DayQuery={...this.diaryFilters(),date:this.day(),limit:100};
    this.api.list('appointments',query).pipe(switchMap(first=>{
      const count=Math.ceil(first.total/Math.max(1,first.limit));
      return (count>1?forkJoin(Array.from({length:count-1},(_,n)=>this.api.list('appointments',{...query,page:n+2}))):of([])).pipe(map(rest=>[first,...rest].flatMap(p=>p.rows)));
    }),takeUntilDestroyed(this.destroyRef)).subscribe({next:rows=>{if(version!==this.attentionVersion)return;this.appointmentAttention.set(rows);this.attentionLoading.set(false)},error:()=>{if(version!==this.attentionVersion)return;this.attentionFailed.set(true);this.attentionLoading.set(false)}});
  }
  protected readonly bookingHours=Array.from({length:12},(_,i)=>i+9);
  protected bookHour(date:string,hour:number):void {
    const action=this.creates().find(a=>a.key==='book')??this.creates()[0];if(!action)return;
    this.startCreate(action);this.setValue('starts_at',date+'T'+String(hour).padStart(2,'0')+':00');this.setValue('ends_at',date+'T'+String(hour+1).padStart(2,'0')+':00');
    if(this.therapistFilter())this.setValue('therapist_id',this.therapistFilter());if(this.roomFilter())this.setValue('room_id',this.roomFilter());if(this.serviceFilter())this.setValue('service_id',this.serviceFilter());
  }
  protected readonly invoiceCounts = signal<Record<string, number | null>>({});
  private loadInvoiceCounts(): void {
    const from = this.from(), to = this.to();
    this.invoiceCounts.set({});
    for (const status of this.spec.statusFilter) {
      this.api.list('invoices', {status, from: from || undefined, to: to || undefined, limit: 1})
        .pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
          next: result => { if (from === this.from() && to === this.to()) this.invoiceCounts.update(value => ({...value, [status]: result.total})); },
          error: () => { if (from === this.from() && to === this.to()) this.invoiceCounts.update(value => ({...value, [status]: null})); },
        });
    }
  }
  protected readonly boardView = signal(false);
  protected readonly calendarView = signal(false);
  protected boardRows(status: string): readonly Row[] { return this.rows().filter(row => row['status'] === status); }
  protected toggleBoard(): void { this.boardView.update(value => !value); this.refilter(); }
  protected exportPage(): void {
    this.downloadCSV(this.rows(), this.spec.resource + '-page-' + this.page() + '.csv');
  }
  private downloadCSV(rows: readonly Row[], filename: string): void {
    const quote = (value: string) => '"' + (/^[=+@\-\t\r]/.test(value) ? "'" : '') + value.replaceAll('"', '""') + '"';
    const lines = [[...this.spec.columns.map(column => this.i18n.translate(column.labelKey)), this.i18n.translate('field.status')],
      ...rows.map(row => [...this.spec.columns.map(column => this.cell(row, column)), this.i18n.translate(this.statusKey(row))])];
    const url = URL.createObjectURL(new Blob(['\uFEFF' + lines.map(line => line.map(quote).join(',')).join('\r\n')], {type: 'text/csv;charset=utf-8'}));
    const link = document.createElement('a'); link.href = url; link.download = filename; link.click(); URL.revokeObjectURL(url);
  }
  protected readonly week = signal<readonly {date: string; rows: readonly Row[]}[]>([]);
  private readVersion = 0;

  protected toggleCalendar(): void {
    this.calendarView.update(value => !value);
    this.refilter();
  }

  protected calendarDate(date: string): string {
    return new Intl.DateTimeFormat('ar-EG', {weekday: 'long', day: 'numeric', month: 'short', timeZone: 'UTC'}).format(new Date(date + 'T12:00:00Z'));
  }

  private loadWeek(): void {
    const version = ++this.readVersion;
    this.loading.set(true);
    this.failed.set(false);
    const start = new Date((this.day() || this.format.today()) + 'T12:00:00Z');
    start.setUTCDate(start.getUTCDate() - ((start.getUTCDay() + 1) % 7));
    const days = Array.from({length: 7}, (_, index) => {
      const date = new Date(start);
      date.setUTCDate(date.getUTCDate() + index);
      const key = date.toISOString().slice(0, 10);
      const query: DayQuery = {...this.diaryFilters(), date: key, status: this.status() || undefined, limit: 100};
      return this.api.list('appointments', query).pipe(switchMap(first => {
        const pages = Math.ceil(first.total / Math.max(1, first.limit));
        return (pages > 1 ? forkJoin(Array.from({length: pages - 1}, (_, n) =>
          this.api.list('appointments', {...query, page: n + 2}))) : of([])).pipe(
          map(rest => ({date: key, rows: [first, ...rest].flatMap(page => page.rows)
            .sort((a, b) => String(a['starts_at']).localeCompare(String(b['starts_at'])))})));
      }));
    });
    forkJoin(days).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: week => { if (version !== this.readVersion) return; this.week.set(week); this.loading.set(false); },
      error: () => { if (version !== this.readVersion) return; this.failed.set(true); this.loading.set(false); },
    });
  }

  protected load(): void {
    if (this.spec.resource === 'invoices') this.loadInvoiceCounts();
    if (this.spec.resource === 'appointments') this.loadAppointmentAttention();
    if (this.calendarView()) { this.loadWeek(); return; }
    const version = ++this.readVersion;
    this.loading.set(true);
    this.failed.set(false);

    const query: DayQuery = {
      status: this.status() || undefined,
      kind: this.kind() || undefined,
      page: this.page() > 1 ? this.page() : undefined,
      limit: this.pageSize(),
    };
    if (this.spec.window === 'diary') {
      // One day, resolved in the centre's zone by the service. The window is
      // half open there, so an appointment at midnight belongs to one day and
      // not to two.
      Object.assign(query, this.diaryFilters(), { date: this.day() || undefined });
    } else if (this.spec.window === 'ledger') {
      // Days, not instants. Sending an instant here is a 400 naming the
      // field - the two windows are not interchangeable.
      Object.assign(query, { from: this.from() || undefined, to: this.to() || undefined });
    }
    // A queue sends no window at all: the application nobody has called back
    // in three weeks is the one that must stay on the screen.

    if (this.spec.archivable && this.showArchived()) {
      Object.assign(query, { archived: true });
    }

    this.api.list(this.spec.resource, query)
      .pipe(switchMap(first => {
        if (!this.boardView()) return of(first);
        const pages = Math.ceil(first.total / Math.max(1, first.limit));
        return (pages > 1 ? forkJoin(Array.from({length: pages - 1}, (_, n) => this.api.list(this.spec.resource, {...query, page: n + 2}))) : of([]))
          .pipe(map(rest => ({...first, rows: [first, ...rest].flatMap(result => result.rows), limit: first.total || first.limit})));
      }), takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          if (version !== this.readVersion) return;
          this.rows.set(result.rows);
          this.total.set(result.total);
          this.limit.set(result.limit);
          this.loading.set(false);
          if (this.focusId) {
            // After the rows are drawn. A miss is silent: the row may be on
            // another page or already moved on, and saying so would be a
            // second message about a thing the list already shows.
            setTimeout(() => document.querySelector('.is-focus')?.scrollIntoView({ block: 'center' }), 0);
          }
        },
        error: () => {
          if (version !== this.readVersion) return;
          this.loading.set(false);
          this.failed.set(true);
        },
      });
  }

  /** Any filter change starts at page one. */
  protected refilter(): void {
    this.page.set(1);
    this.load();
  }

  protected setDay(value: string): void {
    this.day.set(value);
    this.refilter();
  }

  protected shiftDay(days: number): void {
    const current = this.day() || this.format.today();
    const moved = new Date(`${current}T12:00:00Z`);
    moved.setUTCDate(moved.getUTCDate() + days);
    this.setDay(moved.toISOString().slice(0, 10));
  }

  protected setToday(): void {
    this.setDay(this.format.today());
  }

  protected setStatus(value: string): void {
    this.status.set(value);
    this.refilter();
  }

  protected setKind(value: string): void {
    this.kind.set(value);
    this.refilter();
  }

  protected toggleArchived(): void {
    this.showArchived.update((value) => !value);
    this.refilter();
  }

  protected setFrom(value: string): void {
    this.from.set(value);
    this.refilter();
  }

  protected setTo(value: string): void {
    this.to.set(value);
    this.refilter();
  }

  protected goToPage(page: number): void {
    if (page < 1 || page > this.pageCount() || page === this.page()) {
      return;
    }
    this.page.set(page);
    this.load();
  }

  // =====================================================================
  // Drawing a row
  // =====================================================================

  protected cell(row: Row, column: { read: (row: Row, ctx: DayContext) => string }): string {
    return column.read(row, this.ctx);
  }

  protected rowKey(row: Row): string {
    return String(row[this.spec.idColumn] ?? '');
  }

  protected statusKey(row: Row): string {
    const status = readText(row, 'status');
    return status ? `${this.spec.statusPrefix}${status}` : '';
  }

  protected statusTone(row: Row): string {
    return this.spec.tone(readText(row, 'status'));
  }

  /**
   * The actions this row can take, for this account.
   *
   * Two filters, and they mean different things. `when` is the row's state -
   * a completed appointment has nowhere to go. The permission check only
   * decides what to DRAW; the refusal itself happens in a policy under the
   * query, and hiding a button is not a control.
   */
  protected actionsFor(row: Row): readonly DayAction[] {
    return this.spec.actions.filter(
      (action) => action.when(row) && this.auth.can(action.permission));
  }

  /**
   * Which record drawer this list's rows open in, or null for a list whose
   * rows have no drawer (sessions, reports, requests keep their screens).
   */
  protected readonly drawerEntity: DrawerEntity | null =
    this.spec.resource === 'appointments' ? 'appointment'
    : this.spec.resource === 'invoices' ? 'invoice' : null;

  /** Opens the row in the record drawer, beside this list. The row is handed over; nothing is read. */
  protected openRecord(row: Row): void {
    if (!this.drawerEntity) {
      return;
    }
    void this.drawer.open({
      entity: this.drawerEntity, id: Number(row[this.spec.idColumn]), row, source: 'LIST',
    });
  }

  // =====================================================================
  // Acting
  // =====================================================================

  protected startCreate(action: CreateAction): void {
    this.openDialog(action, null);
  }

  /** The read-back heading, when this action asks for one. */
  protected reviewKeyOf(action: DayAction | CreateAction): string {
    return (action as CreateAction).reviewKey ?? '';
  }

  /** Whether the open action can ask the service to check it first. */
  protected hasCheck(action: DayAction | CreateAction): boolean {
    return !!(action as CreateAction).check;
  }

  protected startAction(action: DayAction, row: Row): void {
    this.openDialog(action, row);
  }

  private openDialog(action: DayAction | CreateAction, row: Row | null): void {
    const fields = action.fields ?? [];
    this.open.set({ action, row, fields });
    this.formError.set('');
    this.badField.set(null);
    this.slotCheck.set(null);

    // A select starts on its first real option, never empty. An empty select
    // still renders showing that first option, so the form looks filled while
    // it holds nothing - and the submit then sends nothing and the service
    // answers REQUIRED for a field the person can see a value in.
    // A narrowed list belongs to the service that was chosen LAST time this
    // dialog was open. Left in place it seeds the form with a therapist
    // from a different service, which is the exact mistake the narrowing
    // exists to prevent.
    this.narrowing.set(false);
    if (fields.some((field) => field.narrowedByService)) {
      this.lookups.update((current) => ({ ...current, therapists: [] }));
    }
    this.resetChildSearch();
    this.advancedOpen.set(false);
    this.pairs.set([]);
    this.pairsState.set('idle');
    if (fields.some((field) => field.kind === 'pair')) {
      this.loadPairs();
    }

    const values: Record<string, string> = {};
    for (const field of fields) {
      // A field with a placeholder opens UNANSWERED, and says so on screen.
      // The comment above describes why a select cannot merely be left
      // empty; placeholderKey is the other half of that - it gives the
      // empty state something to draw, so the control and the value agree.
      if (field.placeholderKey) {
        values[field.name] = '';
        continue;
      }
      const options = this.optionsOf(field, row);
      values[field.name] = options.length ? options[0].value : '';
    }
    this.values.set(values);

    // The slot list opens on the day the diary is showing, not on today.
    // Somebody looking at next Tuesday and pressing "book" means Tuesday.
    this.slots.set([]);
    this.slotsState.set('idle');
    this.pickedSlot.set('');
    this.slotDate.set(this.day() || this.format.today());

    this.loadLookups(fields);
  }

  protected close(): void {
    this.open.set(null);
    this.values.set({});
    this.slotCheck.set(null);
    this.slots.set([]);
    this.slotsState.set('idle');
    this.pickedSlot.set('');
    this.resetChildSearch();
    this.advancedOpen.set(false);
    if (this.embedded) {
      const done = this.completed;
      this.completed = false;
      this.embedded.onClose(done);
    }
  }

  protected setValue(name: string, value: string): void {
    this.values.update((current) => ({ ...current, [name]: value }));
    // A changed choice invalidates the answer that was given about the old
    // one. Leaving a green "slot is free" beside a different therapist would
    // be worse than showing nothing.
    if (this.slotCheck()) {
      this.slotCheck.set(null);
    }
    // And it invalidates the LIST for the same reason, which matters more:
    // a stale list is a set of times somebody can click, each of which then
    // books a different therapist's free hour into this one's day.
    if (name === 'therapist_id') {
      this.pickedSlot.set('');
      this.loadSlots();
    }

    // THE SAME REASON, FOR THE SAME KIND OF MISTAKE. An online consultation
    // needs no room, so its free hours are the therapist's own rather than
    // the intersection of the therapist and a room - a different question
    // with a different answer. A list left standing from the other mode is
    // a set of times that each book the wrong kind of appointment, and the
    // room the old list carried would travel with it.
    if (name === 'delivery_mode') {
      this.pickedSlot.set('');
      this.setValue('room_id', '');
      this.loadSlots();
    }

    // A DIFFERENT SERVICE IS A DIFFERENT SET OF THERAPISTS, and the slots
    // are NOT asked for here.
    //
    // They were, at first, and the request went out on the pair that was
    // about to be replaced - therapist 46 with a service he does not offer.
    // It answered harmlessly, which is the problem: a request for a
    // combination the screen is in the middle of rejecting is one nobody
    // would notice was wrong. The narrowing asks, once it knows who the
    // therapist now is.
    if (name === 'service_id') {
      this.pickedSlot.set('');
      this.slots.set([]);
      this.slotsState.set('idle');
      this.loadTherapistsForService(value);
    }

    // TYPING A START FILLS THE END, from the service's own duration.
    //
    // Reception was doing this arithmetic by hand - and a forty-five
    // minute speech session typed as an hour is not a typo anybody sees:
    // it books correctly, passes every rule, and the next family waits
    // fifteen minutes for a room that was never free.
    //
    // Only ever from starts_at, never the other way round. Somebody who
    // opens the manual fields to book a deliberately longer session must
    // be able to lengthen it, and an end that snapped back to the
    // service's duration would make that impossible.
    if (name === 'starts_at') {
      const end = this.derivedEnd();
      if (end) {
        this.values.update((current) => ({ ...current, ends_at: end }));
      }
    }
  }

  // =====================================================================
  // Progressive disclosure, and the read-back before the confirm
  // =====================================================================

  /**
   * Whether this field's prerequisites are answered.
   *
   * Disabled, not hidden. A control that vanishes leaves a hole somebody
   * hunts for; one that is visibly greyed says "not yet, and here is what
   * first" in the place they are already looking.
   */
  protected fieldReady(field: ActionField): boolean {
    return (field.needs ?? []).every((name) => !!(this.values()[name] ?? ''));
  }

  /** The main flow: everything the ordinary booking touches. */
  protected readonly primaryFields = computed(
    () => this.visibleFields().filter((field) => !field.secondary));

  /** Legal, rare, and behind a disclosure. */
  protected readonly secondaryFields = computed(
    () => this.visibleFields().filter((field) => field.secondary));

  protected readonly advancedOpen = signal(false);
  protected toggleAdvanced(): void { this.advancedOpen.update((v) => !v); }

  /** The heading to print above this field, or '' when it continues one. */
  protected sectionBreak(fields: readonly ActionField[], index: number): string {
    const here = fields[index]?.section ?? '';
    const before = index > 0 ? (fields[index - 1]?.section ?? '') : '';
    return here && here !== before ? here : '';
  }

  /**
   * What a chosen value READS as, for the summary.
   *
   * The form holds identifiers; a read-back that said "الطفل: 2716" would
   * be worse than no read-back, because it looks like confirmation.
   */
  protected displayOf(field: ActionField): string {
    const raw = this.values()[field.name] ?? '';
    if (!raw) {
      return '';
    }
    if (field.kind === 'search') {
      return this.childPicked();
    }
    if (field.kind === 'datetime') {
      return `${this.format.dayMonthYear(raw)} · ${this.format.time(raw + ':00')}`;
    }
    if (field.lookup || field.options || field.optionsFor) {
      const hit = this.optionsForOpen(field).find((o) => o.value === raw);
      return hit ? this.i18n.translate(hit.labelKey) : raw;
    }
    return raw;
  }

  /** Every field that holds something, in spec order, for the read-back. */
  protected readonly reviewRows = computed(() => (this.open()?.fields ?? [])
    // Controls are not facts. The slot picker and the pair each hold a
    // value that means something to the form and nothing to a reader -
    // the pair printed "66:46" here for exactly one build. What they
    // CHOSE is listed on its own lines: the service and the therapist.
    .filter((field) => field.kind !== 'slots' && field.kind !== 'pair')
    .filter((field) => !!(this.values()[field.name] ?? ''))
    .map((field) => ({ labelKey: field.labelKey, value: this.displayOf(field) }))
    .filter((row) => !!row.value));

  /**
   * Whether the confirm may be pressed at all.
   *
   * Every required field answered. It is NOT a second copy of the rules -
   * the service still refuses anything it would have refused - it only
   * stops a request that cannot possibly succeed from being sent, and
   * stops the button from looking ready when it is not.
   */
  protected readonly canConfirm = computed(() => (this.open()?.fields ?? [])
    .filter((field) => field.required && this.fieldShown(field))
    .every((field) => !!(this.values()[field.name] ?? '')));

  /**
   * Narrows the therapist list to the ones who offer this service.
   *
   * The list used to be everybody, and hbh.validate_slot answered
   * THERAPIST_SERVICE_MISMATCH after the choice was made. The service still
   * answers it - this is not a substitute for that check and must not be
   * read as one. What changes is that the wrong answer is no longer offered.
   *
   * AN EMPTY LIST IS A REAL ANSWER, not a failure: nobody in this centre is
   * linked to that service yet. The form says so and names where it is
   * fixed, instead of showing an empty dropdown that reads as broken.
   */
  private loadTherapistsForService(serviceId: string): void {
    const fields = this.open()?.fields ?? [];
    const field = fields.find((one) => one.narrowedByService);
    if (!field) {
      return;
    }
    const id = Number(serviceId);
    if (!id) {
      this.lookups.update((current) => ({ ...current, therapists: [] }));
      this.setValue(field.name, '');
      return;
    }
    this.narrowing.set(true);
    this.therapistsFor.next(id);
  }

  /**
   * The answer to the LAST service asked about, never an earlier one.
   *
   * Reception changes their mind mid-sentence - speech, no, occupational -
   * and two requests are in flight. With a plain subscribe the slower one
   * wins by arriving last, and the dropdown ends up listing the therapists
   * for a service the form is no longer on. Nothing errors; the list is
   * simply wrong, and the only person who could notice is the one being
   * misled by it.
   *
   * switchMap cancels the earlier request, so the list always belongs to
   * the service now selected.
   */
  private wireNarrowing(): void {
    this.therapistsFor.pipe(
      switchMap((id) => this.api.serviceTherapists(id).pipe(
        map((rows) => ({ rows, failed: false })),
        catchError(() => of({ rows: [] as readonly Row[], failed: true })))),
      takeUntilDestroyed(this.destroyRef),
    ).subscribe(({ rows, failed }) => {
      const field = (this.open()?.fields ?? []).find((one) => one.narrowedByService);
      if (!field) {
        return;
      }
      if (failed) {
        this.narrowing.set(false);
        // Not silently the full list. Falling back to everybody would
        // quietly restore the behaviour this replaced, on the one day
        // the request failed.
        this.lookups.update((current) => ({ ...current, therapists: [] }));
        this.setValue(field.name, '');
        this.formError.set('error.load');
        return;
      }
      this.applyTherapistOptions(field, rows);
    });
  }

  private applyTherapistOptions(field: ActionField, rows: readonly Row[]): void {
    const options = rows.map((row) => ({
      value: String(row['therapist_id'] ?? ''),
      labelKey: String(row['full_name_ar'] ?? ''),
    })).filter((option) => option.value !== '');
    this.lookups.update((current) => ({ ...current, therapists: options }));
    this.narrowing.set(false);

    // KEEP THE CHOICE IF IT SURVIVED THE NARROWING. Resetting a therapist
    // who still offers the new service would undo a deliberate selection
    // for no reason - and on the edit path it would quietly replace a
    // booking's real therapist with whoever sorts first.
    const held = this.values()[field.name] ?? '';
    if (options.some((option) => option.value === held)) {
      // Nothing calls setValue, so nothing would ask for the slots - and
      // the service changed, so the free windows are a different set.
      this.loadSlots();
    } else {
      // setValue asks for the slots itself, on the new pair.
      //
      // The held therapist did NOT survive the narrowing, so the choice is
      // gone either way. With a placeholder the field goes back to asking
      // rather than silently landing on whoever sorts first under the new
      // service - which is the same substitution this narrowing exists to
      // prevent, arriving one step later.
      this.setValue(field.name,
        field.placeholderKey ? '' : (options.length ? options[0].value : ''));
    }
  }

  // =====================================================================
  // The child search
  // =====================================================================

  protected onChildType(field: ActionField, term: string): void {
    this.childTerm.set(term);
    this.childOpen.set(true);
    // The typed text is no longer a chosen child. Clearing the VALUE here
    // is the point: leaving the last pick behind while the box shows
    // something else would book whoever was chosen before, and the screen
    // would have shown the new name the whole time.
    this.childPicked.set('');
    this.setValue(field.name, '');
    this.childState.set(term.trim().length < 2 ? 'short' : 'searching');
    this.childTyped.next(term);
  }

  protected pickChild(field: ActionField, row: Row): void {
    const id = String(row['child_id'] ?? '');
    if (!id) {
      return;
    }
    this.setValue(field.name, id);
    this.childPicked.set(this.childLabel(row));
    this.childTerm.set(this.childLabel(row));
    this.childOpen.set(false);
    this.childActive.set(-1);
  }

  /** Name and centre number together: two children share a name eventually. */
  protected childLabel(row: Row): string {
    const name = String(row['full_name_ar'] ?? '');
    const no = String(row['child_no'] ?? '');
    return no ? `${name} · ${no}` : name;
  }

  /**
   * Arrow keys, Enter and Escape.
   *
   * Without these the control is a mouse-only box in a screen reception
   * drives from the keyboard all day - and a combobox that announces
   * itself as one and then ignores the arrow keys is worse than a plain
   * text field, because a screen reader has promised something it does
   * not do.
   */
  protected onChildKey(field: ActionField, event: KeyboardEvent): void {
    const hits = this.childHits();
    if (event.key === 'Escape') {
      this.childOpen.set(false);
      return;
    }
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      if (!hits.length) {
        return;
      }
      event.preventDefault();
      this.childOpen.set(true);
      const step = event.key === 'ArrowDown' ? 1 : -1;
      const next = (this.childActive() + step + hits.length + 1) % (hits.length + 1);
      this.childActive.set(next === hits.length ? -1 : next);
      return;
    }
    if (event.key === 'Enter') {
      const active = this.childActive();
      if (this.childOpen() && active >= 0 && active < hits.length) {
        // Only when a hit is highlighted. Swallowing Enter otherwise would
        // stop the form being submitted from the keyboard.
        event.preventDefault();
        this.pickChild(field, hits[active]);
        return;
      }
      // ENTER TAKES THE ONLY HIT, and only when there is exactly one.
      //
      // Typing enough of a name to leave one child, then pressing Enter,
      // is one continuous act - and it is how a receptionist with a
      // parent on the phone actually works. The "exactly one" is the
      // whole safety of it: with two hits there is a real choice, and
      // guessing which one would book the wrong family. That is the one
      // mistake on this screen that reaches a person outside it.
      if (this.childOpen() && hits.length === 1 && this.childState() === 'ready') {
        event.preventDefault();
        this.pickChild(field, hits[0]);
      }
    }
  }

  private resetChildSearch(): void {
    this.childTerm.set('');
    this.childHits.set([]);
    this.childPicked.set('');
    this.childOpen.set(false);
    this.childActive.set(-1);
    this.childState.set('idle');
  }

  /**
   * A datetime-local value (the centre's wall clock) in words, or '' when it
   * is not a complete instant yet (#18). Converted through toUtc so the day
   * and hour read are the centre's, the same instant that will be sent.
   */
  protected readableWhen(wallLocal: string | undefined): string {
    const utc = this.format.toUtc(wallLocal ?? '');
    return utc ? `${this.format.fullDate(utc)} · ${this.format.time(utc)}` : '';
  }

  protected setSlotDate(value: string): void {
    this.slotDate.set(value);
    this.pickedSlot.set('');
    this.loadSlots();
  }

  /**
   * Asks which windows are free.
   *
   * Only when both halves of the question are answered. Asking with no
   * therapist would be asking "when is nobody free", and the service would
   * rightly say nothing at all - which on screen reads as a full day.
   *
   * A 403 is its own state. The route needs APPOINTMENT.BOOK and the
   * function refuses without it rather than returning an empty list,
   * because "you may not ask" and "there is nothing free" are different
   * answers and only one of them means the day is full.
   */
  protected loadSlots(): void {
    if (!this.hasSlotField()) {
      return;
    }
    const therapistId = Number(this.values()['therapist_id']);
    const serviceId = Number(this.values()['service_id']);
    const date = this.slotDate();
    // Absent on every form but the booking one, and IN_PERSON is what those
    // have always asked for.
    const mode = (this.values()['delivery_mode'] || 'IN_PERSON') as DeliveryMode;
    if (!therapistId || !serviceId || !date) {
      this.slots.set([]);
      this.slotsState.set('idle');
      return;
    }
    this.slots.set([]);
    this.slotsState.set('loading');
    this.slotsFor.next({ therapistId, serviceId, date, mode });
  }

  /**
   * The free windows for the LAST question asked, never an earlier one.
   *
   * Stepping through days - Sunday, Monday, Tuesday - puts three requests
   * in flight, and without switchMap the slowest answer wins by landing
   * last. The chips would then belong to a day the date box is no longer
   * showing, and every one of them is a real free window on the wrong
   * date: nothing looks wrong until an appointment is booked into it.
   */
  private wireSlots(): void {
    this.slotsFor.pipe(
      switchMap((q) => this.api.slots(q.therapistId, q.serviceId, q.date, undefined, q.mode).pipe(
        map((rows) => ({ rows, error: null as unknown })),
        catchError((error: unknown) => of({ rows: [] as readonly Slot[], error })))),
      takeUntilDestroyed(this.destroyRef),
    ).subscribe(({ rows, error }) => {
      if (error) {
        this.slotsState.set(
          readRefusal(error).failure === 'FORBIDDEN' ? 'denied' : 'failed');
        return;
      }
      this.slots.set(rows);
      this.slotsState.set('ready');
    });
  }

  /**
   * Takes a slot into the form.
   *
   * It fills THREE fields, and the room is the one that matters: the old
   * screen let somebody pick a room from a list of all of them, and learn at
   * check time that it was occupied. This room is the one the service just
   * said was free for this window.
   *
   * The instants arrive as UTC and go into the form as the centre's wall
   * clock, because that is what the datetime inputs hold and what
   * bookingBody converts back. Round-tripping through the same pair of
   * functions is deliberate: one place decides what "10:00 in Cairo" means.
   */
  protected pickSlot(slot: Slot): void {
    this.pickedSlot.set(slot.starts_at);
    this.setValue('starts_at', this.format.toWallLocal(slot.starts_at));
    this.setValue('ends_at', this.format.toWallLocal(slot.ends_at));
    // TWO fields on a consultation and three on a visit. A slot with no room
    // sets none: String(null) is "null", which would go into the room field
    // as text and reach the service as NaN.
    this.setValue('room_id', slot.room_id === null ? '' : String(slot.room_id));
  }

  protected slotLabel(slot: Slot): string {
    return `${this.format.time(slot.starts_at)} – ${this.format.time(slot.ends_at)}`;
  }

  private hasSlotField(): boolean {
    return (this.open()?.fields ?? []).some((field) => field.kind === 'slots');
  }

  /** The choices for a field: fixed, computed from the row, or looked up. */
  protected optionsOf(field: ActionField, row: Row | null): readonly ActionOption[] {
    if (field.lookup) {
      return this.lookups()[field.lookup] ?? [];
    }
    if (field.optionsFor && row) {
      return field.optionsFor(row);
    }
    return field.options ?? [];
  }

  protected optionsForOpen(field: ActionField): readonly ActionOption[] {
    return this.optionsOf(field, this.open()?.row ?? null);
  }

  /** Whether a conditional field is showing right now. */
  protected fieldShown(field: ActionField): boolean {
    const rule = field.onlyWhen;
    if (!rule) {
      return true;
    }
    return rule.isOneOf.includes(this.values()[rule.field] ?? '');
  }

  protected readonly visibleFields = computed(
    () => (this.open()?.fields ?? []).filter((field) => this.fieldShown(field)));

  /**
   * Loads the choices a booking form needs, once, when it opens.
   *
   * The lists come from the CRUD endpoints - the same rows the catalogue
   * screens edit - so a room added this morning is bookable this afternoon
   * without a second place to add it.
   */
  private loadLookups(fields: readonly ActionField[]): void {
    // A narrowed lookup is NOT loaded from its CRUD list. Loading the full
    // list first and replacing it a moment later would show every therapist
    // for as long as the second request takes - and if the second one
    // failed, leave the full list standing as though nothing had happened.
    // Neither a narrowed lookup nor a searched one is loaded from its CRUD
    // list. For `search` that is the entire change: fetching the first two
    // hundred children to fill a control that never shows them would be the
    // old cost with none of the old benefit.
    const needed = [...new Set(
      fields
        .filter((field) => !field.narrowedByService && field.kind !== 'search')
        .map((field) => field.lookup)
        .filter((name): name is LookupResource => !!name))];
    if (needed.length === 0) {
      return;
    }
    this.lookupsLoading.set(true);
    let outstanding = needed.length;

    for (const name of needed) {
      this.crud.list(name, { limit: 200 })
        .pipe(takeUntilDestroyed(this.destroyRef))
        .subscribe({
          next: (result) => {
            const shape = LOOKUP_SHAPE[name];
            const options = result.rows.map((row) => ({
              value: String(row[shape.id] ?? ''),
              // Already the centre's own text, not a key. The translate pipe
              // returns its input unchanged when there is no such key, so a
              // name passes through untouched.
              labelKey: String(row[shape.label] ?? ''),
            })).filter((option) => option.value !== '');

            // The duration travels with the services list rather than in a
            // request of its own: the rows are already here, and the field
            // the booking needs is on every one of them.
            if (name === 'services') {
              const minutes: Record<string, number> = {};
              for (const row of result.rows) {
                const value = Number(row['default_duration_min']);
                if (value > 0) {
                  minutes[String(row['service_id'])] = value;
                }
              }
              this.serviceMinutes.set(minutes);
            }

            this.lookups.update((current) => ({ ...current, [name]: options }));
            // Fill the control now that there is something to fill it with.
            // Without this the select shows the first name and holds "".
            //
            // UNLESS THE FIELD ASKS. This is where the arriving list used to
            // answer the question on the person's behalf: the dialog opened
            // empty, the lookup landed a moment later, and the first row in
            // it became the booking's service, therapist or room without a
            // single click. A placeholder field keeps its own empty value
            // here - it has something to draw, so the select is not lying.
            const target = fieldNameFor(fields, name);
            const field = fields.find((f) => f.name === target);
            if (options.length && !field?.placeholderKey && !this.values()[target]) {
              this.setValue(target, options[0].value);
            }
            if (--outstanding === 0) {
              this.lookupsLoading.set(false);
            }
          },
          error: () => {
            if (--outstanding === 0) {
              this.lookupsLoading.set(false);
            }
            // Say it once, and let the person close the dialog. A booking
            // form with an empty therapist list is not usable, and silence
            // would leave them clicking a disabled button.
            this.formError.set('error.load');
          },
        });
    }
  }

  /**
   * Asks whether this booking would be accepted, without making one.
   *
   * The refusal is a 200 with ok:false. It is not an error and is not shown
   * as one: a question was asked and answered.
   */
  protected check(): void {
    const open = this.open();
    const create = open?.action as CreateAction | undefined;
    if (!open || !create?.check || this.checking()) {
      return;
    }
    const missing = this.firstMissing();
    if (missing) {
      this.formError.set('error.field.REQUIRED');
      this.badField.set(missing.name);
      return;
    }
    this.checking.set(true);
    this.formError.set('');
    create.check(this.api, this.values(), this.ctx)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (answer) => {
          this.checking.set(false);
          this.slotCheck.set(answer);
        },
        error: (error: unknown) => {
          this.checking.set(false);
          this.formError.set(this.messageFor(error));
        },
      });
  }

  protected submit(event?: Event): void {
    event?.preventDefault();
    const open = this.open();
    if (!open || this.saving()) {
      return;
    }

    const missing = this.firstMissing();
    if (missing) {
      this.formError.set('error.field.REQUIRED');
      this.badField.set(missing.name);
      return;
    }

    this.saving.set(true);
    this.formError.set('');
    this.badField.set(null);

    const values = this.values();
    const call: Observable<unknown> = open.row === null
      ? (open.action as CreateAction).run(this.api, values, this.ctx)
      : (open.action as DayAction).run(this.api, open.row, values, this.ctx);

    call.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: () => {
        this.saving.set(false);
        this.completed = true;
        this.close();
        this.toast.show(this.i18n.translate(open.action.doneKey));
        // Embedded, the caller re-reads its own row; there is no list here.
        if (!this.embedded) {
          this.load();
        }
      },
      error: (error: unknown) => {
        this.saving.set(false);
        const refusal = readRefusal(error);
        this.formError.set(this.messageFor(error));
        this.badField.set(refusal.field);
      },
    });
  }

  /** The first visible required field that is empty, or null. */
  private firstMissing(): ActionField | null {
    const values = this.values();
    for (const field of this.open()?.fields ?? []) {
      if (!field.required || !this.fieldShown(field)) {
        continue;
      }
      if (!(values[field.name] ?? '').trim()) {
        return field;
      }
    }
    return null;
  }

  /**
   * A refusal in the console's words.
   *
   * Status 0 is kept apart from every other case: the request never arrived,
   * and calling that "an unexpected error" sends somebody hunting for a
   * problem in what they typed.
   */
  private messageFor(error: unknown): string {
    const status = (error as { status?: number })?.status;
    if (status === 0 || status === undefined) {
      return 'error.connection';
    }
    const refusal = readRefusal(error);
    // The service documents a set of operational codes the generic reader
    // does not know - SLOT_TAKEN, ILLEGAL_TRANSITION, OVERPAYMENT. They
    // arrive in the same field, and each has its own sentence.
    const code = (error as { error?: { error?: { code?: string } } })
      ?.error?.error?.code;
    if (code && refusal.failure === 'UNKNOWN') {
      return this.known(`error.${code}`, 'error.UNKNOWN');
    }
    return refusalKey(refusal);
  }

  /**
   * The sentence for a slot answer.
   *
   * validate_slot has fourteen reasons - THERAPIST_SERVICE_MISMATCH,
   * OUTSIDE_WORKING_HOURS, CHILD_BUSY, and so on - and they are not the same
   * set as the HTTP codes booking refuses with. Every one is translated; the
   * fallback exists because a reason added to the schema tomorrow must not
   * print its own constant in Latin letters on an Arabic screen.
   */
  protected slotKey(answer: { ok: boolean; reason: string }): string {
    return answer.ok ? 'slot.OK' : this.known(`slot.${answer.reason}`, 'slot.UNKNOWN');
  }

  /** `key` when the bundle has it, otherwise `fallback`. */
  private known(key: string, fallback: string): string {
    return this.i18n.translate(key) === key ? fallback : key;
  }
}

/** Which field in this form draws on a given lookup list. */
function fieldNameFor(fields: readonly ActionField[], lookup: LookupResource): string {
  return fields.find((field) => field.lookup === lookup)?.name ?? '';
}
