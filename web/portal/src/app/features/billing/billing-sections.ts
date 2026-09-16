import { BillingOverview } from '../../core/models/portal.models';

/**
 * The three parts of the billing screen, each retried on its own (#15).
 *
 * The API already loaded them independently - one child's failing balance
 * no longer blanks the invoices. But every retry button on the screen called
 * the same full reload: a family whose invoices failed pressed "retry" under
 * the invoices and got the balance, the packages and every child's lists
 * again, with the whole screen swapped for a skeleton while it happened.
 */
export type BillingSection = 'balance' | 'packages' | 'invoices';


/**
 * The screen after one section was fetched again.
 *
 * Only that section's fields are taken from `fresh`; the other two are left
 * exactly as they were. `fresh` carries all fields because the model does,
 * and the two it did not fetch hold placeholders - taking them would wipe a
 * section that was fine a moment ago.
 */
export function mergeSection(
  current: BillingOverview,
  fresh: BillingOverview,
  section: BillingSection,
): BillingOverview {
  switch (section) {
    case 'balance':
      return {
        ...current,
        dueAmount: fresh.dueAmount,
        currency: fresh.currency || current.currency,
        balanceUnavailable: fresh.balanceUnavailable,
      };
    case 'packages':
      return { ...current, packages: fresh.packages, packagesUnavailable: fresh.packagesUnavailable };
    case 'invoices':
      return { ...current, invoices: fresh.invoices, invoicesUnavailable: fresh.invoicesUnavailable };
  }
}

/** A retry that failed outright - no children, no network - leaves the section marked unavailable. */
export function markUnavailable(current: BillingOverview, section: BillingSection): BillingOverview {
  switch (section) {
    case 'balance': return { ...current, dueAmount: null, balanceUnavailable: true };
    case 'packages': return { ...current, packagesUnavailable: true };
    case 'invoices': return { ...current, invoicesUnavailable: true };
  }
}
