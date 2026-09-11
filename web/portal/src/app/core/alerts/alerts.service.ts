import { Injectable, computed, signal } from '@angular/core';

/**
 * How many things are waiting for the guardian. The welcome screen is the one
 * place that learns this from the server, and it publishes the count here so
 * the shell's bell can show a dot without a second request.
 *
 * The dot is never invented: no count, no dot.
 */
@Injectable({ providedIn: 'root' })
export class AlertsService {
  private readonly count = signal(0);

  readonly pendingCount = this.count.asReadonly();
  readonly hasPending = computed(() => this.count() > 0);

  set(count: number): void {
    this.count.set(Math.max(0, count));
  }
}
