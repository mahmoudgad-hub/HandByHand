import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { HttpClient } from '@angular/common/http';
import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { Router, RouterLink } from '@angular/router';

import { FormatService } from '@hbh/shared/format/format.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { OpsApi, Row } from '../../core/api/ops-api';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { DayApi } from '../../core/ops/day-api';
import { DASHBOARD_TILES, Tile } from './dashboard-tiles';
import { openAhead, runningNow, startable } from './day-summary';

/**
 * The first screen after signing in.
 *
 * It used to say "this dashboard is waiting for centre-indexed endpoints".
 * That was true when it was written and stopped being true the day they
 * arrived - and it stayed on screen afterwards, telling every member of staff
 * that data was unavailable while five screens behind it were reading that
 * same data happily. A stale sentence is worse than an empty panel: an empty
 * panel reads as unfinished, and a sentence reads as fact.
 *
 * So the figures are real, and the ones that cannot be real are absent rather
 * than approximated - see dashboard-tiles.ts.
 */
@Component({
  selector: 'hbh-dashboard',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Icon, TranslatePipe],
  templateUrl: './dashboard.html',
  styleUrl: './dashboard.css',
})
export class Dashboard {
  private readonly http = inject(HttpClient);
  private readonly config = inject(HBH_CONFIG);
  protected readonly metrics = signal<any>(null);
  protected rate(key: string): string { const a=this.metrics()?.attendance;return a?.total ? (100*a[key]/a.total).toFixed(1)+'%' : '—'; }
  private readonly day = inject(DayApi);
  private readonly crud = inject(OpsApi);
  private readonly destroyRef = inject(DestroyRef);
  private readonly router = inject(Router);
  protected readonly auth = inject(OpsAuthService);
  protected readonly format = inject(FormatService);

  /** The count per tile key, or null while it is still unknown. */
  protected readonly counts = signal<Record<string, number | null>>({});
  /** Tiles whose request was refused. Shown as a dash, never as zero. */
  protected readonly refused = signal<Record<string, boolean>>({});

  /**
   * Only the tiles this account may reach.
   *
   * The permission decides what to DRAW. It is not the control - the policy
   * under each query is - but drawing a figure somebody would be refused if
   * they clicked it wastes their time and teaches them to distrust the page.
   */
  protected readonly tiles = computed(
    () => DASHBOARD_TILES.filter((tile) => this.auth.can(tile.permission)));

  protected readonly greetingKey = computed(
    () => `dash.greet.${this.format.partOfDay()}`);

  protected readonly today = computed(() => this.format.fullDate(new Date()));

  protected readonly rooms = signal<readonly Row[]>([]);
  protected readonly roomsState = signal('loading');
  protected readonly alerts = computed(() => this.tiles().filter(t => this.needsAction(t)));
  protected readonly agenda = signal<Record<string, number>>({});
  protected readonly agendaFailed = signal(false);
  protected readonly agendaParts = [{key:'COMPLETED',label:'مكتملة',color:'#2eaa88'},{key:'CHECKED_IN',label:'حضروا',color:'#e0a326'},{key:'BOOKED',label:'محجوزة',color:'#288797'},{key:'CONFIRMED',label:'مؤكدة',color:'#76b7cb'},{key:'CANCELLED',label:'ملغاة',color:'#d66562'},{key:'NO_SHOW',label:'لم يحضروا',color:'#9279ba'}];
  protected readonly agendaCount = computed(() => Object.keys(this.agenda()).length);
  protected readonly agendaTotal = computed(() => Object.values(this.agenda()).reduce((a,b)=>a+b,0));
  protected readonly ring = computed(() => { let offset=0;const total=this.agendaTotal();if(!total)return '#e8eff1';return 'conic-gradient('+this.agendaParts.map(p=>{const start=offset;offset+=(this.agenda()[p.key]||0)/total*100;return p.color+' '+start+'% '+offset+'%'}).join(',')+')'; });
  /**
   * A clinician's own day, on the first screen they see.
   *
   * EVERY PANEL ON THIS DASHBOARD WAS WRITTEN FOR SOMEBODY ELSE. Attendance
   * rates, enrolment leads, outstanding invoices, satisfaction - each is
   * gated on a permission a therapist does not hold, and correctly so.
   * What was left for them was a rooms panel printing "not available for
   * this account", a count of draft reports, and nothing about the work
   * they signed in to do. They then opened /my-day to find out.
   *
   * So this asks the question their morning actually asks - who is next,
   * at what time, and what state is it in - and it asks it of the same
   * endpoint /my-day uses, filtered to them by therapist_id.
   *
   * NOT A SECOND /my-day. It shows the next appointment and a count, and
   * links to the day itself for the rest. A dashboard that reproduced the
   * list would be a second place for the same rows to be right or wrong.
   */
  protected readonly myDay = signal<readonly Row[]>([]);
  protected readonly myDayState = signal<'loading' | 'ready' | 'failed'>('loading');

  /** True when this account has a caseload of its own to show. */
  protected readonly isClinician = computed(() => !!this.auth.me()?.therapistId);

  /**
   * The next appointment that has not happened yet.
   *
   * Cancelled and no-show rows are skipped: they are today's history, not
   * today's work, and putting one under "next" would send somebody to a
   * room for an appointment nobody is coming to. Completed is skipped for
   * the same reason.
   */
  protected readonly openToday = computed(
    () => openAhead(this.myDay(), Date.now()));

  protected readonly nextUp = computed(() => this.openToday()[0] ?? null);

  /** A session already running, which is a different thing from the next one. */
  protected readonly inProgress = computed(() => runningNow(this.myDay()));

  /** How many of today's appointments are still ahead, the running one included. */
  protected readonly remaining = computed(() => this.openToday().length);

  /** The appointment whose start is in flight, so the button cannot be pressed twice. */
  protected readonly starting = signal<number | null>(null);
  protected readonly startFailed = signal(false);

  /**
   * Whether "start the session" is offered on this row.
   *
   * THE THREE CONDITIONS ARE THE SCHEMA'S, NOT THIS SCREEN'S. A session
   * starts from CHECKED_IN and from nothing else (0005_scheduling.up.sql),
   * and only once - the appointment STAYS CHECKED_IN while its session
   * runs, so the status test alone would leave the button up afterwards
   * and a second press could only ever return HB022. They are copied from
   * day-spec's `start` action deliberately: this is a shortcut to the same
   * operation, and a shortcut that offers it under different conditions is
   * a second, quieter rule.
   *
   * The permission is drawn, not enforced, here. SESSION.START is checked
   * in the policy; hiding the button only spares somebody a refusal.
   */
  protected canStart(row: Row | null): boolean {
    return this.auth.can('SESSION.START') && startable(row);
  }

  /**
   * Starts it, then goes to /sessions.
   *
   * The navigation is the point of the shortcut: a therapist who presses
   * "start" is going to write in that session within the minute, and
   * leaving them on a dashboard with a changed badge would mean finding
   * the screen themselves. The panel is NOT reloaded first - the row it
   * would show is the session they are already being taken to.
   */
  protected startNow(row: Row): void {
    const id = Number(row['appointment_id']);
    if (!id || this.starting() !== null) {
      return;
    }
    this.starting.set(id);
    this.startFailed.set(false);
    this.day.startSession(id)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.starting.set(null);
          void this.router.navigate(['/sessions']);
        },
        // A refusal here is a real answer - HB022, a permission, a session
        // somebody else opened a second ago - and it is shown rather than
        // swallowed. The row stays as it is; `load()` re-asks the service.
        error: () => {
          this.starting.set(null);
          this.startFailed.set(true);
        },
      });
  }

  protected childName(row: Row | null): string {
    if (!row) {
      return '';
    }
    const child = row['child'] as Record<string, unknown> | undefined;
    return String(child?.['full_name_ar'] ?? '');
  }

  /**
   * The status in Arabic, from the same table the ring is drawn from.
   *
   * A code this build has not met falls through to the code itself rather
   * than to a blank: "BOOKED" tells a reader something, an empty cell does
   * not, and an unknown status is worth seeing rather than hiding.
   */
  protected statusLabel(row: Row | null): string {
    const code = String(row?.['status'] ?? '');
    return this.agendaParts.find((part) => part.key === code)?.label ?? code;
  }

  protected readonly toolbarPanel = signal<'alerts' | 'help' | null>(null);
  protected toggleToolbar(panel: 'alerts' | 'help'): void { this.toolbarPanel.update(current => current === panel ? null : panel); }
  constructor() {
    this.load();
  }

  protected load(): void {
    this.metrics.set(null);
    this.http.get(this.config.apiBaseUrl+'/api/v1/dashboard/metrics').pipe(takeUntilDestroyed(this.destroyRef)).subscribe({next:m=>this.metrics.set(m),error:()=>this.metrics.set(null)});
    this.roomsState.set('loading');
    if (this.auth.can('CATALOG.MANAGE')) this.crud.list('rooms',{limit:6}).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({next:p=>{this.rooms.set(p.rows);this.roomsState.set('ready')},error:()=>this.roomsState.set('failed')});
    else this.roomsState.set('denied');
    // The clinician's own day. Asked for only when this account HAS a
    // caseload - an administrator has no therapist row, and a request
    // filtered by a therapist_id that does not exist would return the whole
    // centre's day under a heading that says "yours".
    this.myDay.set([]);
    this.myDayState.set('loading');
    const mine = this.auth.me()?.therapistId;
    if (mine) {
      this.day.list('appointments', { therapist_id: mine, date: this.format.today(), limit: 50 })
        .pipe(takeUntilDestroyed(this.destroyRef))
        .subscribe({
          next: (page) => { this.myDay.set(page.rows); this.myDayState.set('ready'); },
          error: () => this.myDayState.set('failed'),
        });
    } else {
      this.myDayState.set('ready');
    }

    this.agenda.set({});this.agendaFailed.set(false);
    if(this.auth.can('APPOINTMENT.BOOK')) for(const part of this.agendaParts) this.day.list('appointments',{status:part.key,limit:1}).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({next:p=>this.agenda.update(a=>({...a,[part.key]:p.total})),error:()=>this.agendaFailed.set(true)});
    this.counts.set({});
    this.refused.set({});
    for (const tile of this.tiles()) {
      // limit=1 because only `total` is wanted. The row that comes back is
      // paid for either way; a thousand are not.
      const call = tile.resource === 'children'
        ? this.crud.list('children', { limit: 1 })
        : this.day.list(tile.resource, { ...tile.query, limit: 1 });

      call.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
        next: (page) => this.counts.update(
          (current) => ({ ...current, [tile.key]: page.total })),
        // A dash, not a zero. "0 new applications" and "we could not ask"
        // are different facts, and only one of them means nobody is waiting.
        error: () => {
          this.refused.update((current) => ({ ...current, [tile.key]: true }));
          this.counts.update((current) => ({ ...current, [tile.key]: null }));
        },
      });
    }
  }

  /**
   * Whether this tile's request came back refused.
   *
   * A method, not the signal read directly from the template: `refused(key)`
   * in a template calls the SIGNAL, which ignores the argument and returns
   * the whole record - always truthy, so every tile would have claimed it was
   * refused. It compiles and it is silent.
   */
  protected wasRefused(tile: Tile): boolean {
    return !!this.refused()[tile.key];
  }

  protected countOf(tile: Tile): string {
    if (this.refused()[tile.key]) {
      return '—';
    }
    const value = this.counts()[tile.key];
    return value === undefined || value === null ? '' : this.format.count(value);
  }

  protected isPending(tile: Tile): boolean {
    return this.counts()[tile.key] === undefined && !this.refused()[tile.key];
  }

  /** A tile worth acting on: something is waiting and the count says so. */
  protected needsAction(tile: Tile): boolean {
    return !!tile.wantsAction && (this.counts()[tile.key] ?? 0) > 0;
  }
}
