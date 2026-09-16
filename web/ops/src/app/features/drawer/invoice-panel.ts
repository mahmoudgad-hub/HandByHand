import { TablePages } from '@hbh/shared/ui/table-pages';
import { ChangeDetectionStrategy, Component, computed, inject, input, output } from '@angular/core';
import { RouterLink } from '@angular/router';

import { FormatService } from '@hbh/shared/format/format.service';
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
  imports: [TablePages, RouterLink, Icon, TranslatePipe],
  templateUrl: './invoice-panel.html',
  styleUrl: './record-panel.css',
})
export class InvoicePanel {
  readonly row = input.required<Row>();
  readonly child = input<DrawerChild | null>(null);
  readonly guardians = input<readonly Row[] | null>(null);
  readonly guardiansState = input<'idle' | 'loading' | 'ready' | 'failed'>('idle');
  readonly act = output<DrawerStep>();

  private readonly dialogs = inject(ActionDialogService);
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
