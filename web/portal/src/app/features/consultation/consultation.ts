import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  ElementRef,
  OnDestroy,
  computed,
  inject,
  signal,
  viewChild,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import { PortalApi } from '../../core/api/portal-api';
import { readRefusal, traceIdFor } from '../../core/api/portal-error';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { MeetingPass } from '../../core/models/portal.models';
import { Icon } from '@hbh/shared/icon/icon';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';

/** Why there is no call on screen, in the words the screen needs. */
type Refusal =
  | 'none'
  /** The appointment is in the centre. There is no video call to join. */
  | 'not-online'
  /** Booked, not paid. The family can do something about this one. */
  | 'not-confirmed'
  /** Too early, too late, or cancelled. Nothing to fix but the clock. */
  | 'door-closed'
  /** Not this family's appointment, or no such appointment. */
  | 'not-found'
  /** The centre has no working video provider configured. */
  | 'unavailable'
  /** The pass ran out while the call was open. */
  | 'expired'
  /** The call ended - either side hung up. */
  | 'ended'
  | 'error';

/**
 * The provider's own client, as much of it as this file uses.
 *
 * Declared rather than installed. @jitsi/react-sdk and lib-jitsi-meet are
 * both large dependencies whose only job here would be to type four calls,
 * and this application has no build-time dependency on the provider at all -
 * the script is fetched at runtime from the host the SERVER named. A package
 * would pin a version of a client that the provider upgrades on their own
 * schedule, which is the opposite of what an embedded conference wants.
 */
interface JitsiApi {
  addListener(event: string, handler: (payload?: unknown) => void): void;
  dispose(): void;
}

type JitsiConstructor = new (domain: string, options: Record<string, unknown>) => JitsiApi;

/**
 * THE HOSTS THIS BUILD IS ALLOWED TO LOAD A CONFERENCE CLIENT FROM.
 *
 * The pass names its own domain so that a change of provider is a change of
 * configuration rather than a release - and this list does not take that
 * back, because a new provider needs a Content-Security-Policy entry anyway,
 * and that is already a deploy. So the allowlist costs nothing that was not
 * required, and it buys the thing CSP alone cannot: the page and the policy
 * agree, and they fail in the same direction.
 *
 * What it actually defends against: this file injects a <script> at a host
 * that arrived in a response body. If the response were ever attacker-shaped
 * - a compromised service, a proxy in the middle, a bug in a handler - that
 * is arbitrary code inside a signed-in parent's session. An allowlist makes
 * that a refusal instead. CLAUDE.md paid for this rule once already, on the
 * static server that served any file under its root.
 */
const ALLOWED_PROVIDER_HOSTS: readonly string[] = ['8x8.vc', 'meet.jit.si'];

/**
 * The online consultation, inside this application.
 *
 * FOUR RULES GOVERN THIS SCREEN, AND THREE OF THEM ARE NOT ENFORCED HERE.
 *
 *   The door is the server's. Whether this family may enter - the
 *   appointment being theirs, it being a consultation at all, the invoice
 *   being paid, the hour having come, the room still being open - is decided
 *   by hbh.authorize_meeting_entry and by nothing in this file. This screen
 *   asks once and renders the answer, including every refusal. There is no
 *   condition here that could disagree with the database, because there is
 *   no condition here at all.
 *
 *   The pass is short and there is no renewal. When it expires the call
 *   drops, and the way back in is to ask the door again - which asks all of
 *   its questions again. That is the point of it being short.
 *
 *   Never recorded. The options passed to the client below switch recording,
 *   livestreaming and transcription off, AND THAT IS NOT THE CONTROL: the
 *   client is code in this browser and anything in it can be changed by
 *   whoever holds the browser. The control is inside the signed token, which
 *   the provider enforces and nobody here can rewrite - see the meeting
 *   package in the API. The options are here so the buttons are not drawn;
 *   the token is here so the buttons would not work.
 *
 *   The credential dies with the screen. It is held in one signal, never
 *   written to storage, never put in a URL of ours, never logged. Leaving
 *   this screen disposes the client and drops the pass.
 *
 * WHY THE TOKEN IS IN THIS PAGE AT ALL, which is a real departure from the
 * live-stream screen beside it: that one is one-way video the service can
 * stand in front of, so its credential lives in an HttpOnly cookie the
 * script cannot read. A conference is two-way, and real-time media cannot be
 * proxied - the browser negotiates with the provider directly and therefore
 * authenticates to it directly. Migration 0120 records the decision and the
 * owner who made it.
 */
@Component({
  selector: 'hbh-consultation',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Icon, TranslatePipe, Skeleton, ErrorNote],
  templateUrl: './consultation.html',
})
export class Consultation implements OnDestroy {
  private readonly api = inject(PortalApi);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);

  private readonly host = viewChild<ElementRef<HTMLElement>>('stage');

  private api$: JitsiApi | null = null;
  private ticker: ReturnType<typeof setInterval> | null = null;

  protected readonly pass = signal<MeetingPass | null>(null);
  /**
   * FALSE at construction, and enter() - called from the constructor below -
   * sets it true before anything can render. It has to start false because
   * enter() now refuses to run while it is true, and a screen that began
   * "already loading" would refuse its own first request and sit blank
   * forever.
   */
  protected readonly loading = signal(false);
  /** True once the provider's client is actually in the page. */
  protected readonly joined = signal(false);
  protected readonly refusal = signal<Refusal>('none');
  protected readonly traceId = signal<string | null>(null);
  /** Ticks once a second so the remaining time is a clock and not a guess. */
  protected readonly now = signal(Date.now());

  /** Seconds left on this pass, floored at zero. */
  protected readonly secondsLeft = computed(() => {
    const current = this.pass();
    if (!current) {
      return 0;
    }
    return Math.max(0, Math.floor(
      (new Date(current.expiresAt).getTime() - this.now()) / 1000));
  });

  /**
   * The remaining time, as mm:ss.
   *
   * Latin digits and `dir="ltr"` on the element that shows it: the centre
   * writes clock times in Latin digits, and a bidirectional run of
   * "٠٢:١٤" inside Arabic text renders its parts in an order nobody means.
   */
  protected readonly timeLeft = computed(() => {
    const total = this.secondsLeft();
    const minutes = Math.floor(total / 60);
    const seconds = total % 60;
    return `${minutes}:${String(seconds).padStart(2, '0')}`;
  });

  /** Under two minutes left. The warning appears before the call drops. */
  protected readonly endingSoon = computed(
    () => this.joined() && this.secondsLeft() > 0 && this.secondsLeft() <= 120);

  constructor() {
    this.ticker = setInterval(() => {
      this.now.set(Date.now());
      if (this.pass() && this.secondsLeft() === 0) {
        // The provider will drop the call on its own. Saying so here rather
        // than waiting for that means the parent reads a sentence instead of
        // watching a video freeze.
        this.leaveCall();
        this.refusal.set('expired');
      }
    }, 1000);
    this.enter();
  }

  ngOnDestroy(): void {
    if (this.ticker) {
      clearInterval(this.ticker);
    }
    this.leaveCall();
  }

  /**
   * Asks the door.
   *
   * Called once on arrival and again only when a person presses a button. It
   * is a WRITE - every call mints a credential and records that it did - so
   * nothing here may call it on a timer or a retry loop.
   */
  protected enter(): void {
    // ONE AT A TIME. The template already hides the button while a request
    // is out, and that is not enough: it is the weaker half of the rule, it
    // depends on change detection having run, and a double tap on a phone
    // beats it. Every extra press here is another credential minted and
    // another row written against this family - so the guard belongs in the
    // method that does the minting, not only in the markup that offers it.
    if (this.loading()) {
      return;
    }

    const appointmentId = this.route.snapshot.paramMap.get('appointmentId');
    if (!appointmentId) {
      // Cannot happen through the router, which is exactly why it is stated:
      // a missing parameter must not become a request to /consultation/null.
      this.loading.set(false);
      this.refusal.set('not-found');
      return;
    }

    this.loading.set(true);
    this.refusal.set('none');
    this.traceId.set(null);

    this.api.enterConsultation(appointmentId)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (pass) => {
          this.loading.set(false);
          this.pass.set(pass);
          this.join(pass);
        },
        error: (error: unknown) => {
          this.loading.set(false);
          this.refusal.set(this.readWhy(error));
          this.traceId.set(traceIdFor(error));
        },
      });
  }

  /** Back to the diary, which is where somebody who cannot join should go. */
  protected leave(): void {
    void this.router.navigate(['/schedule']);
  }

  /**
   * Puts the provider's client in the page.
   *
   * The script is fetched from the host the SERVER named, checked against
   * ALLOWED_PROVIDER_HOSTS first. Loaded once per document: a second visit to
   * this screen finds the constructor already on `window` and reuses it, so
   * leaving and coming back does not stack script tags.
   */
  private join(pass: MeetingPass): void {
    if (!ALLOWED_PROVIDER_HOSTS.includes(pass.domain)) {
      // Not "error". The centre's configuration names a provider this build
      // has not been reviewed for, and there is nothing a parent can do -
      // which is the same thing "unavailable" says about a missing key.
      this.pass.set(null);
      this.refusal.set('unavailable');
      return;
    }

    this.loadClient(pass.domain).then((Ctor) => {
      const stage = this.host()?.nativeElement;
      if (!stage || this.pass() === null) {
        // The screen was left while the script was in flight.
        return;
      }
      // Set BEFORE the client is constructed, so the container is visible
      // by the time the iframe is attached to it. A conference built into a
      // `display:none` subtree is one the browser may never lay out.
      this.joined.set(true);
      try {
        this.api$ = this.build(Ctor, pass, stage);
      } catch {
        this.joined.set(false);
        this.pass.set(null);
        this.refusal.set('unavailable');
        return;
      }

      // Both mean the same thing to this screen: the call is over. The
      // second fires when the provider itself decides to close - a kicked
      // participant, a room that ended - and without it the page would sit
      // showing a dead iframe.
      this.api$.addListener('videoConferenceLeft', () => this.ended());
      this.api$.addListener('readyToClose', () => this.ended());
    }).catch(() => {
      this.pass.set(null);
      this.refusal.set('unavailable');
    });
  }

  /** The client's options, kept apart from the wiring so both stay readable. */
  private build(Ctor: JitsiConstructor, pass: MeetingPass, stage: HTMLElement): JitsiApi {
    return new Ctor(pass.domain, {
      roomName: pass.room,
      // Absent rather than empty for a provider with no tokens: the client
      // treats an empty string as a malformed one and refuses.
      jwt: pass.token === '' ? undefined : pass.token,
      parentNode: stage,
      userInfo: { displayName: pass.displayName },
      configOverwrite: {
        // NOT THE CONTROL. See the class comment: the token is what the
        // provider enforces, and these three only stop the buttons being
        // drawn for something that would be refused anyway.
        fileRecordingsEnabled: false,
        liveStreamingEnabled: false,
        transcribingEnabled: false,

        // The whole reason this is embedded. Deep linking is the banner
        // that asks a parent on a phone to install an application before
        // they can talk to their child's therapist, and avoiding exactly
        // that is why the consultation is inside the portal at all.
        disableDeepLinking: true,
        prejoinPageEnabled: false,
        disableThirdPartyRequests: true,
      },
      interfaceConfigOverwrite: {
        MOBILE_APP_PROMO: false,
        SHOW_JITSI_WATERMARK: false,
        SHOW_CHROME_EXTENSION_BANNER: false,
      },
    });
  }

  private ended(): void {
    this.leaveCall();
    this.refusal.set('ended');
  }

  /**
   * Drops the call and the credential together.
   *
   * dispose() is wrapped because it reaches into an iframe that may already
   * be gone - a navigation, a provider that closed it first - and a throw
   * here would leave `pass` set, which is the one thing this method exists
   * to prevent.
   */
  private leaveCall(): void {
    try {
      this.api$?.dispose();
    } catch {
      // Already gone. The pass is dropped below regardless.
    }
    this.api$ = null;
    this.joined.set(false);
    this.pass.set(null);
  }

  /**
   * Loads the provider's IFrame client, once per document.
   *
   * Rejects on a load error rather than hanging: a blocked script fires
   * `error` and never `load`, and a promise that settles neither way is a
   * spinner that spins forever.
   */
  private loadClient(domain: string): Promise<JitsiConstructor> {
    const existing = (window as unknown as Record<string, unknown>)['JitsiMeetExternalAPI'];
    if (typeof existing === 'function') {
      return Promise.resolve(existing as JitsiConstructor);
    }
    return new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = `https://${domain}/external_api.js`;
      script.async = true;
      script.onload = () => {
        const ctor = (window as unknown as Record<string, unknown>)['JitsiMeetExternalAPI'];
        if (typeof ctor === 'function') {
          resolve(ctor as JitsiConstructor);
        } else {
          // The file loaded and did not define what it should. Treated as a
          // failure to load, because to this screen it is the same thing.
          reject(new Error('the conference client did not load'));
        }
      };
      script.onerror = () => reject(new Error('the conference client could not be fetched'));
      document.head.appendChild(script);
    });
  }

  /** The message key for whatever is on screen instead of a call. */
  protected refusalKey(): string {
    switch (this.refusal()) {
      case 'not-online': return 'consult.notOnline';
      case 'not-confirmed': return 'consult.notConfirmed';
      case 'door-closed': return 'consult.doorClosed';
      case 'not-found': return 'consult.notFound';
      case 'unavailable': return 'consult.unavailable';
      case 'expired': return 'consult.expired';
      case 'ended': return 'consult.ended';
      case 'error': return 'error.load';
      default: return '';
    }
  }

  /**
   * Reads the SHAPE of the refusal, never a sentence from the server.
   *
   * By code and not by status: three of these are 409 and they are three
   * different things to do about them - pay, wait, or go to the right
   * screen. Falling back on the status alone would collapse them into one
   * message, which is how "the door is not open" ends up hiding an unpaid
   * invoice behind a sentence about time.
   */
  private readWhy(error: unknown): Refusal {
    const refusal = readRefusal(error);
    switch (refusal.code) {
      case 'NOT_IN_PERSON': return 'not-online';
      case 'NOT_CONFIRMED': return 'not-confirmed';
      case 'DOOR_CLOSED': return 'door-closed';
      case 'NOT_FOUND': return 'not-found';
      case 'STREAM_UNAVAILABLE': return 'unavailable';
      default: break;
    }
    // A code this build has not been taught. The status still separates
    // "not yours" from "we broke", which is the least a person needs.
    if (refusal.status === 404 || refusal.status === 403) {
      return 'not-found';
    }
    if (refusal.status === 503) {
      return 'unavailable';
    }
    return 'error';
  }
}
