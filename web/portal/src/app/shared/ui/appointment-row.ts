import { ChangeDetectionStrategy, Component, inject, input } from '@angular/core';

import { Router } from '@angular/router';

import { FormatService } from '@hbh/shared/format/format.service';
import { AppointmentSummary } from '../../core/models/portal.models';
import { StatusBadge } from './status-badge';

/**
 * One appointment as the design's list row. Applied to a button or a div by
 * the caller, so the same markup serves a row that navigates and a row that
 * only informs.
 *
 * The date box and the clock time are two different digit shapes on purpose:
 * the centre writes dates in Arabic-Indic and clock times in Latin.
 */
@Component({
  selector: '[hbhAppointmentRow]',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [StatusBadge],
  host: { class: 'row' },
  template: `
    <span class="row__date">
      <b>{{ format.dayNumber(appointment().startsAt) }}</b>
      <small>{{ format.monthName(appointment().startsAt) }}</small>
    </span>
    <span class="row__b">
      <span class="row__t">{{ appointment().serviceName }}</span>
      <span class="row__s">
        <!-- The therapist's name opens their profile. The row itself may
             already be inside a button or a link, so this is a plain span
             with a click rather than an anchor: an anchor nested in a button
             is invalid, and browsers resolve it by dropping one of them. -->
        @if (appointment().therapistId) {
          <span class="hbh-link" role="link" tabindex="0"
                (click)="openTherapist($event)"
                (keydown.enter)="openTherapist($event)">
            {{ appointment().therapistName }}
          </span>
        } @else {
          {{ appointment().therapistName }}
        }
        <s>&middot;</s> {{ appointment().roomName }}
      </span>
    </span>
    <span class="row__e">
      <hbh-status-badge [status]="appointment().status" />
      <span class="row__time" dir="ltr">{{ format.time(appointment().startsAt) }}</span>
    </span>
  `,
})
export class AppointmentRow {
  readonly appointment = input.required<AppointmentSummary>();
  protected readonly format = inject(FormatService);
  private readonly router = inject(Router);

  /**
   * Opens the therapist's profile.
   *
   * The event is stopped first, because this row is usually itself
   * clickable - a whole appointment that opens the diary. Without that, one
   * tap on the name would fire both and the profile would be replaced by
   * whatever the row does, which reads as the link not working.
   */
  protected openTherapist(event: Event): void {
    event.stopPropagation();
    event.preventDefault();
    const id = this.appointment().therapistId;
    if (id) {
      void this.router.navigate(['/therapists', id]);
    }
  }
}
