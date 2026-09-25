import { TablePages } from '@hbh/shared/ui/table-pages';
import { ChangeDetectionStrategy, Component, DestroyRef, computed, inject, input, output, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { RouterLink } from '@angular/router';

import { FormatService } from '@hbh/shared/format/format.service';
import { ModalDialog } from '@hbh/shared/a11y/modal-dialog';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { DayApi } from '../../core/ops/day-api';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon, IconName } from '@hbh/shared/icon/icon';
import { Row } from '../../core/api/ops-api';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { ActionDialogService } from '../../core/ops/action-dialog.service';
import { INVOICES_SPEC, readText } from '../../core/ops/day-spec';
import { DrawerChild, DrawerStep } from '../../core/ops/record-drawer';

interface Offer {
  readonly key: string;
  readonly step: DrawerStep;
  readonly labelKey: string;
  readonly icon: IconName;
  readonly primary: boolean;
}

/**
 * One invoice, from the single-invoice read: header figures, the lines,
 * the payments. The buttons are the billing list's own actions - add a
 * line and issue while it is a draft, record a payment once it is out -
 * each drawn only for an account that holds BILLING.MANAGE and only in
 * the state the list would draw it.
 *
 * OQ-13 IS KEPT AS IT IS. An account with BILLING.VIEW and not
 * BILLING.MANAGE (reception, today) sees the invoice in full and is
 * offered nothing: no payment button, no workaround, no note pretending
 * otherwise. The decision about who takes cash at the door is the
 * owner's, not this panel's.
 */
@Component({
  selector: 'hbh-invoice-panel',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [TablePages, RouterLink, Icon, TranslatePipe, ModalDialog],
  templateUrl: './invoice-panel.html',
  styleUrl: './record-panel.css',
})
export class InvoicePanel {
  readonly row = input.required<Row>();
  readonly child = input<DrawerChild | null>(null);
  readonly guardians = input<readonly Row[] | null>(null);
  readonly guardiansState = input<'idle' | 'loading' | 'ready' | 'failed'>('idle');
  readonly act = output<DrawerStep>();
  /** Fires after a line was removed here, so the host re-reads the invoice and tells the screen behind. */
  readonly changed = output<void>();

  private readonly dialogs = inject(ActionDialogService);
  private readonly day = inject(DayApi);
  private readonly toast = inject(ToastService);
  private readonly i18n = inject(I18nService);
  private readonly destroyRef = inject(DestroyRef);
  protected readonly auth = inject(OpsAuthService);
  protected readonly format = inject(FormatService);

  protected readonly id = computed(() => Number(this.row()['invoice_id']));
  protected readonly status = computed(() => readText(this.row(), 'status'));
  protected readonly statusKey = computed(() => `${INVOICES_SPEC.statusPrefix}${this.status()}`);
  protected readonly tone = computed(() => INVOICES_SPEC.tone(this.status()));
  protected readonly currency = computed(() => readText(this.row(), 'currency_code') || undefined);
  protected readonly total = computed(() => Number(readText(this.row(), 'total_amt')) || 0);
  protected readonly paid = computed(() => Number(readText(this.row(), 'paid_amt')) || 0);
  /**
   * What is still owed: total less paid, for display beside the two
   * figures it is made of. The service does not return it, and this is
   * arithmetic on two numbers it did return - not a rule.
   */
  protected readonly remaining = computed(() => Math.max(0, this.total() - this.paid()));
  protected readonly issueDate = computed(() => readText(this.row(), 'issue_date'));
  protected readonly dueDate = computed(() => readText(this.row(), 'due_date'));
  protected readonly taxAmt = computed(() => Number(readText(this.row(), 'tax_amt')) || 0);
  /** Due before today and not settled. Display only - the same test the task inbox draws "overdue" by. */
  protected readonly overdue = computed(() =>
    ['ISSUED', 'PARTIALLY_PAID'].includes(this.status())
    && this.dueDate() !== '' && this.dueDate() < this.format.today());

  protected readonly lines = computed<readonly Row[]>(() =>
    (Array.isArray(this.row()['lines']) ? this.row()['lines'] as Row[] : []));
  protected readonly payments = computed<readonly Row[]>(() =>
    (Array.isArray(this.row()['payments']) ? this.row()['payments'] as Row[] : []));

  protected readonly primaryGuardian = computed(() => {
    const rows = this.guardians() ?? [];
    return rows.find((row) => row['is_primary'] === true) ?? rows[0] ?? null;
  });
  protected readonly canOpenGuardian = computed(() => this.auth.can('GUARDIAN.MANAGE'));

  protected readonly offers = computed<readonly Offer[]>(() => {
    const row = this.row();
    const out: Offer[] = [];
    if (this.dialogs.canOffer('invoices', 'pay', row)) {
      out.push({ key: 'pay', step: { actionType: 'pay', entityType: 'invoices' }, labelKey: 'billing.addPayment', icon: 'ic-money', primary: true });
    }
    if (this.dialogs.canOffer('invoices', 'issue', row)) {
      out.push({ key: 'issue', step: { actionType: 'issue', entityType: 'invoices' }, labelKey: 'billing.issue', icon: 'ic-receipt', primary: true });
    }
    if (this.dialogs.canOffer('invoices', 'addLine', row)) {
      out.push({ key: 'addLine', step: { actionType: 'addLine', entityType: 'invoices' }, labelKey: 'billing.addLine', icon: 'ic-plus', primary: false });
    }
    return out;
  });

  // ---- removing a line: the one verb the billing list never drew ----
  //
  // DayApi.removeInvoiceLine has existed as long as the invoice has; no
  // screen offered it (docs/UX-DETAIL-PAGES.md §5). It is drawn here for
  // BILLING.MANAGE on a DRAFT only - the same two conditions "add a line"
  // carries - and the service still decides: an issued invoice refuses it.

  protected readonly canRemoveLines = computed(
    () => this.status() === 'DRAFT' && this.auth.can('BILLING.MANAGE'));
  /** The line whose removal is being confirmed, or null. */
  protected readonly removing = signal<Row | null>(null);
  protected readonly removeBusy = signal(false);
  protected readonly removeError = signal('');

  protected askRemove(line: Row): void {
    this.removeError.set('');
    this.removing.set(line);
  }

  protected cancelRemove(): void {
    if (!this.removeBusy()) {
      this.removing.set(null);
    }
  }

  protected confirmRemove(): void {
    const line = this.removing();
    if (!line || this.removeBusy()) {
      return;
    }
    this.removeBusy.set(true);
    this.removeError.set('');
    this.day.removeInvoiceLine(this.id(), Number(line['line_id']))
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.removeBusy.set(false);
          this.removing.set(null);
          this.toast.show(this.i18n.translate('drawer.lineRemoved'));
          this.changed.emit();
        },
        error: () => {
          this.removeBusy.set(false);
          this.removeError.set('drawer.removeLineFailed');
        },
      });
  }

  protected money(value: number): string {
    return this.format.money(value, this.currency());
  }

  protected text(row: Row, key: string): string {
    return readText(row, key);
  }

  protected num(row: Row, key: string): number {
    return Number(readText(row, key)) || 0;
  }
}
