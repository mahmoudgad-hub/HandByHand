import { BillingOverview } from '../../core/models/portal.models';
import { markUnavailable, mergeSection } from './billing-sections';

/**
 * Per-section retry on the billing screen (#15). The failure worth a test
 * is the silent one: a retry of one section quietly replacing another that
 * was showing correct figures.
 */
const invoice = {
  id: 'i-1', number: 'INV-1', issuedAt: '2026-09-01T09:00:00Z', amount: 600,
  paidAmount: 0, currency: 'EGP', status: 'ISSUED', description: 'تخاطب',
} as unknown as BillingOverview['invoices'][number];
const pkg = {
  id: 'p-1', title: 'باقة', used: 2, total: 8, expiresAt: '2026-12-01T00:00:00Z',
} as unknown as BillingOverview['packages'][number];

const onScreen: BillingOverview = {
  dueAmount: 600, currency: 'EGP', packages: [pkg], invoices: [],
  balanceUnavailable: false, packagesUnavailable: false, invoicesUnavailable: true,
};

/** What a fetch of ONE section returns: the other two are placeholders. */
const fetchedInvoicesOnly: BillingOverview = {
  dueAmount: 0, currency: '', packages: [], invoices: [invoice],
  balanceUnavailable: false, packagesUnavailable: false, invoicesUnavailable: false,
};

describe('mergeSection', () => {
  it('takes the retried section', () => {
    const merged = mergeSection(onScreen, fetchedInvoicesOnly, 'invoices');
    expect(merged.invoices).toEqual([invoice]);
    expect(merged.invoicesUnavailable).toBeFalse();
  });

  it('leaves the sections it did not fetch exactly as they were', () => {
    // The placeholders say "0 owed, no packages". Taking them would tell a
    // family they owe nothing because their invoices were retried.
    const merged = mergeSection(onScreen, fetchedInvoicesOnly, 'invoices');
    expect(merged.dueAmount).toBe(600);
    expect(merged.currency).toBe('EGP');
    expect(merged.packages).toEqual([pkg]);
  });

  it('withholds the total again when the retried balance still failed', () => {
    const failedAgain = { ...fetchedInvoicesOnly, dueAmount: null, balanceUnavailable: true };
    const merged = mergeSection(onScreen, failedAgain, 'balance');
    expect(merged.dueAmount).toBeNull();
    expect(merged.balanceUnavailable).toBeTrue();
    expect(merged.packages).toEqual([pkg]);
  });

  it('keeps the known currency when a balance arrives without one', () => {
    const merged = mergeSection(onScreen, { ...fetchedInvoicesOnly, dueAmount: 450 }, 'balance');
    expect(merged.dueAmount).toBe(450);
    expect(merged.currency).toBe('EGP');
  });
});

describe('markUnavailable', () => {
  it('marks only the section whose retry failed', () => {
    const merged = markUnavailable({ ...onScreen, invoicesUnavailable: false }, 'packages');
    expect(merged.packagesUnavailable).toBeTrue();
    expect(merged.packages).toEqual([pkg]);
    expect(merged.invoicesUnavailable).toBeFalse();
    expect(merged.dueAmount).toBe(600);
  });

  it('withholds the total when the balance retry failed', () => {
    expect(markUnavailable(onScreen, 'balance').dueAmount).toBeNull();
  });
});
