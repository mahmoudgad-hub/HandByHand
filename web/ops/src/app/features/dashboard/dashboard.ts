import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { HttpClient } from '@angular/common/http';
import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { Router, RouterLink } from '@angular/router';

import { FormatService } from '@hbh/shared/format/format.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { OpsApi, Row } from '../../core/api/ops-api';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { DayApi } from '../../core/ops/day-api';
import { RecordDrawerService } from '../../core/ops/record-drawer.service';
import { Task, TaskEntity } from '../../core/tasks/task-model';
import { TasksService } from '../../core/tasks/tasks.service';
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
  private readonly drawer = inject(RecordDrawerService);
  private readonly i18n = inject(I18nService);
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

  /**
   * The first five tasks, from the service the task inbox reads. Not a
   * second computation: the tiles above still count with `limit=1`, and
   * this panel shows what those counts are made of.
   */
  protected readonly tasks = inject(TasksService);
  protected readonly taskPreview = computed<readonly Task[]>(() => this.tasks.tasks().slice(0, 5));
  protected taskIcon(task: Task): 'ic-user-plus' | 'ic-users' | 'ic-calendar' | 'ic-activity' | 'ic-file' | 'ic-chat' | 'ic-receipt' | 'ic-user-check' {
    const byEntity: Record<TaskEntity, 'ic-user-plus' | 'ic-users' | 'ic-calendar' | 'ic-activity' | 'ic-file' | 'ic-chat' | 'ic-receipt' | 'ic-user-check'> = {
      CONVERSATION:'ic-chat',
      APPLICATION: 'ic-user-plus', BENEFICIARY: 'ic-users', APPOINTMENT: 'ic-calendar', SESSION: 'ic-activity',
      REPORT: 'ic-file', REQUEST: 'ic-chat', INVOICE: 'ic-receipt', THERAPIST: 'ic-user-check',
    };
    return byEntity[task.entityType];
  }
  protected readonly agenda = signal<Record<string, number>>({});
  protected readonly agendaFailed = signal(false);
  protected readonly agendaParts = [{key:'COMPLETED',labelKey:'status.appointment.COMPLETED',color:'#2eaa88'},{key:'CHECKED_IN',labelKey:'status.appointment.CHECKED_IN',color:'#e0a326'},{key:'BOOKED',labelKey:'status.appointment.BOOKED',color:'#288797'},{key:'CONFIRMED',labelKey:'status.appointment.CONFIRMED',color:'#76b7cb'},{key:'CANCELLED',labelKey:'status.appointment.CANCELLED',color:'#d66562'},{key:'NO_SHOW',labelKey:'status.appointment.NO_SHOW',color:'#9279ba'}];
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
    const part = this.agendaParts.find((item) => item.key === code);
    return part ? this.i18n.translate(part.labelKey) : code;
  }

  protected readonly toolbarPanel = signal<'alerts' | 'help' | null>(null);
  protected toggleToolbar(panel: 'alerts' | 'help'): void { this.toolbarPanel.update(current => current === panel ? null : panel); }

  /** A task about an appointment or an invoice opens in the drawer, beside this page. */
  protected openTask(task: Task): void {
    const target = task.primaryAction.drawer;
    if (!target) {
      return;
    }
    this.toolbarPanel.set(null);
    void this.drawer.open({
      entity: target.entity, id: target.id, action: target.action, source: 'DASHBOARD',
      row: task.row && task.entityId === target.id ? task.row : undefined,
      context: task.childId ? { childId: task.childId, childName: task.childName } : undefined,
    });
  }

  constructor() {
    this.load();
    // A record changed from the drawer: the figures and the preview that
    // counted it are read again. The page is not rebuilt.
    this.drawer.changed$
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe(() => this.load());
  }

  protected load(): void {
    this.metrics.set(null);
    // The preview panel and the sidebar badge read the same signal; asking
    // here makes the first screen's preview fresh without a second read
    // when the person then opens the inbox.
    this.tasks.refreshIfStale(0);
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
    // KPI tiles read as figures, not prose: Latin digits (the rule in
    // FormatService.number, #22). count() is for a number inside a sentence.
    return value === undefined || value === null ? '' : this.format.number(value);
  }

  protected isPending(tile: Tile): boolean {
    return this.counts()[tile.key] === undefined && !this.refused()[tile.key];
  }

  /** A tile worth acting on: something is waiting and the count says so. */
  protected needsAction(tile: Tile): boolean {
    return !!tile.wantsAction && (this.counts()[tile.key] ?? 0) > 0;
  }
}
