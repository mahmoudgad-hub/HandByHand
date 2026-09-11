import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  OnDestroy,
  computed,
  inject,
  signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { RouterLink } from '@angular/router';

import { PortalApi } from '../../core/api/portal-api';
import { ChildContextService } from '../../core/auth/child-context.service';
import { FormatService } from '@hbh/shared/format/format.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { LiveSession, StreamTicket } from '../../core/models/portal.models';
import { Icon } from '@hbh/shared/icon/icon';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';

/** Why the stream is not playing, in the words the screen needs. */
type Refusal = 'none' | 'no-session' | 'consent' | 'denied' | 'expired' | 'error';

/**
 * Watching a session as it happens.
 *
 * Three rules govern this screen, and none of them is enforced here:
 *
 *   Live only, never recorded. There is no recording, no archive, and no clip
 *   to seek into - which is why this component has no timeline, no scrubber
 *   and no download. A "moment" is a timestamped note for the therapist.
 *
 *   The ticket is the control. Requesting one is what checks the guardian's
 *   link to the child, the live-view consent, and the session being in
 *   progress. This screen renders whatever answer comes back, including the
 *   refusals - it never decides for itself that a stream may play.
 *
 *   Nothing about the camera reaches the client. No address, no credential,
 *   no room network detail. The portal holds an opaque token and a playback
 *   URL the edge issued, and nothing more.
 *
 * Every successful view is written to the centre's audit log by the server,
 * because a read is not something a trigger can catch.
 */
@Component({
  selector: 'hbh-live',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Icon, TranslatePipe, Skeleton, ErrorNote],
  templateUrl: './live.html',
})
export class Live implements OnDestroy {
  private readonly api = inject(PortalApi);
  private readonly childContext = inject(ChildContextService);
  private readonly destroyRef = inject(DestroyRef);
  private readonly toast = inject(ToastService);
  private readonly i18n = inject(I18nService);
  protected readonly format = inject(FormatService);

  private ticker: ReturnType<typeof setInterval> | null = null;

  protected readonly session = signal<LiveSession | null>(null);
  protected readonly ticket = signal<StreamTicket | null>(null);
  protected readonly loading = signal(true);
  protected readonly refusal = signal<Refusal>('none');
  protected readonly muted = signal(true);
  /** Ticks once a second so the elapsed clock and the expiry both advance. */
  protected readonly now = signal(Date.now());

  protected readonly elapsed = computed(() => {
    const current = this.session();
    return current ? this.format.elapsed(current.startedAt, new Date(this.now())) : '';
  });

  /** Seconds of viewing left on the current ticket, floored at zero. */
  protected readonly ticketSecondsLeft = computed(() => {
    const current = this.ticket();
    if (!current) {
      return 0;
    }
    return Math.max(0, Math.floor(
      (new Date(current.expiresAt).getTime() - this.now()) / 1000));
  });

  protected readonly playing = computed(
    () => this.ticket() !== null && this.ticketSecondsLeft() > 0);

  constructor() {
    this.ticker = setInterval(() => {
      this.now.set(Date.now());
      // An expired ticket stops the stream on this device too, rather than
      // leaving a dead player on screen while the edge has already cut it.
      if (this.ticket() && this.ticketSecondsLeft() === 0) {
        this.ticket.set(null);
        this.refusal.set('expired');
      }
    }, 1000);
    this.load();
  }

  ngOnDestroy(): void {
    if (this.ticker) {
      clearInterval(this.ticker);
    }
    // Leaving the screen drops the ticket. It stays valid on the server until
    // it expires - only the server can end it early - but this device stops
    // holding one it is no longer using.
    this.ticket.set(null);
  }

  protected load(): void {
    this.loading.set(true);
    this.refusal.set('none');
    this.api.liveSession(this.childContext.requireId())
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (session) => {
          this.session.set(session);
          this.loading.set(false);
          if (!session) {
            this.refusal.set('no-session');
            return;
          }
          this.requestTicket(session);
        },
        error: () => {
          this.loading.set(false);
          this.refusal.set('error');
        },
      });
  }

  protected requestTicket(session = this.session()): void {
    if (!session) {
      return;
    }
    this.refusal.set('none');
    this.api.requestStreamTicket(session.sessionId)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (ticket) => this.ticket.set(ticket),
        error: (error: unknown) => this.refusal.set(this.readRefusal(error)),
      });
  }

  protected toggleMute(): void {
    this.muted.update((value) => !value);
  }

  /**
   * Fills the screen with the player.
   *
   * Wrapped because the Fullscreen API is refused rather than absent in
   * plenty of real cases - an iPhone in Safari, a permissions policy on an
   * embedded page - and a rejected promise there must not surface to a parent
   * as a broken screen. Failing to go fullscreen leaves the session playing,
   * which is the thing they came for.
   */
  protected toggleFullscreen(element: HTMLElement): void {
    try {
      if (document.fullscreenElement) {
        void document.exitFullscreen().catch(() => undefined);
        return;
      }
      void element.requestFullscreen?.().catch(() => undefined);
    } catch {
      // Not supported here. The stream is unaffected.
    }
  }

  /**
   * A moment the parent wants the therapist to look at. It is a note with a
   * time on it - there is no recording for it to point into.
   */
  protected markMoment(): void {
    const session = this.session();
    if (!session) {
      return;
    }
    this.api.markMoment(session.sessionId, this.i18n.translate('live.momentNote'))
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => this.toast.show(this.i18n.translate('live.momentSaved')),
        error: () => this.toast.error(this.i18n.translate('error.saveFailed')),
      });
  }

  /** The message key for whatever the screen is currently refusing to play. */
  protected refusalKey(): string {
    switch (this.refusal()) {
      case 'no-session': return 'live.noSession';
      case 'consent': return 'live.consentRequired';
      case 'denied': return 'live.denied';
      case 'expired': return 'live.ticketExpired';
      case 'error': return 'error.load';
      default: return '';
    }
  }

  /**
   * Reads only the shape of the refusal, never a message from the server.
   * A server's own words about why it said no can describe its internals, and
   * those are not for a parent's screen.
   */
  private readRefusal(error: unknown): Refusal {
    const shaped = error as { status?: number; error?: { code?: string } };
    if (shaped?.status === 403) {
      return shaped.error?.code === 'CONSENT_REQUIRED' ? 'consent' : 'denied';
    }
    if (shaped?.status === 404 || shaped?.status === 409) {
      return 'no-session';
    }
    return 'error';
  }
}
