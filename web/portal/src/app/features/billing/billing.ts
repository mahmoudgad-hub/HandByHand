import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  inject,
  signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Router } from '@angular/router';

import { PortalApi } from '../../core/api/portal-api';
import { loadErrorKey, traceIdFor } from '../../core/api/portal-error';
import { FormatService } from '@hbh/shared/format/format.service';
import { HbhMoneyPipe, HbhNumberPipe, HbhPluralPipe } from '@hbh/shared/format/format.pipes';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { BillingOverview, Invoice, ServicePackage } from '../../core/models/portal.models';
import { Icon } from '@hbh/shared/icon/icon';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { StatusBadge } from '../../shared/ui/status-badge';
import { BillingSection, markUnavailable, mergeSection } from './billing-sections';

/**
 * Packages and invoices, across all of the guardian's children - which is why
 * this screen needs no child chosen.
 *
 * It takes no payment. No card number, no account number, and no payment form
 * appears here. The inquiry button opens the existing family conversation;
 * it does not claim that a callback was requested before a message is sent.
 */
@Component({
  selector: 'hbh-billing',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    Icon, TranslatePipe, HbhMoneyPipe, HbhNumberPipe, HbhPluralPipe,
    StatusBadge, Skeleton, EmptyState, ErrorNote,
  ],
  templateUrl: './billing.html',
  styleUrl: './billing.css',
})
export class Billing {
  private readonly api = inject(PortalApi);
  private readonly destroyRef = inject(DestroyRef);
  private readonly router = inject(Router);
  protected readonly format = inject(FormatService);

  protected readonly data = signal<BillingOverview | null>(null);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);
  protected readonly failureKey = signal('error.load');
  /** Shown only where nobody can act on the failure. */
  protected readonly traceId = signal<string | null>(null);

  /** The one section being fetched again, if any - drawn as busy in place. */
  protected readonly retrying = signal<BillingSection | null>(null);

  constructor() {
    this.load();
  }

  /**
   * Fetch one section again and leave the others on screen (#15). The page
   * does not drop back to a skeleton: the figures that loaded are still
   * right, and hiding them to reload something else was the defect.
   */
  protected retry(section: BillingSection): void {
    const current = this.data();
    if (!current || this.retrying()) { return; }
    this.retrying.set(section);
    this.api.billing(new Set([section]))
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (fresh) => {
          this.data.update((now) => now ? mergeSection(now, fresh, section) : now);
          this.retrying.set(null);
        },
        error: () => {
          this.data.update((now) => now ? markUnavailable(now, section) : now);
          this.retrying.set(null);
        },
      });
  }

  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    this.api.billing()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (overview) => {
          this.data.set(overview);
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

  protected usedShare(servicePackage: ServicePackage): number {
    return servicePackage.total > 0
      ? Math.round((servicePackage.used / servicePackage.total) * 100) : 0;
  }

  protected remaining(servicePackage: ServicePackage): number {
    return Math.max(0, servicePackage.total - servicePackage.used);
  }

  /**
   * What is still owed on one invoice.
   *
   * Subtraction, and nothing more: both figures come from the service and
   * neither is summed across rows here. The centre's own balance stays the
   * total at the top of the screen - this file does not add invoices up and
   * present the result as the outstanding amount, because a page of a longer
   * list would give a figure that is right on a small account and quietly
   * wrong on a large one.
   *
   * Clamped at zero. An overpayment is a real thing and the centre's problem
   * to sort out, but "you owe −150" is not a sentence to put in front of a
   * family.
   */
  protected owed(invoice: Invoice): number {
    return Math.max(0, invoice.amount - invoice.paidAmount);
  }

  protected invoiceTint(invoice: Invoice): string {
    return invoice.status === 'PAID' ? 'hbh-t--green' : 'hbh-t--amber';
  }

  /** Open the family-wide conversation without requiring a selected child. */
  protected askAboutPayment(): void {
    void this.router.navigate(['/requests'], { queryParams: { tab: 'messages' } });
  }
}
