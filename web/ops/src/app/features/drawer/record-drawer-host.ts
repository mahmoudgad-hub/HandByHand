import {
  ChangeDetectionStrategy, Component, DestroyRef, ElementRef, computed, effect, inject, signal, untracked,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { HttpErrorResponse } from '@angular/common/http';
import { Router } from '@angular/router';
import { Observable, catchError, map, of, switchMap } from 'rxjs';

import { ModalDialog } from '@hbh/shared/a11y/modal-dialog';
import { FormatService } from '@hbh/shared/format/format.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { ChildApi } from '../../core/api/child-api';
import { Row } from '../../core/api/ops-api';
import { readAllPages } from '../../core/api/read-all-pages';
import { ActionDialogService } from '../../core/ops/action-dialog.service';
import { DayApi } from '../../core/ops/day-api';
import { APPOINTMENTS_SPEC, INVOICES_SPEC, readText } from '../../core/ops/day-spec';
import {
  DrawerChild, DrawerStep, DrawerTarget, childIdFromPath, formatOpen, stepFor,
} from '../../core/ops/record-drawer';
import { DrawerState, RecordDrawerService } from '../../core/ops/record-drawer.service';
import { AppointmentPanel } from './appointment-panel';
import { InvoicePanel } from './invoice-panel';

type Phase = 'loading' | 'ready' | 'notFound' | 'failed';
type PartState = 'idle' | 'loading' | 'ready' | 'failed';

/** What a read of the record settles: the row and the child it is about. */
interface Located {
  readonly row: Row;
  readonly child: DrawerChild | null;
}

/**
 * The one place a record drawer is drawn, beside every screen (shell).
 *
 * It draws whatever RecordDrawerService says is open - an appointment or
 * an invoice - as a `<dialog>` at the side of the page. The page behind
 * stays where it was: the same route, the same tab, the same scroll,
 * because the drawer is not a navigation. Closing it rewrites `?open=`
 * off the address and nothing else moves.
 *
 * ONE RECORD IS READ, where the service has a way to read one. An invoice
 * has `GET /invoices/{id}` and is read there. An appointment has no
 * single-row read, so a row the caller did not hand over is LOCATED in
 * the smallest list that can hold it: the child's diary when a child is
 * known (from the caller, or from a /children/:id address), otherwise
 * today's diary. A row not in either is reported as not found, in the
 * drawer, and nothing is guessed.
 *
 * ACTIONS ARE THE LIST'S. A button in a panel names one of day-spec's
 * actions; this host asks ActionDialogService to open it, exactly as the
 * list would, and re-reads the record when the dialog reports DONE.
 * `?action=` does the same on arrival - offered, never run.
 */
@Component({
  selector: 'hbh-record-drawer-host',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [ModalDialog, Icon, TranslatePipe, Skeleton, EmptyState, ErrorNote, AppointmentPanel, InvoicePanel],
  templateUrl: './record-drawer-host.html',
  styleUrl: './record-drawer-host.css',
})
export class RecordDrawerHost {
  protected readonly svc = inject(RecordDrawerService);
  private readonly dialogs = inject(ActionDialogService);
  private readonly day = inject(DayApi);
  private readonly childApi = inject(ChildApi);
  private readonly router = inject(Router);
  private readonly format = inject(FormatService);
  private readonly destroyRef = inject(DestroyRef);
  private readonly hostRef = inject<ElementRef<HTMLElement>>(ElementRef);

  protected readonly phase = signal<Phase>('loading');
  protected readonly record = signal<Row | null>(null);
  protected readonly child = signal<DrawerChild | null>(null);
  protected readonly guardians = signal<readonly Row[] | null>(null);
  protected readonly guardiansState = signal<PartState>('idle');
  /** A one-line answer when a step could not be opened (denied, not applicable). */
  protected readonly notice = signal('');

  protected readonly entity = computed(() => this.svc.active()?.target.entity ?? null);
  protected readonly kindKey = computed(
    () => (this.entity() === 'invoice' ? 'drawer.invoice' : 'drawer.appointment'));
  protected readonly title = computed(() => {
    const row = this.record();
    const target = this.svc.active()?.target;
    if (!target) {
      return '';
    }
    const no = row ? readText(row, target.entity === 'invoice' ? 'invoice_no' : 'appointment_no') : '';
    return no || `#${target.id}`;
  });
  protected readonly statusKey = computed(() => {
    const row = this.record();
    const status = row ? readText(row, 'status') : '';
    if (!status) {
      return '';
    }
    return `${this.entity() === 'invoice' ? INVOICES_SPEC.statusPrefix : APPOINTMENTS_SPEC.statusPrefix}${status}`;
  });
  protected readonly statusTone = computed(() => {
    const row = this.record();
    const status = row ? readText(row, 'status') : '';
    return this.entity() === 'invoice' ? INVOICES_SPEC.tone(status) : APPOINTMENTS_SPEC.tone(status);
  });

  private version = 0;
  private shownKey = '';

  /** Focus the first verb, or the close button when there is none, once the dialog above has gone. */
  private refocus(): void {
    setTimeout(() => {
      const root = this.hostRef.nativeElement;
      root.querySelector<HTMLElement>('.rd__actions button, .hbh-drawer__head .hbh-iconbtn')?.focus();
    }, 0);
  }

  constructor() {
    // Draw whatever the service says is open. The effect fires on every
    // change of the state object; only a change of RECORD reloads, and a
    // step asked for after the record is ready is offered at once.
    effect(() => {
      const state = this.svc.active();
      untracked(() => this.onState(state));
    });
  }

  private onState(state: DrawerState | null): void {
    if (!state) {
      this.version++;
      this.shownKey = '';
      this.record.set(null);
      this.child.set(null);
      this.guardians.set(null);
      this.guardiansState.set('idle');
      this.notice.set('');
      return;
    }
    const key = formatOpen(state.target);
    if (key !== this.shownKey) {
      this.shownKey = key;
      this.load(state);
      return;
    }
    if (state.action && this.phase() === 'ready') {
      this.offerStep(state);
    }
  }

  protected close(): void {
    void this.svc.close();
  }

  /** Reads the record again, after a change or on retry. */
  protected reload(): void {
    const state = this.svc.active();
    if (state) {
      this.svc.forget(state.target);
      this.load({ ...state, row: null });
    }
  }

  private load(state: DrawerState): void {
    const version = ++this.version;
    this.phase.set('loading');
    this.notice.set('');
    this.record.set(null);
    this.child.set(null);
    this.guardians.set(null);
    this.guardiansState.set('idle');

    const read$: Observable<Located | null> = state.target.entity === 'invoice'
      ? this.readInvoice(state)
      : this.locateAppointment(state);

    read$.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: (found) => {
        if (version !== this.version) {
          return;
        }
        if (!found) {
          this.phase.set('notFound');
          return;
        }
        this.record.set(found.row);
        this.child.set(found.child);
        this.phase.set('ready');
        this.svc.remember(state.target, found.row);
        if (found.child?.id) {
          this.loadGuardians(found.child.id, version);
        } else {
          this.guardiansState.set('ready');
          this.guardians.set([]);
        }
        // The step asked for NOW, not the one captured when the read began:
        // a task may have re-opened this record with a step while it loaded.
        const now = this.svc.active();
        if (now?.action) {
          this.offerStep(now);
        }
      },
      error: (error: unknown) => {
        if (version !== this.version) {
          return;
        }
        const status = error instanceof HttpErrorResponse ? error.status : 0;
        // "Not visible to you" and "no such row" are one answer from the
        // service (404 for both, on purpose); a refusal reads the same here.
        this.phase.set(status === 404 || status === 403 ? 'notFound' : 'failed');
      },
    });
  }

  // ---- reading ----

  private readInvoice(state: DrawerState): Observable<Located | null> {
    const id = state.target.id;
    return this.day.get('invoices', id).pipe(switchMap((detail) => {
      // The single-invoice read carries lines and payments and no child;
      // the list row the caller held (or the caller's context) names the
      // child. With neither, the page of the ledger this invoice is on is
      // asked once - a read too many for a deep link, and the only way to
      // print whose invoice this is.
      const known = childOf(state.row, state.context);
      if (known) {
        return of<Located>({ row: { ...detail, child: state.row?.['child'] }, child: known });
      }
      return readAllPages((page) => this.day.list('invoices', { status: readText(detail, 'status') || undefined, limit: 100, page })).pipe(
        map((rows) => rows.find((row) => Number(row['invoice_id']) === id) ?? null),
        catchError(() => of(null)),
        map((row): Located => ({ row: { ...detail, child: row?.['child'] }, child: childOf(row, undefined) })),
      );
    }));
  }

  private locateAppointment(state: DrawerState): Observable<Located | null> {
    const id = state.target.id;
    if (state.row) {
      return this.withChildName(state.row, childOf(state.row, state.context));
    }
    const url = this.router.url;
    const childId = state.context?.childId ?? childIdFromPath(url);
    if (childId) {
      return this.childApi.list(childId, 'appointments').pipe(
        map((rows) => rows.find((row) => Number(row['appointment_id']) === id) ?? null),
        switchMap((row) => (row
          ? this.withChildName(row, childOf(row, { ...state.context, childId }))
          : of(null))),
      );
    }
    // A copied link retains the appointment's instant, not personal data.
    // Search its UTC day, or the explicit diary date on an older link.
    const params = this.router.parseUrl(url).queryParams;
    const onDiary = /^\/appointments(?:[/?#]|$)/.test(url);
    const status = onDiary && APPOINTMENTS_SPEC.statusFilter.includes(params['status']) ? params['status'] : undefined;
    const instant = typeof params['recordAt'] === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(params['recordAt'])
      ? Date.parse(params['recordAt']) : NaN;
    const start = Math.floor(instant / 86_400_000) * 86_400_000;
    const window = Number.isFinite(start)
      ? { from: new Date(start).toISOString(), to: new Date(start + 86_400_000).toISOString() }
      : { date: /^\d{4}-\d{2}-\d{2}$/.test(params['date'] ?? '') ? params['date'] : this.format.today() };
    return readAllPages((page) => this.day.list('appointments', {
      ...window, limit: 100, page, status,
      mine: onDiary && params['view'] === 'mine' ? true : undefined,
    })).pipe(
      map((rows) => rows.find((row) => Number(row['appointment_id']) === id) ?? null),
      map((row): Located | null => (row ? { row, child: childOf(row, undefined) } : null)),
    );
  }

  /** A child known by id alone is named with one read; a named one is not read again. */
  private withChildName(row: Row, child: DrawerChild | null): Observable<Located> {
    if (!child || child.name || !child.id) {
      return of({ row, child });
    }
    return this.childApi.child(child.id).pipe(
      map((found): Located => ({
        row,
        child: { id: child.id, name: readText(found, 'full_name_ar'), no: readText(found, 'child_no') },
      })),
      catchError(() => of<Located>({ row, child })),
    );
  }

  private loadGuardians(childId: number, version: number): void {
    this.guardiansState.set('loading');
    this.childApi.guardians(childId)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (rows) => {
          if (version !== this.version) {
            return;
          }
          this.guardians.set(rows);
          this.guardiansState.set('ready');
        },
        error: () => {
          if (version === this.version) {
            this.guardiansState.set('failed');
          }
        },
      });
  }

  // ---- acting: every step is the owning list's dialog ----

  /** A step from a deep link or a task: resolved, consumed, then offered like any button. */
  private offerStep(state: DrawerState): void {
    const step = stepFor(state.target.entity, state.action);
    void this.svc.consumeAction();
    if (!step) {
      this.notice.set('drawer.notice.UNKNOWN_ACTION');
      return;
    }
    this.run(step);
  }

  /** A panel changed the record itself (a line removed): say so behind, and read it again. */
  protected onChanged(): void {
    const state = this.svc.active();
    if (state) {
      this.svc.notifyChanged(state.target);
      this.reload();
    }
  }

  protected run(step: DrawerStep): void {
    const state = this.svc.active();
    const row = this.record();
    if (!state || !row) {
      return;
    }
    const target: DrawerTarget = state.target;
    this.notice.set('');
    this.dialogs.open({
      actionType: step.actionType, entityType: step.entityType, entityId: target.id, row,
      source: 'RECORD_DRAWER', prefill: step.prefill,
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe((outcome) => {
        // The action's dialog is gone and the drawer is the top layer
        // again: put the keyboard back on it rather than on the page
        // behind, which is inert while the drawer is open.
        this.refocus();
        if (outcome === 'DONE') {
          // The record moved. Say so to the screen behind, and read it again.
          this.svc.notifyChanged(target);
          if (this.svc.active()) {
            this.reload();
          }
          return;
        }
        if (outcome === 'DENIED' || outcome === 'NOT_APPLICABLE' || outcome === 'UNKNOWN_ACTION') {
          this.notice.set(`drawer.notice.${outcome}`);
        }
      });
  }
}

/** The child a row or a caller's context names, or null. */
function childOf(row: Row | null | undefined, context: { childId?: number; childName?: string; childNo?: string } | undefined): DrawerChild | null {
  const nested = row?.['child'] as Record<string, unknown> | undefined | null;
  const id = Number(nested?.['child_id']);
  if (Number.isFinite(id) && id > 0) {
    return { id, name: String(nested?.['full_name_ar'] ?? ''), no: String(nested?.['child_no'] ?? '') };
  }
  if (context?.childId) {
    return { id: context.childId, name: context.childName ?? '', no: context.childNo ?? '' };
  }
  return null;
}
