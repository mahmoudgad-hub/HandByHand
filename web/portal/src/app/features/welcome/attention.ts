import { IconName } from '@hbh/shared/icon/icon';
import { AttentionItem } from '../../core/models/portal.models';

/**
 * What a pending item looks like and where it leads.
 *
 * Shared by the front page, which lists the family's pending items for
 * every child, and by anything else that draws one. Pure functions: the
 * money and the plural go through the app's formatter and bundle in the
 * component, where those live.
 */
export function attentionIcon(item: AttentionItem): IconName {
  switch (item.kind) {
    case 'INVOICE': return 'ic-receipt';
    case 'ACTIVITY': return 'ic-puzzle';
    case 'REPORT': return 'ic-file';
    case 'REQUEST': return 'ic-send';
  }
}

/** The tint each kind carries in the design. */
export function attentionTint(item: AttentionItem): string {
  switch (item.kind) {
    case 'INVOICE': return 'hbh-t--amber';
    case 'ACTIVITY': return 'hbh-t--red';
    case 'REPORT': return 'hbh-t--blue';
    case 'REQUEST': return 'hbh-t--purple';
  }
}

export interface AttentionTarget {
  readonly path: string;
  readonly query?: Readonly<Record<string, string>>;
  /** True when the screen is about one child, so that child must be chosen first. */
  readonly needsChild: boolean;
}

/**
 * Where a pending item leads. Billing and requests span the family and
 * need no child chosen; a report or an activity is one child's, and the
 * caller selects that child before navigating.
 */
export function attentionTarget(item: AttentionItem): AttentionTarget {
  switch (item.kind) {
    case 'INVOICE': return { path: '/billing', needsChild: false };
    case 'REQUEST': return { path: '/requests', needsChild: false };
    case 'REPORT': return { path: '/progress', query: { tab: 'reports' }, needsChild: true };
    case 'ACTIVITY': return { path: '/activities', needsChild: true };
  }
}
