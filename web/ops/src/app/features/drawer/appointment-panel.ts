import { ChangeDetectionStrategy, Component, computed, inject, input, output } from '@angular/core';
import { RouterLink } from '@angular/router';

import { FormatService } from '@hbh/shared/format/format.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon, IconName } from '@hbh/shared/icon/icon';
import { Row } from '../../core/api/ops-api';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { ActionDialogService } from '../../core/ops/action-dialog.service';
import { APPOINTMENTS_SPEC, APPOINTMENT_NEXT, readRef, readText } from '../../core/ops/day-spec';
import { DrawerChild, DrawerStep } from '../../core/ops/record-drawer';

/** A button the panel offers: a day-spec action, possibly with a value pre-selected. */
interface Offer {
  readonly key: string;
  readonly step: DrawerStep;
  readonly labelKey: string;
  readonly icon: IconName;
  readonly primary: boolean;
}

const ICON_OF_NEXT: Readonly<Record<string, IconName>> = {
  CONFIRMED: 'ic-check',
  CHECKED_IN: 'ic-user-check',
  COMPLETED: 'ic-check-circle',
  CANCELLED: 'ic-x-circle',
  NO_SHOW: 'ic-eye-off',
};

/**
 * One appointment, read in full. Display and the buttons the owning list
 * would draw for this row - each one the list's own `status` or `start`
 * action, opened by the host through ActionDialogService.
 *
 * THE NEXT STATES ARE THE SCHEMA'S (APPOINTMENT_NEXT, copied verbatim in
 * day-spec.ts). One button per legal move, each pre-selecting that move in
 * the list's status dialog: the select is still shown and the person still
 * confirms. Nothing here decides whether a move is allowed - the database
 * does, and refuses with ILLEGAL_TRANSITION whatever this panel offered.
 */
@Component({
  selector: 'hbh-appointment-panel',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Icon, TranslatePipe],
  templateUrl: './appointment-panel.html',
  styleUrl: './record-panel.css',
})
export class AppointmentPanel {
  readonly row = input.required<Row>();
  readonly child = input<DrawerChild | null>(null);
  /** The child's guardians, null while unread, empty when none. */
  readonly guardians = input<readonly Row[] | null>(null);
  readonly guardiansState = input<'idle' | 'loading' | 'ready' | 'failed'>('idle');
  readonly act = output<DrawerStep>();

  private readonly dialogs = inject(ActionDialogService);
  protected readonly auth = inject(OpsAuthService);
  protected readonly format = inject(FormatService);

  protected readonly id = computed(() => Number(this.row()['appointment_id']));
  protected readonly status = computed(() => readText(this.row(), 'status'));
  protected readonly statusKey = computed(() => `${APPOINTMENTS_SPEC.statusPrefix}${this.status()}`);
  protected readonly tone = computed(() => APPOINTMENTS_SPEC.tone(this.status()));
  protected readonly startsAt = computed(() => readText(this.row(), 'starts_at'));
  protected readonly endsAt = computed(() => readText(this.row(), 'ends_at'));
  /**
   * "9:15 ص – 10:00 ص", and it stays in that order: each time is wrapped
   * in directional isolates (the same repair as day-spec's clockRange),
   * because Latin digits beside an Arabic meridiem reorder as one run.
   */
  protected readonly clock = computed(() => {
    const from = this.startsAt();
    const to = this.endsAt();
    if (!from) {
      return '';
    }
    const one = (at: string): string => `⁨${this.format.time(at)}⁩`;
    return to ? `${one(from)} – ${one(to)}` : one(from);
  });
  protected readonly service = computed(() => readRef(this.row(), 'service', 'name_ar'));
  protected readonly therapist = computed(() => readRef(this.row(), 'therapist', 'full_name_ar'));
  protected readonly room = computed(() => readRef(this.row(), 'room', 'name_ar'));
  protected readonly deliveryKey = computed(() => {
    const mode = readText(this.row(), 'delivery_mode');
    return mode ? `delivery.${mode}` : '';
  });
  protected readonly cancelReason = computed(() => readText(this.row(), 'cancel_reason'));
  protected readonly sessionId = computed(() => {
    const value = Number(this.row()['session_id']);
    return Number.isFinite(value) && value > 0 ? value : null;
  });
  protected readonly sessionStatusKey = computed(() => {
    const status = readText(this.row(), 'session_status');
    return status ? `status.session.${status}` : '';
  });

  protected readonly primaryGuardian = computed(() => {
    const rows = this.guardians() ?? [];
    return rows.find((row) => row['is_primary'] === true) ?? rows[0] ?? null;
  });
  protected readonly canOpenGuardian = computed(() => this.auth.can('GUARDIAN.MANAGE'));

  /** The buttons, in the order the day usually goes: start, then the moves. */
  protected readonly offers = computed<readonly Offer[]>(() => {
    const row = this.row();
    const out: Offer[] = [];
    if (this.dialogs.canOffer('appointments', 'start', row)) {
      out.push({
        key: 'start', step: { actionType: 'start', entityType: 'appointments' },
        labelKey: 'sessions.start', icon: 'ic-play', primary: true,
      });
    }
    if (this.dialogs.canOffer('appointments', 'status', row)) {
      for (const next of APPOINTMENT_NEXT[this.status()] ?? []) {
        const forward = next !== 'CANCELLED' && next !== 'NO_SHOW';
        out.push({
          key: next,
          step: { actionType: 'status', entityType: 'appointments', prefill: { status: next } },
          labelKey: `drawer.appointment.to.${next}`,
          icon: ICON_OF_NEXT[next] ?? 'ic-check-circle',
          primary: forward && !out.some((offer) => offer.primary),
        });
      }
    }
    return out;
  });

  protected text(row: Row, key: string): string {
    return readText(row, key);
  }
}
