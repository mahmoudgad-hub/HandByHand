import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { HttpClient } from '@angular/common/http';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { ModalDialog } from '@hbh/shared/a11y/modal-dialog';

import { readRefusal, refusalKey } from '../../core/api/ops-error';
import { OpsAuthService } from '../../core/auth/ops-auth.service';

/** One row: what it is, what it holds, and where it is really stored. */
interface Setting {
  readonly labelKey: string;
  readonly value: string;
  /** The column or parameter behind it, shown so nobody hunts for it. */
  readonly source: string;
  readonly noteKey?: string;
  readonly ltr?: boolean;
  /**
   * The name PATCH /settings/center accepts, or undefined when the field
   * cannot be written at all.
   *
   * `code` is the only one without it. That is not a screen decision: it
   * carries no UPDATE grant and the trigger refuses it besides, because the
   * seeds and the site exporter match on the value and a rename leaves them
   * matching nothing - which is an empty result reported as success.
   */
  readonly field?: 'name_ar' | 'country_code' | 'currency_code' | 'time_zone' | 'weekend_days';
}

/** One entry of GET /settings/time-zones. */
interface TimeZone {
  readonly name: string;
  /** Minutes east of UTC, as it stands today. */
  readonly offsetMinutes: number;
}

/** The zones under one region heading, for an <optgroup>. */
interface ZoneGroup {
  readonly region: string;
  readonly zones: readonly { readonly name: string; readonly label: string }[];
}

/** "+03:00" · "-04:30" · "+00:00". */
function offsetLabel(minutes: number): string {
  const sign = minutes < 0 ? '-' : '+';
  const abs = Math.abs(minutes);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${sign}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`;
}

/**
 * Five hundred names into region headings.
 *
 * The prefix before the slash is the grouping the IANA database already uses,
 * so nothing here invents a taxonomy - it reads the one in the name. `UTC` has
 * no slash and gets its own heading rather than being dropped or filed under
 * something it is not.
 *
 * The label carries the offset because five hundred names are unreadable
 * without one, and somebody looking for their own zone recognises the number
 * faster than the city. It is TODAY's offset: a zone on summer time answers
 * differently in January, which is a property of the zone and not a fault in
 * the list.
 */
function groupZones(zones: readonly TimeZone[]): readonly ZoneGroup[] {
  const byRegion = new Map<string, { name: string; label: string }[]>();
  for (const zone of zones) {
    const slash = zone.name.indexOf('/');
    const region = slash === -1 ? zone.name : zone.name.slice(0, slash);
    const city = slash === -1 ? zone.name : zone.name.slice(slash + 1).replace(/_/g, ' ');
    const list = byRegion.get(region) ?? [];
    list.push({ name: zone.name, label: `${city}  (${offsetLabel(zone.offsetMinutes)})` });
    byRegion.set(region, list);
  }
  return [...byRegion.entries()].map(([region, list]) => ({ region, zones: list }));
}

/** One row of hbh.sys_params, as the service resolves it for this centre. */
export interface CenterParam {
  readonly code: string;
  readonly value: string;
  readonly dataType: string;
  readonly descriptionAr: string | null;
  readonly editable: boolean;
  /** True when this centre has its own value beside the shipped default. */
  readonly overridden: boolean;
  readonly defaultValue: string | null;
}

/**
 * The centre's own settings.
 *
 * TWO HALVES, WRITTEN THROUGH TWO DIFFERENT DOORS.
 *
 * The centre ROW is read from GET /me and written with
 * PATCH /api/v1/settings/center. Its rules are not here and not in the Go
 * handler either - migration 0051 put them in three separate places because
 * they answer three separate questions: a column GRANT decides which columns
 * may move at all (`code` has none), the RLS policy asks for SETTINGS.MANAGE,
 * and a BEFORE trigger judges the change itself. So a caller who cannot write
 * is refused by the POLICY, which matches no row - and the screen learns that
 * as a 404, not as a permission message it invented.
 *
 * The PARAMETERS below it: GET /api/v1/settings/params lists
 * them and PATCH writes one. Whether a parameter may be changed at all is
 * `editable`, and it is decided in the database - hbh.sys_params.editable_flg,
 * checked again inside hbh.set_center_param. What this screen does with the
 * flag is DRAW or NOT DRAW a pencil. That is a courtesy to the person, never
 * the control: hiding a button is not authorisation, and a caller who sends
 * the request anyway is refused by the function.
 *
 * WHY A CHANGE IS AN OVERRIDE, and why the screen says so. The shipped
 * default stays in its own row and is never touched; a centre's value sits
 * beside it. So "معدَّل" on a row is not decoration - it is the difference
 * between a value somebody chose and a value that came with the system, and
 * it is what tells you there is something to return to.
 */
@Component({
  selector: 'hbh-settings',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon, TranslatePipe, Skeleton, ErrorNote, ModalDialog],
  templateUrl: './settings.html',
})
export class Settings {
  protected readonly auth = inject(OpsAuthService);
  private readonly i18n = inject(I18nService);
  private readonly http = inject(HttpClient);
  private readonly toast = inject(ToastService);
  private readonly destroyRef = inject(DestroyRef);
  private readonly settingsBase = `${inject(HBH_CONFIG).apiBaseUrl}/api/v1/settings`;
  private readonly base = `${this.settingsBase}/params`;
  private readonly centreBase = `${this.settingsBase}/center`;

  protected readonly params = signal<readonly CenterParam[]>([]);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);

  /** The row being edited, or null. */
  protected readonly editing = signal<CenterParam | null>(null);
  protected readonly draft = signal('');
  protected readonly saving = signal(false);
  protected readonly formError = signal('');

  protected readonly editableCount = computed(
    () => this.params().filter((p) => p.editable).length);

  constructor() {
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    this.http.get<{ params?: readonly CenterParam[] }>(this.base)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (body) => {
          this.params.set(body.params ?? []);
          this.loading.set(false);
        },
        error: () => {
          this.failed.set(true);
          this.loading.set(false);
        },
      });
  }

  protected startEdit(param: CenterParam): void {
    this.formError.set('');
    this.draft.set(param.value);
    this.editing.set(param);
  }

  protected cancel(): void {
    this.editing.set(null);
  }

  protected setDraft(value: string): void {
    this.draft.set(value);
  }

  protected save(event?: Event): void {
    event?.preventDefault();
    const param = this.editing();
    if (!param || this.saving()) {
      return;
    }
    const value = this.draft().trim();
    if (!value) {
      // The database refuses this too, with its own code. Refusing it here
      // as well only saves a round trip - it does not decide anything.
      this.formError.set('error.field.REQUIRED');
      return;
    }

    this.saving.set(true);
    this.formError.set('');
    this.http.patch<{ code: string; value: string }>(
      `${this.base}/${encodeURIComponent(param.code)}`, { value })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.saving.set(false);
          this.editing.set(null);
          this.toast.show(this.i18n.translate('settings.saved'));
          this.load();
        },
        error: (error: unknown) => {
          this.saving.set(false);
          this.formError.set(refusalKey(readRefusal(error)));
        },
      });
  }

  /** The code whose override is being cleared, so its button can wait. */
  protected readonly clearing = signal('');

  /**
   * Return one parameter to the value it shipped with.
   *
   * DELETE is what the person means and not what happens: the override row is
   * deactivated and kept, because no table in this schema carries a DELETE
   * grant and the trail of who set what is worth more than the row is worth
   * removing. The service answers with the value now in force.
   *
   * No confirmation dialogue. The action is reversible in one click - the
   * pencil beside it sets the value again - and an "are you sure" in front of
   * something undoable teaches people to dismiss the ones that matter.
   */
  protected clear(param: CenterParam): void {
    if (this.clearing()) {
      return;
    }
    this.clearing.set(param.code);
    this.http.delete<{ code: string; value: string }>(
      `${this.base}/${encodeURIComponent(param.code)}`)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (body) => {
          this.clearing.set('');
          this.toast.show(
            `${this.i18n.translate('settings.reset')} ${body.value}`);
          this.load();
        },
        error: (error: unknown) => {
          this.clearing.set('');
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error))));
        },
      });
  }

  // ------------------------------------------------------------------
  // The centre row
  // ------------------------------------------------------------------

  /** The centre field being edited, or null. */
  protected readonly editingCentre = signal<Setting | null>(null);
  protected readonly centreDraft = signal('');
  /** The weekend, while it is being edited. ISO numbers, Monday is 1. */
  protected readonly weekendDraft = signal<readonly number[]>([]);
  protected readonly centreError = signal('');

  /** Monday to Sunday, in the order the checkboxes are drawn. */
  protected readonly weekdays = [1, 2, 3, 4, 5, 6, 7];

  /** The zones the server can actually resolve, grouped by region. */
  protected readonly zoneGroups = signal<readonly ZoneGroup[]>([]);
  protected readonly zonesLoading = signal(false);

  /**
   * Fetch the zone list, once, the first time it is needed.
   *
   * Not on screen load: five hundred names are twenty-four kilobytes, and a
   * settings screen is opened to read it far more often than to change the
   * one field that needs them.
   */
  private loadZones(): void {
    if (this.zoneGroups().length || this.zonesLoading()) {
      return;
    }
    this.zonesLoading.set(true);
    this.http.get<{ zones?: readonly TimeZone[] }>(`${this.settingsBase}/time-zones`)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (body) => {
          this.zoneGroups.set(groupZones(body.zones ?? []));
          this.zonesLoading.set(false);
        },
        error: () => {
          // The box falls back to free text, and the database still refuses a
          // name it does not know. A picker that cannot load is a reason to
          // type, not a reason to be unable to.
          this.zonesLoading.set(false);
        },
      });
  }

  protected startEditCentre(row: Setting): void {
    if (!row.field) {
      return;
    }
    this.centreError.set('');
    const me = this.auth.me();
    if (row.field === 'time_zone') {
      this.loadZones();
    }
    if (row.field === 'weekend_days') {
      this.weekendDraft.set([...(me?.weekendDays ?? [])]);
    } else {
      // The RAW value, not the rendered one. The weekend is the only field
      // whose display differs from what the service takes, and it has its own
      // control; the rest are the stored string.
      this.centreDraft.set(row.value);
    }
    this.editingCentre.set(row);
  }

  protected cancelCentre(): void {
    this.editingCentre.set(null);
  }

  protected setCentreDraft(value: string): void {
    this.centreDraft.set(value);
  }

  protected weekendHas(day: number): boolean {
    return this.weekendDraft().includes(day);
  }

  protected toggleWeekend(day: number, on: boolean): void {
    const next = this.weekendDraft().filter((d) => d !== day);
    this.weekendDraft.set(on ? [...next, day].sort((a, b) => a - b) : next);
  }

  protected saveCentre(event?: Event): void {
    event?.preventDefault();
    const row = this.editingCentre();
    if (!row?.field || this.saving()) {
      return;
    }

    // One field per request. The service can take several, but the screen
    // edits one row at a time - and that is what lets a refusal the database
    // raised without a constraint name still be attached to the right box.
    const body: Record<string, unknown> = {};
    if (row.field === 'weekend_days') {
      body['weekend_days'] = this.weekendDraft();
    } else {
      const value = this.centreDraft().trim();
      if (!value) {
        this.centreError.set('error.field.REQUIRED');
        return;
      }
      body[row.field] = value;
    }

    this.saving.set(true);
    this.centreError.set('');
    this.http.patch(`${this.centreBase}`, body)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.saving.set(false);
          this.editingCentre.set(null);
          this.toast.show(this.i18n.translate('settings.saved'));
          // /me is where this screen - and the shell's centre name, and the
          // day window every diary screen resolves - read the row from. Not
          // reloading it would leave the console showing the old value
          // everywhere except the table that was just edited.
          this.auth.loadIdentity()
            .pipe(takeUntilDestroyed(this.destroyRef)).subscribe();
        },
        error: (error: unknown) => {
          this.saving.set(false);
          this.centreError.set(refusalKey(readRefusal(error)));
        },
      });
  }

  protected readonly centre = computed<readonly Setting[]>(() => {
    const me = this.auth.me();
    if (!me) {
      return [];
    }
    return [
      {
        labelKey: 'settings.centreName', value: me.centerName,
        source: 'centers.name_ar', field: 'name_ar',
      },
      {
        labelKey: 'settings.centreCode', value: me.centerCode,
        source: 'centers.code', ltr: true,
        noteKey: 'settings.centreCodeNote',
      },
      {
        labelKey: 'settings.country', value: me.countryCode,
        source: 'centers.country_code', ltr: true, field: 'country_code',
      },
      {
        labelKey: 'settings.currency', value: me.currency,
        source: 'centers.currency_code', ltr: true, field: 'currency_code',
        noteKey: 'settings.currencyNote',
      },
      {
        labelKey: 'settings.timeZone', value: me.timeZone,
        source: 'centers.time_zone', ltr: true, field: 'time_zone',
        noteKey: 'settings.timeZoneNote',
      },
      {
        labelKey: 'settings.weekend', value: this.weekendText(me.weekendDays),
        source: 'centers.weekend_days', field: 'weekend_days',
        noteKey: 'settings.weekendNote',
      },
    ];
  });

  /**
   * The weekend as day names, from ISO numbers where Monday is 1.
   *
   * Read from the centre's row, never assumed: Friday and Saturday is what
   * Egypt does, and it is a value here rather than a constant precisely so
   * that a centre somewhere else is a row and not a code change.
   */
  private weekendText(days: readonly number[]): string {
    const names = days.map((day) => this.i18n.translate(`weekday.${day}`));
    return this.i18n.list(names);
  }
}
