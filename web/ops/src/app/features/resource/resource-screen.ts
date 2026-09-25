import { ArchiveSwitch } from '@hbh/shared/ui/archive-switch';
import {
  ChangeDetectionStrategy, Component, DestroyRef, Injector, Type, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormControl, ReactiveFormsModule } from '@angular/forms';
import { NgComponentOutlet } from '@angular/common';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { Observable, Subscription } from 'rxjs';

import { ModalDialog } from '@hbh/shared/a11y/modal-dialog';
import { FormatService } from '@hbh/shared/format/format.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { DateParts } from '@hbh/shared/ui/date-parts';
import { HbhNumberPipe } from '@hbh/shared/format/format.pipes';
import { DayApi } from '../../core/ops/day-api';
import { OpsApi, Row } from '../../core/api/ops-api';
import { readAllPages } from '../../core/api/read-all-pages';
import { readRefusal, refusalKey, refusalSentence } from '../../core/api/ops-error';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { EmbeddedResource } from '../../core/ops/action-request';
import { FieldSpec, ResourceSpec } from '../../core/resource/resource-spec';
import { ChildProfile, EMBEDDED_CHILD_PROFILE } from '../child/child-profile';

/** A tab drawn by a component of its own, declared in the route's `extraTabs`. */
export interface ExtraTab {
  readonly key: string;
  readonly titleKey: string;
  /** Decides whether the tab is drawn; the component's reads are refused by the server regardless. */
  readonly permission: string;
  readonly component: Type<unknown>;
}

interface TabRef {
  readonly key: string;
  readonly titleKey: string;
  readonly permission: string;
}

/**
 * One screen for every resource the service exposes.
 *
 * The service gives fourteen resources the same six verbs, so the console
 * answers with one implementation and a description per resource. Writing a
 * component per table would have produced fourteen list-and-editor pairs,
 * and the day one of them learned to handle a refusal properly would be the
 * day the other thirteen did not.
 *
 * Two rules it will not break:
 *
 *   Nothing is ever deleted. Archive sets active_flg through the service's
 *   own path and restore brings the row back. There is no hard delete in
 *   this system, and none in this screen.
 *
 *   center_id and active_flg are never sent. The service derives the centre
 *   from the caller and owns the archive flag; a client that could name a
 *   centre could try to name someone else's.
 */
@Component({
  selector: 'hbh-resource-screen',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [ArchiveSwitch, 
    ReactiveFormsModule, RouterLink, NgComponentOutlet, Icon, TranslatePipe, HbhNumberPipe,
    Skeleton, EmptyState, ErrorNote, ModalDialog, DateParts,
  ],
  templateUrl: './resource-screen.html',
  styleUrl: './resource-screen.css',
  host: { '[class.family-screen]': "spec().resource === 'guardians'" },
})
export class ResourceScreen {
  private readonly api = inject(OpsApi);
  private readonly dayApi = inject(DayApi);
  protected readonly roomCards = signal(true);
  protected readonly roomSessions = signal<Record<string, Row | null | undefined>>({});
  protected cameraStatus(row: Row): string {
    return ({ONLINE:'متصلة', OFFLINE:'غير متصلة', FAULT:'عطل', DISABLED:'معطلة'} as Record<string,string>)[String(row['status'])] ?? 'غير معروفة';
  }
  protected nestedName(row: Row, field: string): string {
    return String((row[field] as Record<string, unknown> | undefined)?.['full_name_ar'] ?? '');
  }
  protected readonly roomsFailed = signal<Record<string, boolean>>({});
  private roomVersion = 0;
  private loadRoomSessions(rooms: readonly Row[]): void {
    const version = ++this.roomVersion;
    this.roomSessions.set({});
    this.roomsFailed.set({});
    if (!this.auth.can('SESSION.START')) return;
    for (const room of rooms) {
      const id = Number(room['room_id']);
      this.dayApi.list('sessions', {date: this.format.today(), room_id: id, status: 'IN_PROGRESS', limit: 1})
        .pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
          next: result => { if (version === this.roomVersion) this.roomSessions.update(current => ({...current, [id]: result.rows[0] ?? null})); },
          error: () => { if (version === this.roomVersion) this.roomsFailed.update(current => ({...current, [id]: true})); },
        });
    }
  }
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  private readonly toast = inject(ToastService);
  private readonly i18n = inject(I18nService);
  protected readonly auth = inject(OpsAuthService);
  protected readonly format = inject(FormatService);

  /** One or more resources on this screen; several become tabs. */
  protected readonly specs: readonly ResourceSpec[] =
    (this.route.snapshot.data['specs'] as ResourceSpec[] | undefined) ?? [];

  /**
   * Tabs that are whole components rather than resources, drawn after the
   * resource tabs: the therapist services matrix beside the therapists, the
   * site team beside the site's texts, the satisfaction results beside the
   * surveys. One screen per subject, not one route per table
   * (docs/UX-TARGET-INFORMATION-ARCHITECTURE.md section 1.2).
   */
  protected readonly extraTabs: readonly ExtraTab[] =
    (this.route.snapshot.data['extraTabs'] as ExtraTab[] | undefined) ?? [];

  /** Every tab in order, resources first, for the tab bar and the URL. */
  protected readonly tabs: readonly TabRef[] = [
    ...this.specs.map((s) => ({ key: s.resource, titleKey: s.titleKey, permission: s.viewPermission })),
    ...this.extraTabs.map((e) => ({ key: e.key, titleKey: e.titleKey, permission: e.permission })),
  ];

  protected readonly guardianCounts = signal<Record<string, number | undefined>>({});
  protected readonly selectedGuardian = signal<Row | null>(null);
  protected readonly familyChildren = signal<readonly Row[]>([]);
  private readonly familyInjector = inject(Injector);
  protected readonly childProfileComponent = ChildProfile;
  protected readonly familyChild = signal<{ row: Row; injector: Injector } | null>(null);
  protected openFamilyChild(row: Row): void {
    if (!this.auth.can('CHILD.VIEW_ALL')) return;
    this.familyChild.set({ row, injector: Injector.create({ parent: this.familyInjector, providers: [
      { provide: EMBEDDED_CHILD_PROFILE, useValue: { childId: Number(row['child_id']), close: () => this.familyChild.set(null) } },
    ] }) });
  }
  protected readonly familyLoading = signal(false);
  protected readonly familyFailed = signal(false);
  private familyRequest?: Subscription;
  protected openGuardian(row: Row): void {
    this.selectedGuardian.set(row);
    this.familyChild.set(null);
    this.loadFamily();
  }
  protected closeGuardian(): void {
    this.familyRequest?.unsubscribe();
    this.familyChild.set(null);
    this.selectedGuardian.set(null);
  }
  protected loadFamily(): void {
    const guardian = this.selectedGuardian();
    if (!guardian) return;
    this.familyRequest?.unsubscribe();
    this.familyLoading.set(true);
    this.familyFailed.set(false);
    this.familyRequest = readAllPages(page => this.api.list('children', {
      guardian_id: Number(guardian['guardian_id']), page, limit: 100,
    })).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: rows => {
        this.familyChildren.set(rows);
        this.familyLoading.set(false);
      },
      error: () => { this.familyLoading.set(false); this.familyFailed.set(true); },
    });
  }
  /**
   * Which tab, taken from the URL when the URL says.
   *
   * THE TAB IS PART OF WHERE YOU ARE. These screens carry two to five tabs -
   * children and guardians, the four plan resources, rooms and cameras - and
   * switching them changed nothing in the address bar. So a link to
   * "guardians" was a link to "children", refreshing threw you back to the
   * first tab, and the browser's back button left the screen entirely instead
   * of returning to the tab before.
   *
   * Named by resource rather than numbered: `?tab=guardians` still means the
   * same thing if somebody reorders the array, and it reads.
   *
   * The fallback is the first tab this person may actually open - a
   * receptionist without PLAN.MANAGE lands on one she can see rather than on
   * an empty screen.
   */
  private readonly firstPermitted = Math.max(
    0, this.tabs.findIndex((t) => this.auth.can(t.permission)));

  protected readonly tabIndex = signal(this.tabFromUrl());

  private tabFromUrl(): number {
    const wanted = this.route.snapshot.queryParamMap.get('tab');
    if (!wanted) {
      return this.firstPermitted;
    }
    const found = this.tabs.findIndex(
      (t) => t.key === wanted && this.auth.can(t.permission));
    return found >= 0 ? found : this.firstPermitted;
  }

  /**
   * The resource under the active tab. When the active tab is a component
   * tab there is no resource, and the rest of this class - controls, list,
   * editor - keeps pointing at the first resource so nothing it computes is
   * undefined; the template draws none of it while `extra()` is set.
   */
  protected readonly spec = computed(
    () => this.specs[this.tabIndex()] ?? this.specs[0]);

  /** The component tab under the active index, or null on a resource tab. */
  protected readonly extra = computed<ExtraTab | null>(
    () => this.extraTabs[this.tabIndex() - this.specs.length] ?? null);

  protected readonly rows = signal<readonly Row[]>([]);

  /**
   * Readable names for the foreign keys on this screen, by resource then id.
   *
   * Loaded once when the screen opens, not per row: a list of twenty plans
   * referencing twenty children would otherwise be twenty requests for the
   * same list.
   *
   * A miss is not an error. If the name cannot be read - the list is longer
   * than one page, the caller may not see that row, the service is having a
   * bad minute - display() falls back to the identifier, which is what it
   * showed before this existed. The screen never renders less than it used
   * to because a lookup failed.
   */
  private readonly refNames = signal<Record<string, Record<string, string>>>({});
  protected readonly refState = signal<Record<string, 'loading' | 'ready' | 'failed'>>({});

  protected refOptions(field: FieldSpec): readonly { value: string; label: string }[] {
    const names = this.refNames()[field.ref!.resource] ?? {};
    return Object.entries(names).map(([value, label]) => ({ value, label: `${label} · #${value}` }));
  }

  protected refHasCurrent(field: FieldSpec): boolean {
    return !!this.refNames()[field.ref!.resource]?.[this.controls()[field.name].value];
  }

  /**
   * A value held by a select whose list does not offer it, or ''.
   *
   * Lists here are written in the console and the column they are written for
   * is plain text in the database - `nps_surveys.code` is the case this was
   * added for. So a row can hold something the list has never heard of: one
   * written before the list existed, or by a centre that had its own name for
   * it. The value is drawn as its own option, unlabelled, exactly as it is
   * stored.
   */
  /**
   * Whether this row's family has no way into the portal (HBH-084).
   *
   * STRICTLY false, never falsy. The service sends
   * `family_has_portal_account` on every child, list and single read, and
   * sends false rather than omitting it - so undefined means this build is
   * talking to a service that does not compute it. Drawing that as "no
   * account" would put a warning on every child in the list the day the
   * field is renamed, and send the centre off creating accounts that exist.
   */
  protected noPortalAccount(row: Row): boolean {
    return row['family_has_portal_account'] === false;
  }

  protected unlistedValue(field: FieldSpec): string {
    const value = this.controls()[field.name]?.value ?? '';
    if (!value || !field.options) {
      return '';
    }
    return field.options.some((option) => option.value === value) ? '' : value;
  }

  protected retryReferences(): void { this.loadRefNames(); }

  private loadRefNames(): void {
    const seen = new Set<string>();
    for (const field of this.spec().fields) {
      const ref = field.ref;
      if (!ref || seen.has(ref.resource)) {
        continue;
      }
      seen.add(ref.resource);
      this.refState.update(all => ({ ...all, [ref.resource]: 'loading' }));
      readAllPages(page => this.api.list(ref.resource, { limit: 100, page }))
        .pipe(takeUntilDestroyed(this.destroyRef))
        .subscribe({
          next: (rows) => {
            const names: Record<string, string> = {};
            for (const row of rows) {
              const id = row[ref.idColumn];
              const label = row[ref.labelColumn];
              if (id !== null && id !== undefined && label) {
                names[String(id)] = String(label);
              }
            }
            this.refNames.update((all) => ({ ...all, [ref.resource]: names }));
            this.refState.update(all => ({ ...all, [ref.resource]: 'ready' }));
          },
          // Silent: the identifier still shows. A toast about a lookup the
          // person did not ask for would be noise on every screen open.
          error: () => this.refState.update(all => ({ ...all, [ref.resource]: 'failed' })),
        });
    }
  }
  /** What the whole filter matches, which is not what this page holds. */
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
  protected readonly showArchived = signal(false);

  /**
   * "Only the families who cannot sign in" (HBH-101).
   *
   * IT IS A QUESTION FOR THE SERVICE. The obvious version of this - keep the
   * rows and hide the ones whose flag is true - reads the page the browser
   * happens to hold, so a centre with ninety children would be shown the
   * twenty on screen and told that was all of them. On the one screen whose
   * whole purpose is finding a family nobody noticed, that is the worst
   * possible way to be wrong. So the parameter goes back to the service,
   * which filters in the query and makes the count and the pages follow.
   *
   * The service computes it from the same expression it computes the badge
   * from, under the caller's identity - so the filter agrees with the badge
   * beside it and cannot reach a family the policy would hide.
   */
  protected readonly onlyWithoutAccount = signal(false);

  /** Whether this list is one the service can answer that question about. */
  protected readonly canFilterWithoutAccount = computed(
    () => this.spec().resource === 'children');
  protected readonly search = new FormControl('', { nonNullable: true });

  /** The row being edited; an empty object means creating. Null means closed. */
  protected readonly editing = signal<Row | null>(null);
  protected readonly saving = signal(false);
  protected readonly formError = signal('');
  protected readonly badField = signal<string | null>(null);

  /** One control per field of the active resource, rebuilt when tabs change. */
  protected readonly controls = signal<Record<string, FormControl<string>>>({});

  /**
   * The controls' current values, mirrored into a signal.
   *
   * A FormControl is not a signal, so a computed that reads one does not
   * recompute when it changes. Without this mirror the conditional fields
   * would settle on whatever the trigger was when the dialogue opened and
   * never follow the selection - which looks exactly like the bug it is
   * meant to fix.
   */
  private readonly values = signal<Record<string, string>>({});
  private valueWatch?: Subscription;

  protected readonly canWrite = computed(() => this.auth.can(this.spec().writePermission));
  protected readonly isNew = computed(
    () => this.editing()?.[this.spec().idColumn] === undefined);

  /**
   * The fields the editor draws, which is not always all of them.
   *
   * An `editOnly` field is hidden while creating. It exists for `status` on
   * the website's content: those resources accept it on UPDATE and refuse it
   * on INSERT, because publishing is a separate act from writing - a
   * different permission, and a testimonial or a certificate that has to be
   * looked at before it reaches the open internet.
   *
   * Drawing it anyway was worse than useless: the dialogue offered "منشور",
   * the service refused the whole row, and the message said "check the
   * values you entered" - which names nothing, points at nothing, and
   * describes a control that could never have worked.
   */
  protected readonly formFields = computed(() => {
    const fields = this.spec().fields;
    const drawn = this.isNew() ? fields.filter((field) => !field.editOnly) : fields;
    return drawn.filter((field) => this.isShown(field));
  });

  /**
   * The fields a `showWhen` is currently holding back, so save() can clear
   * them. Never `editOnly` ones: those are omitted, not blanked.
   */
  private readonly clearedFields = computed(() => {
    const fields = this.isNew()
      ? this.spec().fields.filter((field) => !field.editOnly)
      : this.spec().fields;
    return fields.filter((field) => field.showWhen && !this.isShown(field));
  });
  protected readonly listFields = computed(
    () => this.spec().fields.filter((field) => field.inList));

  /**
   * Set when this instance exists only to draw the editor for a caller
   * elsewhere (ActionDialogHost, through ActionDialogService.openResource):
   * the child's file adding a goal, the guardian's page editing the
   * guardian. No list, no reads; the editor opens at once on the given row
   * (or on a blank one with the caller's values) and reports back through
   * `onClose`. Same editor, same save, same refusals as on the list.
   */
  protected readonly embeddedRes: EmbeddedResource | null =
    (this.route.snapshot.data['embeddedResource'] as EmbeddedResource | undefined) ?? null;

  constructor() {
    this.buildControls();
    if (this.embeddedRes) {
      this.loadRefNames();
      this.openEditor(this.embeddedRes.row ?? {});
      const prefill = this.embeddedRes.request.prefill ?? {};
      const controls = this.controls();
      for (const [name, value] of Object.entries(prefill)) {
        controls[name]?.setValue(value);
        if (this.embeddedRes.request.source === 'CHILD_PROFILE' && ['child_id', 'plan_id', 'goal_id'].includes(name)) {
          controls[name]?.disable();
        }
      }
    } else {
      this.load();
    }
    // buildControls drops the previous subscriptions on a tab change; this
    // drops the last set when the screen itself goes.
    this.destroyRef.onDestroy(() => this.valueWatch?.unsubscribe());
  }

  protected selectTab(index: number): void {
    if (index === this.tabIndex() && !this.selectedGuardian()) {
      return;
    }
    this.selectedGuardian.set(null);
    this.tabIndex.set(index);
    // Into the address bar, so the tab can be linked to, refreshed and
    // stepped back out of. A real history entry rather than a replacement:
    // "back" should return to the tab somebody came from, which is what they
    // are asking for when they press it.
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: { tab: this.tabs[index].key },
      queryParamsHandling: 'merge',
    });
    this.editing.set(null);
    this.search.setValue('');
    this.showArchived.set(false);
    this.onlyWithoutAccount.set(false);
    this.page.set(1);
    this.buildControls();
    this.load();
  }

  /**
   * Which listing is the current one.
   *
   * Now that the SERVER filters, a search is a request per term, and the
   * replies do not have to come back in the order they were asked for: type
   * "م", then "محمد", and if the first query is the slower of the two it
   * lands last and puts the wide result back on screen under the narrow
   * term. Same guard the room cards above already use.
   */
  private listVersion = 0;

  protected load(): void {
    const version = ++this.listVersion;
    if (this.extra()) {
      // A component tab reads for itself; asking for the first resource's
      // rows here would be a request nobody looks at.
      this.loading.set(false);
      return;
    }
    const term = this.spec().searchable ? this.search.value.trim() : '';
    this.loading.set(true);
    this.failed.set(false);
    this.loadRefNames();
    this.api.list(this.spec().resource, {
      guardian_id: this.spec().resource === 'children' && this.selectedGuardian() ? Number(this.selectedGuardian()!['guardian_id']) : undefined,
      q: term || undefined,
      archived: this.showArchived() || undefined,
      without_portal_account:
        this.canFilterWithoutAccount() && this.onlyWithoutAccount() ? true : undefined,
      // Pages start at 1, not 0 - the service's own convention.
      page: this.page() > 1 ? this.page() : undefined,
      limit: this.pageSize(),
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          if (version !== this.listVersion) return;
          this.appliedQuery.set(term);
          this.rows.set(result.rows);
          if (this.spec().resource === 'rooms') this.loadRoomSessions(result.rows);
if (this.spec().resource === 'guardians') {
for (const guardian of result.rows) {
this.api.list('children', {guardian_id: Number(guardian['guardian_id'])}).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({next: children => this.guardianCounts.update(counts => ({...counts, [String(guardian['guardian_id'])]: children.total})), error: () => {}});
}
const selected = result.rows.find(row => row['guardian_id'] === this.selectedGuardian()?.['guardian_id']);
if (selected) this.selectedGuardian.set(selected); else this.closeGuardian();
}
          this.total.set(result.total);
          this.limit.set(result.limit);
          this.loading.set(false);
        },
        error: () => {
          if (version !== this.listVersion) return;
          this.loading.set(false);
          this.failed.set(true);
        },
      });
  }

  protected toggleArchived(): void {
    this.showArchived.update((value) => !value);
    // Any filter change starts at the first page. Staying on page 4 of a
    // narrower result shows an empty table that looks like "nothing found".
    this.page.set(1);
    this.load();
  }

  protected toggleWithoutAccount(): void {
    this.onlyWithoutAccount.update((value) => !value);
    // Same reason as above, and it bites harder here: this filter is the one
    // that makes a long list short, so page 4 is very likely to be past the
    // end - and an empty table on the screen for finding forgotten families
    // reads as "there are none".
    this.page.set(1);
    this.load();
  }

  /**
   * Whether the empty table is empty BECAUSE of a term.
   *
   * Read from the applied term rather than the input box: somebody who
   * clears the field and has not pressed search yet is still looking at the
   * results of the old one, and the empty state should describe what is on
   * screen rather than what they are about to ask for.
   */
  protected readonly searching = computed(() => this.appliedQuery() !== '');

  /** The term the rows on screen were fetched with. */
  private readonly appliedQuery = signal('');

  protected searchNow(): void {
    this.page.set(1);
    this.load();
  }

  protected readonly pageCount = computed(() => {
    const size = this.limit();
    return size > 0 ? Math.max(1, Math.ceil(this.total() / size)) : 1;
  });

  protected readonly hasMorePages = computed(() => this.pageCount() > 1);

  protected goToPage(page: number): void {
    if (page < 1 || page > this.pageCount() || page === this.page()) {
      return;
    }
    this.page.set(page);
    this.load();
  }

  /** Reads a column as text. Rows are untyped by design. */
  protected cell(row: Row, column: string): string {
    const value = row[column];
    return value === null || value === undefined ? '' : String(value);
  }

  /** How one field should read in the list. */
  protected display(row: Row, field: FieldSpec): string {
    const raw = this.cell(row, field.name);
    if (!raw) {
      return '';
    }
    if (field.kind === 'date') {
      // WITH THE YEAR. A `date` field here is a calendar date - a birth date,
      // a measurement day, when a plan starts, when an invoice falls due -
      // and every one of them is read against a year.
      //
      // It used to call shortDate, which is day and month. So a child born in
      // 2020 read "٤ أغسطس", a measurement from last year was indistinguish-
      // able from one taken this morning, and two invoices twelve months
      // apart looked like the same day. Ten fields, four of them list columns.
      //
      // shortDate is right where it is still used: a timestamp inside the
      // working period, printed next to its time, where the year is the
      // current one and saying so every row is noise. The difference is the
      // question the reader is asking, not the width of the column.
      return this.format.dayMonthYear(raw);
    }
    if (field.kind === 'ref' && field.ref) {
      // The name if it is known, the identifier if it is not. Never blank -
      // an empty cell where a number used to be reads as missing data.
      return this.refNames()[field.ref.resource]?.[raw] ?? raw;
    }
    if (field.kind === 'select' && field.options) {
      const option = field.options.find((item) => item.value === raw);
      return option ? this.i18n.translate(option.labelKey) : raw;
    }
    if (field.kind === 'switch') {
      // The service sends a JSON boolean, so `raw` is "true" or "false".
      // Printed as it arrives, a column of twelve sections read
      // "true / true / false" in the middle of an Arabic page.
      return this.i18n.translate(raw === 'true' ? 'flag.yes' : 'flag.no');
    }
    return raw;
  }

  /**
   * A checkbox writing into a string control.
   *
   * Every control on this screen is a FormControl<string> - that is what
   * buildControls makes and what save() reads. Rather than give one field
   * kind its own typed control and two code paths, the checkbox stores the
   * same two strings a select would, and save() is the single place that
   * turns them back into a boolean.
   */
  protected setSwitch(field: FieldSpec, event: Event): void {
    const checked = (event.target as HTMLInputElement).checked;
    this.controls()[field.name]?.setValue(checked ? 'true' : 'false');
  }

  /**
   * Archived means the service set active_flg false. Checked for `false`, not
   * for falsiness: the field is absent from some projections, and an absent
   * flag is "not known" - claiming a row is archived on that basis would
   * strike out a live record's name.
   */
  protected isArchived(row: Row): boolean {
    return row['active_flg'] === false;
  }

  protected statusKey(row: Row): string {
    if (this.isArchived(row)) {
      return 'status.archived';
    }
    const column = this.spec().statusColumn;
    const value = column ? this.cell(row, column) : '';
    return value ? `${this.spec().statusPrefix ?? 'status.'}${value}` : 'status.active';
  }

  protected statusTone(row: Row): string {
    if (this.isArchived(row)) {
      return 'hbh-badge--muted';
    }
    const column = this.spec().statusColumn;
    const value = column ? this.cell(row, column) : '';
    return !value || value === 'ACTIVE' ? 'hbh-badge--success' : 'hbh-badge--info';
  }

  protected startCreate(): void {
    this.openEditor({});
  }

  protected startEdit(row: Row): void {
    this.openEditor(row);
  }

  protected cancel(): void {
    this.editing.set(null);
    this.embeddedRes?.onClose(false);
  }

  protected save(event?: Event): void {
    event?.preventDefault();
    const current = this.editing();
    if (!current || this.saving()) {
      return;
    }

    // Refuse an empty required field here, before the request. The service
    // would refuse it too - this only saves a round trip and names the field.
    const controls = this.controls();
    const missing = this.formFields().find(
      (field) => field.required && !controls[field.name]?.value.trim());
    if (missing) {
      this.formError.set('error.field.REQUIRED');
      this.badField.set(missing.name);
      this.toast.warning(this.i18n.currentLang() === 'ar' ? 'يوجد بيانات إلزامية — يرجى تعبئة جميع البيانات المطلوبة' : 'Please fill in all required fields.');
      return;
    }

    // Only the fields this resource declares. Never the id, the centre, or
    // the archive flag.
    const body: Record<string, unknown> = {};
    // formFields, not every field: a status sent on a create is refused by
    // the service, and the dialogue no longer offers one.
    for (const field of this.formFields()) {
      // A read-only field is drawn so the row can be identified and is not
      // the person's to change. Sending it would be a key outside the
      // service's allow list - a 400 that names the field and not the
      // reason.
      if (field.readOnly) {
        continue;
      }
      const value = controls[field.name]?.value.trim() ?? '';
      if (value === '') {
        continue;
      }
      // A boolean, not the string "false". The column is boolean, and the
      // skip above is why this matters more than it looks: "false" is a
      // non-empty string and does reach here, so the one thing that must
      // not happen is it arriving as text that only coincidentally casts.
      if (field.kind === 'switch') {
        body[field.name] = value === 'true';
        continue;
      }
      body[field.name] = field.kind === 'number' ? Number(value) : value;
    }

    // An explicit null for whatever the trigger no longer allows. Leaving it
    // unsent is not the same thing: a PATCH carries only what it names, so
    // the row would keep its old action_code under a new PERIOD trigger and
    // ck_nps_shape would refuse a value the person can no longer see.
    for (const field of this.clearedFields()) {
      body[field.name] = null;
    }

    this.saving.set(true);
    this.formError.set('');
    this.badField.set(null);

    const id = current[this.spec().idColumn] as number | undefined;
    const call: Observable<unknown> = this.spec().resource === 'caseload'
      // The caseload has two doors and only this one carries the rules; see
      // OpsApi.assignCaseload. There is no edit branch because the row IS
      // its three columns - changing one is a different assignment, which
      // is ended and made again rather than patched (HBH-103).
      ? this.api.assignCaseload(
        Number(body['child_id']), Number(body['therapist_id']),
        Number(body['service_id']), body['is_primary_flg'] === true)
      : id === undefined
        ? this.api.create(this.spec().resource, body)
        : this.api.update(this.spec().resource, id, body);

    call.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: () => {
        this.saving.set(false);
        this.editing.set(null);
        this.toast.show(this.i18n.translate(id === undefined ? 'crud.created' : 'crud.updated'));
        // Embedded, the caller re-reads its own rows; there is no list here.
        if (this.embeddedRes) {
          this.embeddedRes.onClose(true);
        } else {
          this.load();
        }
      },
      error: (error: unknown) => {
        this.saving.set(false);
        const refusal = readRefusal(error);
        this.formError.set(refusalKey(refusal));
        // Naming the field turns "invalid input" into something the person at
        // the desk can fix without guessing which box is wrong.
        this.badField.set(refusal.field);
      },
    });
  }

  /**
   * Whether this row may be edited in place.
   *
   * A caseload row is its three columns - uix_caseload_live is keyed on
   * (therapist, child, service) - so changing any of them means it was a
   * different assignment all along. PATCHing one through the generic door
   * would move the row with none of assign_therapist's rules: the same
   * defect as the bare insert, only quieter because nothing is created.
   * End it and assign again (HBH-103).
   */
  protected canEditRow(_row: Row): boolean {
    return this.spec().resource !== 'caseload';
  }

  protected archive(row: Row): void {
    if (this.spec().resource === 'caseload') {
      this.write(
        this.api.endCaseload(Number(row['child_id']), this.idOf(row)),
        'crud.archived');
      return;
    }
    this.write(this.api.archive(this.spec().resource, this.idOf(row)), 'crud.archived');
  }

  protected restore(row: Row): void {
    this.write(this.api.restore(this.spec().resource, this.idOf(row)), 'crud.restored');
  }

  protected idOf(row: Row): number {
    return row[this.spec().idColumn] as number;
  }

  private write(call: Observable<unknown>, successKey: string): void {
    call.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: () => {
        this.toast.show(this.i18n.translate(successKey));
        this.load();
      },
      // The service's refusal, in the console's words. Never a status code.
      error: (error: unknown) =>
        this.toast.error(refusalSentence(this.i18n, error)),
    });
  }

  private openEditor(row: Row): void {
    this.editing.set(row);
    this.formError.set('');
    this.badField.set(null);
    const controls = this.controls();
    for (const field of this.spec().fields) {
      const stored = this.cell(row, field.name);
      // Creating: a select keeps its first option rather than being blanked.
      const fallback = field.kind === 'select' ? field.options?.[0]?.value ?? '' : '';
      controls[field.name]?.setValue(stored || fallback);
    }
  }

  private buildControls(): void {
    const controls: Record<string, FormControl<string>> = {};
    for (const field of this.spec().fields) {
      // A select starts on its first option, not empty.
      //
      // An empty select still renders showing that first option, so the form
      // looks filled while the control holds "" - and the submit, which skips
      // empty values, sends nothing. The service then refuses REQUIRED for a
      // field the person can see a value in. Same class of defect as a
      // placeholder that looks like a typed value.
      // A switch starts off, for the same reason: "" would draw an unticked
      // box while the control holds nothing, and save() skips empty values -
      // so an untouched switch would send no column at all rather than the
      // "no" the person can see.
      const initial = field.kind === 'select' ? field.options?.[0]?.value ?? ''
        : field.kind === 'switch' ? 'false' : '';
      controls[field.name] = new FormControl(initial, { nonNullable: true });
    }
    this.controls.set(controls);

    // The old subscriptions belong to controls nobody holds any more.
    this.valueWatch?.unsubscribe();
    this.valueWatch = new Subscription();
    const publish = () => this.values.set(
      Object.fromEntries(
        Object.entries(controls).map(([name, control]) => [name, control.value])));
    for (const control of Object.values(controls)) {
      this.valueWatch.add(control.valueChanges.subscribe(publish));
    }
    publish();
  }

  /** Whether a `showWhen` field's condition currently holds. */
  private isShown(field: FieldSpec): boolean {
    const rule = field.showWhen;
    if (!rule) {
      return true;
    }
    return rule.equals.includes(this.values()[rule.field] ?? '');
  }
}
