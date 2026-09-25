import { TablePages } from '@hbh/shared/ui/table-pages';
import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';

import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { OpsApi, Row } from '../../core/api/ops-api';
import { refusalSentence } from '../../core/api/ops-error';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { DayApi } from '../../core/ops/day-api';

/**
 * Which services each therapist actually practises.
 *
 * WITHOUT A ROW HERE NO APPOINTMENT CAN BE BOOKED AT ALL. validate_slot
 * refuses with THERAPIST_SERVICE_MISMATCH, and that is how the gap was found:
 * a centre could create therapists, services, rooms and children through this
 * console and still not book a single appointment, because nothing anywhere
 * could write this table. The endpoint exists now; this is the screen.
 *
 * EASY TO CONFUSE WITH CASELOAD, and they are different questions:
 *   caseload  - therapist to CHILD:   may this person run this child's session
 *   this      - therapist to SERVICE: does this person practise speech therapy
 * Booking checks both, and neither substitutes for the other.
 *
 * It is a grid of checkboxes rather than a list of rows because that is the
 * shape of the question - every therapist against every service - and because
 * a "which of these have I forgotten" is answered by looking at an empty
 * column, not by paging a list.
 */
@Component({
  selector: 'hbh-therapist-services',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [TablePages, Icon, TranslatePipe, Skeleton, EmptyState, ErrorNote],
  templateUrl: './therapist-services.html',
})
export class TherapistServices {
  private readonly crud = inject(OpsApi);
  private readonly day = inject(DayApi);
  private readonly destroyRef = inject(DestroyRef);
  private readonly toast = inject(ToastService);
  private readonly i18n = inject(I18nService);
  private readonly auth = inject(OpsAuthService);

  protected readonly therapists = signal<readonly Row[]>([]);
  protected readonly services = signal<readonly Row[]>([]);
  /** therapist id -> the service ids they practise. */
  protected readonly links = signal<Record<number, ReadonlySet<number>>>({});

  protected readonly loading = signal(true);
  protected readonly failed = signal(false);
  /** "<therapistId>:<serviceId>" while that one cell is being written. */
  protected readonly busy = signal<string>('');

  protected readonly canWrite = computed(() => this.auth.can('STAFF.MANAGE'));

  constructor() {
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    this.crud.list('therapists', { limit: 200 })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (page) => {
          this.therapists.set(page.rows);
          this.loadServices(page.rows);
        },
        error: () => {
          this.loading.set(false);
          this.failed.set(true);
        },
      });
  }

  private loadServices(therapists: readonly Row[]): void {
    this.crud.list('services', { limit: 200 })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (page) => {
          this.services.set(page.rows);
          if (therapists.length === 0) {
            this.loading.set(false);
            return;
          }
          this.loadLinks(therapists);
        },
        error: () => {
          this.loading.set(false);
          this.failed.set(true);
        },
      });
  }

  /**
   * One request per therapist, because the service answers per therapist.
   *
   * A row that fails is left EMPTY rather than assumed unlinked - an empty
   * checkbox says "not linked", and saying that about a link nobody could
   * read would invite somebody to tick it and get a duplicate.
   */
  private loadLinks(therapists: readonly Row[]): void {
    let outstanding = therapists.length;
    for (const therapist of therapists) {
      const id = Number(therapist['therapist_id']);
      this.day.therapistServices(id)
        .pipe(takeUntilDestroyed(this.destroyRef))
        .subscribe({
          next: (rows) => {
            const ids = new Set(rows.map((row) => Number(row['service_id'])));
            this.links.update((current) => ({ ...current, [id]: ids }));
            if (--outstanding === 0) {
              this.loading.set(false);
            }
          },
          error: () => {
            if (--outstanding === 0) {
              this.loading.set(false);
            }
            this.failed.set(true);
          },
        });
    }
  }

  protected therapistId(row: Row): number {
    return Number(row['therapist_id']);
  }

  protected serviceId(row: Row): number {
    return Number(row['service_id']);
  }

  protected nameOf(row: Row): string {
    return String(row['full_name_ar'] ?? row['name_ar'] ?? '');
  }

  protected isLinked(therapist: number, service: number): boolean {
    return this.links()[therapist]?.has(service) ?? false;
  }

  protected isBusy(therapist: number, service: number): boolean {
    return this.busy() === `${therapist}:${service}`;
  }

  /**
   * Links or unlinks one pair.
   *
   * The screen updates only after the service confirms. An optimistic tick
   * here would show a therapist as able to take a booking that the very next
   * slot check would refuse - and the person would be looking at a tick while
   * being told the therapist does not do that service.
   */
  protected toggle(therapist: number, service: number): void {
    if (!this.canWrite() || this.busy()) {
      return;
    }
    const linked = this.isLinked(therapist, service);
    this.busy.set(`${therapist}:${service}`);

    const call = linked
      ? this.day.unlinkTherapistService(therapist, service)
      : this.day.linkTherapistService(therapist, service);

    call.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: () => {
        this.busy.set('');
        this.links.update((current) => {
          const ids = new Set(current[therapist] ?? []);
          if (linked) {
            ids.delete(service);
          } else {
            ids.add(service);
          }
          return { ...current, [therapist]: ids };
        });
        this.toast.show(this.i18n.translate(
          linked ? 'therapistServices.unlinked' : 'therapistServices.linked'));
      },
      error: (error: unknown) => {
        this.busy.set('');
        this.toast.error(refusalSentence(this.i18n, error));
      },
    });
  }
}
