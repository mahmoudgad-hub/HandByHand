import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import {
  AppointmentStatus,
  InvoiceStatus,
  RequestStatus,
} from '../../core/models/portal.models';

type AnyStatus = AppointmentStatus | InvoiceStatus | RequestStatus;

/**
 * One badge for every state machine the portal displays. The label comes from
 * the bundle keyed by the server's own value, so a state the portal has not
 * been taught shows its raw code rather than a wrong friendly word.
 *
 * Coral is absent on purpose: it is a brand colour here, never a failure one.
 */
@Component({
  selector: 'hbh-status-badge',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [TranslatePipe],
  template: `
    <span class="hbh-badge" [class]="tone()">
      @if (status() === 'IN_PROGRESS') {
        <span class="hbh-live-dot"></span>
      }
      {{ 'status.' + status() | t }}
    </span>
  `,
  styles: [':host { display: contents; }'],
})
export class StatusBadge {
  readonly status = input.required<AnyStatus>();

  protected readonly tone = computed(() => {
    switch (this.status()) {
      case 'CONFIRMED':
      case 'IN_PROGRESS':
      case 'PAID':
      case 'ACCEPTED':
        return 'hbh-badge--success';
      case 'BOOKED':
      case 'CHECKED_IN':
        return 'hbh-badge--info';
      case 'DUE':
      case 'PARTIAL':
      case 'SUBMITTED':
      case 'UNDER_REVIEW':
        return 'hbh-badge--progress';
      case 'CANCELLED':
      case 'NO_SHOW':
      case 'DECLINED':
        return 'hbh-badge--danger';
      default:
        return 'hbh-badge--muted';
    }
  });
}
