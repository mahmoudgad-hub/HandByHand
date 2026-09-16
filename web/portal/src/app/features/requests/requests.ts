import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  inject,
  signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute } from '@angular/router';
import { FormControl, ReactiveFormsModule, Validators } from '@angular/forms';

import { PortalApi } from '../../core/api/portal-api';
import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { ChildContextService } from '../../core/auth/child-context.service';
import { loadErrorKey, traceIdFor } from '../../core/api/portal-error';
import { FormatService } from '@hbh/shared/format/format.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { DateParts } from '@hbh/shared/ui/date-parts';
import { AppointmentSummary, ParentRequest, RequestKind } from '../../core/models/portal.models';
import { Icon, IconName } from '@hbh/shared/icon/icon';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { StatusBadge } from '../../shared/ui/status-badge';

/**
 * Asking reception for something, and seeing what came of it.
 *
 * A request changes nothing on its own. Moving an appointment depends on a
 * therapist and a room being free, and that is reception's decision - so this
 * screen submits a request and then reports its state, and never edits an
 * appointment itself.
 */
@Component({
  selector: 'hbh-requests',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    ReactiveFormsModule, Icon, TranslatePipe, StatusBadge,
    Skeleton, EmptyState, ErrorNote, DateParts,
  ],
  templateUrl: './requests.html',
  styleUrl: './requests.css',
})
export class Requests {
  private readonly api = inject(PortalApi);
  private readonly childContext = inject(ChildContextService);
  private readonly config = inject(HBH_CONFIG);
  private readonly destroyRef = inject(DestroyRef);
  private readonly route = inject(ActivatedRoute);
  private readonly toast = inject(ToastService);
  private readonly i18n = inject(I18nService);
  protected readonly format = inject(FormatService);

  protected readonly kinds: readonly { kind: RequestKind; icon: IconName }[] = [
    { kind: 'RESCHEDULE', icon: 'ic-cal-plus' },
    { kind: 'CANCEL', icon: 'ic-x-circle' },
    { kind: 'CALLBACK', icon: 'ic-phone' },
  ];

  protected readonly items = signal<readonly ParentRequest[]>([]);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);
  protected readonly failureKey = signal('error.load');
  /** Shown only where nobody can act on the failure. */
  protected readonly traceId = signal<string | null>(null);

  /** The kind being composed, or null when no form is open. */
  protected readonly drafting = signal<RequestKind | null>(null);
  protected readonly sending = signal(false);
  protected readonly note = new FormControl('', { nonNullable: true, validators: [Validators.maxLength(500)] });
  protected readonly appointments = signal<readonly AppointmentSummary[]>([]);
  protected readonly appointmentsLoading = signal(true);
  protected readonly appointmentsFailed = signal(false);
  protected readonly appointmentId = new FormControl('', { nonNullable: true });
  protected readonly alternativeDate = new FormControl('', { nonNullable: true });
  protected readonly alternativeTime = new FormControl('', { nonNullable: true });
  protected readonly today = this.centreNow().slice(0, 10);

  constructor() {
    // Arrive with a kind already chosen, when the screen that sent you here
    // knew which one. The home screen's "ask them to call me" is the case:
    // landing on a menu of three and having to pick the one you just pressed
    // is a step that exists only because the two screens do not talk.
    //
    // The value is checked against the list rather than trusted: it comes
    // from the address bar, and an unknown kind opens no form at all rather
    // than composing a request the service would refuse.
    const wanted = this.route.snapshot.queryParamMap.get('kind');
    if (wanted && this.kinds.some((entry) => entry.kind === wanted)) {
      this.drafting.set(wanted as RequestKind);
    }
    this.load();
    this.loadAppointments();
  }

  protected loadAppointments(): void {
    this.appointmentsLoading.set(true);
    this.appointmentsFailed.set(false);
    this.api.appointments(this.childContext.requireId(), 'upcoming')
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: items => {
          this.appointments.set(items.filter(a => ['BOOKED', 'CONFIRMED'].includes(a.status)));
          const wanted = this.route.snapshot.queryParamMap.get('appointment');
          if (wanted && this.appointments().some(a => a.id === wanted)) this.appointmentId.setValue(wanted);
          this.appointmentsLoading.set(false);
        },
        error: () => { this.appointmentsLoading.set(false); this.appointmentsFailed.set(true); },
      });
  }

  protected validDraft(): boolean {
    const kind = this.drafting();
    if (!kind || this.note.invalid || this.sending()) return false;
    if (kind === 'CALLBACK') return true;
    if (this.appointmentsLoading() || this.appointmentsFailed()
      || !this.appointments().some(a => a.id === this.appointmentId.value)) return false;
    if (kind === 'CANCEL') return true;
    const date = this.alternativeDate.value;
    const time = this.alternativeTime.value;
    return /^\d{4}-\d{2}-\d{2}$/.test(date) && /^\d{2}:\d{2}$/.test(time)
      && `${date}T${time}` > this.centreNow();
  }

  private centreNow(): string {
    const parts = new Intl.DateTimeFormat('en-GB', {
      timeZone: this.config.timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
    }).formatToParts(new Date());
    const value = (type: string) => parts.find(part => part.type === type)?.value;
    return `${value('year')}-${value('month')}-${value('day')}T${value('hour')}:${value('minute')}`;
  }

  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    this.api.requests()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (items) => {
          this.items.set(items);
          this.loading.set(false);
        },
        // The refusal names itself. Showing "could not load" for a wrong
        // filter invites a retry that will be refused identically forever.
        error: (error: unknown) => {
          this.loading.set(false);
          this.failed.set(true);
          this.failureKey.set(loadErrorKey(error));
          this.traceId.set(traceIdFor(error));
        },
      });
  }

  protected startDraft(kind: RequestKind): void {
    if (this.sending()) return;
    if (this.drafting() === kind) { this.cancelDraft(); return; }
    this.drafting.set(kind);
    this.note.setValue('');
    this.alternativeDate.setValue('');
    this.alternativeTime.setValue('');
  }

  protected cancelDraft(): void {
    this.drafting.set(null);
    this.note.setValue('');
  }

  protected submit(): void {
    const kind = this.drafting();
    if (!kind || !this.validDraft()) {
      return;
    }
    this.sending.set(true);
    this.api.submitRequest({
      childId: this.childContext.requireId(),
      kind,
      appointmentId: kind === 'CALLBACK' ? null : this.appointmentId.value,
      note: [
        kind === 'RESCHEDULE' ? this.i18n.translate('requests.alternativeSummary', {
          date: this.alternativeDate.value, time: this.alternativeTime.value,
        }) : '',
        this.note.value.trim(),
      ].filter(Boolean).join('\n') || this.i18n.translate(`requests.kind.${kind}`),
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (created) => {
          this.sending.set(false);
          this.drafting.set(null);
          this.note.setValue('');
          this.items.update((current) => [created, ...current]);
          this.toast.show(this.i18n.translate('requests.sent'));
        },
        error: () => {
          this.sending.set(false);
          this.toast.error(this.i18n.translate('error.saveFailed'));
        },
      });
  }

  protected icon(request: ParentRequest): IconName {
    switch (request.status) {
      case 'ACCEPTED': return 'ic-check-circle';
      case 'DECLINED': return 'ic-x-circle';
      default: return 'ic-clock';
    }
  }

  protected tint(request: ParentRequest): string {
    switch (request.status) {
      case 'ACCEPTED': return 'hbh-t--green';
      case 'DECLINED': return 'hbh-t--red';
      default: return 'hbh-t--amber';
    }
  }
}
