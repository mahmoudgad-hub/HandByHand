import {
  ChangeDetectionStrategy, Component, DestroyRef, OnDestroy, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute, Router } from '@angular/router';

import { FormatService } from '@hbh/shared/format/format.service';
import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { LiveApi } from '../../core/api/live-api';
import { readRefusal, refusalKey } from '../../core/api/ops-error';
import { DayApi } from '../../core/ops/day-api';

/**
 * Watching a session that is happening right now.
 *
 * TWO RULES THIS SCREEN EXISTS INSIDE, and neither is negotiable:
 *
 *   LIVE ONLY. NOTHING IS EVER RECORDED. There is no table for a clip, no
 *   switch to enable one, and no seek bar on this player - a scrubber implies
 *   a recording behind it. "Mark a moment" writes a CLINICAL NOTE stamped
 *   with the offset into the session; it does not point at a saved video,
 *   because there is no saved video to point at.
 *
 *   THE CREDENTIAL NEVER REACHES THIS CODE. The service answers with an
 *   HttpOnly cookie scoped to one path. This component knows a path and an
 *   expiry and nothing else, and it must stay that way: a token in JavaScript
 *   is a token in a log, a history entry and a screenshot.
 *
 * The grant lasts fifteen minutes at most, so the player renews it before it
 * lapses rather than letting the picture die mid-session.
 */
@Component({
  selector: 'hbh-live-view',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon, TranslatePipe, ErrorNote],
  templateUrl: './live-view.html',
})
export class LiveView implements OnDestroy {
  private readonly api = inject(LiveApi);
  private readonly day = inject(DayApi);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  private readonly toast = inject(ToastService);
  private readonly i18n = inject(I18nService);
  private readonly config = inject(HBH_CONFIG);
  protected readonly format = inject(FormatService);

  private readonly sessionId = Number(this.route.snapshot.paramMap.get('sessionId'));

  protected readonly src = signal('');
  protected readonly expiresAt = signal('');
  protected readonly opening = signal(true);
  protected readonly errorKey = signal('');

  /** The moment marks written this sitting, newest first. */
  protected readonly marks = signal<readonly { at: string; body: string }[]>([]);
  protected readonly markBody = signal('');
  protected readonly saving = signal(false);

  /** When the picture started, for the offset a mark is stamped with. */
  private watchingSince = 0;
  private renewTimer: ReturnType<typeof setTimeout> | null = null;

  protected readonly hasPicture = computed(() => this.src() !== '');

  constructor() {
    this.open();
  }

  ngOnDestroy(): void {
    if (this.renewTimer) {
      clearTimeout(this.renewTimer);
    }
    // Hand the credential back rather than letting it lapse. Fifteen minutes
    // is short, but a token nobody revoked still works after the person who
    // opened it has walked away from the desk.
    this.api.close().subscribe({ next: () => undefined, error: () => undefined });
  }

  protected open(): void {
    this.opening.set(true);
    this.errorKey.set('');
    this.api.open(this.sessionId)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (grant) => {
          this.opening.set(false);
          this.expiresAt.set(grant.expires_at);
          if (!this.watchingSince) {
            this.watchingSince = Date.now();
          }
          // A cache-buster so a renewal actually re-requests rather than
          // replaying whatever the browser kept from the expired grant.
          this.src.set(
            `${this.config.apiBaseUrl}${grant.playback_path}?t=${Date.now()}`);
          this.scheduleRenewal(grant.expires_in_seconds);
        },
        error: (error: unknown) => {
          this.opening.set(false);
          this.errorKey.set(this.messageFor(error));
        },
      });
  }

  /**
   * Renews a minute before the grant lapses.
   *
   * Not at the moment it expires: the request takes time, and a picture that
   * dies while a parent is watching their child is the failure this whole
   * screen exists to avoid. The floor keeps a very short cap from scheduling
   * a renewal in the past.
   */
  private scheduleRenewal(seconds: number): void {
    if (this.renewTimer) {
      clearTimeout(this.renewTimer);
    }
    const delay = Math.max(15, seconds - 60) * 1000;
    this.renewTimer = setTimeout(() => this.open(), delay);
  }

  protected setMark(value: string): void {
    this.markBody.set(value);
  }

  /**
   * Writes a clinical note stamped with the offset into this sitting.
   *
   * The offset is text inside the note, not a pointer: there is no recording
   * for it to point into. It is there so a therapist reading the note later
   * knows roughly when in the session it happened.
   */
  protected mark(event?: Event): void {
    event?.preventDefault();
    const body = this.markBody().trim();
    if (!body || this.saving()) {
      return;
    }
    const offset = this.format.elapsed(new Date(this.watchingSince || Date.now()));
    this.saving.set(true);
    this.day.writeNote(this.sessionId, `[${offset}] ${body}`)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.saving.set(false);
          this.marks.update((all) => [{ at: offset, body }, ...all]);
          this.markBody.set('');
          this.toast.show(this.i18n.translate('live.marked'));
        },
        error: (error: unknown) => {
          this.saving.set(false);
          this.toast.error(this.i18n.translate(this.messageFor(error)));
        },
      });
  }

  protected back(): void {
    void this.router.navigate(['/sessions']);
  }

  private messageFor(error: unknown): string {
    const status = (error as { status?: number })?.status;
    if (status === 0 || status === undefined) {
      return 'error.connection';
    }
    const code = (error as { error?: { error?: { code?: string } } })?.error?.error?.code;
    // NOT_LIVE and STREAM_UNAVAILABLE are the two this screen actually meets,
    // and they mean different things to the person standing there: one is
    // "the session ended", the other is "the camera is not answering".
    if (code === 'NOT_LIVE' || code === 'STREAM_UNAVAILABLE') {
      return `error.${code}`;
    }
    return refusalKey(readRefusal(error));
  }
}
