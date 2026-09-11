import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';

import { Icon } from '../icon/icon';

/**
 * A failure the parent can act on. It carries the message the caller decided
 * to show - never a status code, a stack, or anything the server said about
 * its own internals.
 */
@Component({
  selector: 'hbh-error-note',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon],
  template: `
    <div class="err" role="alert">
      <hbh-icon name="ic-warn" />
      <span>{{ message() }}</span>
    </div>
    @if (traceId()) {
      <!-- The service's id for the request that failed. Shown only where
           nobody can act on the failure, because the REASON deliberately
           never leaves the server - this is the single thread between "it
           did not work for me" and the line in the centre's log that says
           why. It names the request and nothing about the person. -->
      <p class="err__trace" dir="ltr">{{ traceId() }}</p>
    }
    @if (retryLabel()) {
      <button class="hbh-btn hbh-btn--ghost hbh-btn--block" type="button"
              style="margin-top:10px" (click)="retry.emit()">
        <hbh-icon name="ic-refresh" />
        {{ retryLabel() }}
      </button>
    }
  `,
})
export class ErrorNote {
  readonly message = input.required<string>();
  /** The service's request id, on a failure nobody can act on. */
  readonly traceId = input<string | null>(null);
  readonly retryLabel = input<string>('');
  readonly retry = output<void>();
}
