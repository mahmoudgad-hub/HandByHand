import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed, fakeAsync, tick } from '@angular/core/testing';
import { ActivatedRoute, convertToParamMap, provideRouter } from '@angular/router';
import { Observable, of, throwError } from 'rxjs';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { PortalApi } from '../../core/api/portal-api';
import { MeetingPass } from '../../core/models/portal.models';
import { Consultation } from './consultation';

/**
 * What is worth testing on this screen is the part that would fail QUIETLY.
 *
 * A broken layout is visible the first time somebody looks. These are not:
 * a refusal mapped to the wrong sentence reads as a working screen telling a
 * family the wrong thing, a credential that outlives the screen leaves no
 * trace anywhere, and a script host that is not checked looks identical to
 * one that is until the day it matters.
 */

/** The provider's client, faked, so no test reaches the network. */
class FakeJitsi {
  static built: { domain: string; options: Record<string, unknown> } | null = null;
  static disposed = 0;
  private readonly handlers = new Map<string, (payload?: unknown) => void>();

  constructor(domain: string, options: Record<string, unknown>) {
    FakeJitsi.built = { domain, options };
  }

  addListener(event: string, handler: (payload?: unknown) => void): void {
    this.handlers.set(event, handler);
  }

  dispose(): void {
    FakeJitsi.disposed += 1;
  }

  static reset(): void {
    FakeJitsi.built = null;
    FakeJitsi.disposed = 0;
  }
}

/** Reaching the parts the template uses, which are protected on the class. */
interface Probe {
  refusalKey(): string;
  joined(): boolean;
  pass(): MeetingPass | null;
  enter(): void;
}

const aPass = (domain: string): MeetingPass => ({
  provider: 'JITSI_PUBLIC',
  domain,
  room: 'hbh-0123456789abcdef0123456789abcdef',
  token: '',
  displayName: 'ولي أمر يوسف',
  moderator: false,
  expiresAt: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
});

/** Counts how many times the door was asked, which is what must stay at one. */
let doorCalls = 0;

function build(answer: Observable<MeetingPass>) {
  doorCalls = 0;
  TestBed.configureTestingModule({
    providers: [
      provideRouter([]),
      // I18nService is what the template's translate pipe injects, and it
      // asks for HttpClient the moment it is constructed. The TESTING
      // backend, not the real one: nothing in this file should be able to
      // reach the network, and a misconfiguration that let it would show up
      // as a slow green test rather than a failing one.
      provideHttpClient(),
      provideHttpClientTesting(),
      { provide: HBH_CONFIG, useValue: DEFAULT_HBH_CONFIG },
      {
        provide: PortalApi,
        useValue: {
          enterConsultation: () => {
            doorCalls += 1;
            return answer;
          },
        } as unknown as PortalApi,
      },
      {
        provide: ActivatedRoute,
        useValue: { snapshot: { paramMap: convertToParamMap({ appointmentId: '7' }) } },
      },
    ],
  });
  const fixture = TestBed.createComponent(Consultation);
  // The view has to exist before the client can be attached to it: the stage
  // is looked up by reference, and without this it is simply not there when
  // the script resolves - which would make every test below pass for the
  // wrong reason, by never joining at all.
  fixture.detectChanges();
  const probe = fixture.componentInstance as unknown as Probe;
  return { fixture, probe };
}

function refused(status: number, code: string) {
  return throwError(() => ({ status, error: { error: { code } } }));
}

describe('Consultation refusals', () => {
  afterEach(() => {
    TestBed.resetTestingModule();
  });

  /**
   * THE TEST THIS FILE EXISTS FOR.
   *
   * Three of these arrive as 409 and they are three different things for a
   * family to do: pay the invoice, come back at the hour, or go to the right
   * screen. A mapping that read the status instead of the code would collapse
   * them into one sentence and still look perfectly healthy - which is how
   * "the door is not open" ends up hiding an unpaid invoice.
   */
  const cases: readonly [number, string, string][] = [
    [409, 'NOT_CONFIRMED', 'consult.notConfirmed'],
    [409, 'DOOR_CLOSED', 'consult.doorClosed'],
    [409, 'NOT_IN_PERSON', 'consult.notOnline'],
    [404, 'NOT_FOUND', 'consult.notFound'],
    [503, 'STREAM_UNAVAILABLE', 'consult.unavailable'],
  ];

  for (const [status, code, key] of cases) {
    it(`says ${key} for ${code}`, fakeAsync(() => {
      const { probe } = build(refused(status, code));
      tick();
      expect(probe.refusalKey()).toBe(key);
    }));
  }

  it('keeps every refusal distinct from every other', () => {
    const keys = cases.map(([, , key]) => key);
    expect(new Set(keys).size).toBe(keys.length);
  });

  /**
   * A code this build has not been taught must not borrow the sentence of one
   * it has. "Something went wrong" is the honest answer; anything specific
   * would be this screen inventing a reason.
   */
  it('falls back to the generic failure for a code it does not know', fakeAsync(() => {
    const { probe } = build(refused(409, 'SOME_FUTURE_CODE'));
    tick();
    expect(probe.refusalKey()).toBe('error.load');
  }));

  /**
   * Asking the door is a WRITE: each call mints a credential and writes a row
   * against this family. The template hides the button while a request is
   * out, but that is the weaker half - it needs change detection to have run,
   * and an impatient double tap on a phone beats it.
   */
  it('asks the door once however many times the button is pressed', fakeAsync(() => {
    // Never answers, so the request is still in flight for the presses below.
    const { probe } = build(new Observable<MeetingPass>(() => undefined));
    expect(doorCalls).toBe(1);

    probe.enter();
    probe.enter();
    probe.enter();

    expect(doorCalls).toBe(1);
  }));

  /**
   * And the other half of that guard, which is the one that would have
   * shipped broken: `loading` used to start true, so a method that refuses
   * to run while loading would have refused its OWN first request - and the
   * screen would sit blank with nothing in any log.
   */
  it('still makes its first request at all', fakeAsync(() => {
    build(refused(404, 'NOT_FOUND'));
    tick();
    expect(doorCalls).toBe(1);
  }));
});

describe('Consultation client', () => {
  const windowRef = window as unknown as Record<string, unknown>;
  let saved: unknown;

  beforeEach(() => {
    saved = windowRef['JitsiMeetExternalAPI'];
    windowRef['JitsiMeetExternalAPI'] = FakeJitsi;
    FakeJitsi.reset();
  });

  afterEach(() => {
    windowRef['JitsiMeetExternalAPI'] = saved;
    TestBed.resetTestingModule();
  });

  /**
   * THE SECURITY TEST. This screen injects a <script> at a host that arrived
   * in a response body. An allowlist is what stands between that and
   * arbitrary code in a signed-in parent's session if the response is ever
   * attacker-shaped, and an allowlist nobody tests is a comment.
   */
  it('refuses a provider host this build does not know, and loads nothing', fakeAsync(() => {
    const before = document.head.querySelectorAll('script').length;
    const { probe } = build(of(aPass('evil.example.com')));
    tick();

    expect(probe.refusalKey()).toBe('consult.unavailable');
    expect(probe.joined()).toBeFalse();
    expect(FakeJitsi.built).toBeNull();
    expect(document.head.querySelectorAll('script').length).toBe(before);
  }));

  /**
   * And the other half of it: the allowlist must still let the real provider
   * through. A refusal test alone stays green on a list that refuses
   * everything - CLAUDE.md's rule about the photo-consent gate, which was a
   * gate with no key and whose refusal test passed for as long as it existed.
   */
  it('admits a provider host it does know', fakeAsync(() => {
    const { probe } = build(of(aPass('meet.jit.si')));
    tick();

    expect(probe.joined()).toBeTrue();
    expect(FakeJitsi.built?.domain).toBe('meet.jit.si');
  }));

  /** The empty token of a provider with none must not travel as "". */
  it('sends no jwt at all when the provider has no token', fakeAsync(() => {
    build(of(aPass('meet.jit.si')));
    tick();

    expect(FakeJitsi.built?.options['jwt']).toBeUndefined();
  }));

  /**
   * Recording is refused permanently by CLAUDE.md. The token is the control -
   * these flags only stop the buttons being drawn - but a build that quietly
   * stopped passing them would put the button one press away from a clinical
   * recording, and the press would be refused with no explanation.
   */
  it('asks the client not to offer recording, streaming or transcription', fakeAsync(() => {
    build(of(aPass('meet.jit.si')));
    tick();

    const config = FakeJitsi.built?.options['configOverwrite'] as Record<string, unknown>;
    expect(config['fileRecordingsEnabled']).toBeFalse();
    expect(config['liveStreamingEnabled']).toBeFalse();
    expect(config['transcribingEnabled']).toBeFalse();
  }));

  /**
   * The deep-linking banner is the "install our app first" wall, and getting
   * past it without an installed application is the reason the consultation
   * is embedded in this portal at all.
   */
  it('turns off the banner that asks a parent to install an application', fakeAsync(() => {
    build(of(aPass('meet.jit.si')));
    tick();

    const config = FakeJitsi.built?.options['configOverwrite'] as Record<string, unknown>;
    expect(config['disableDeepLinking']).toBeTrue();
  }));

  /**
   * THE CREDENTIAL DIES WITH THE SCREEN. Nothing else in this application
   * holds a live provider credential in JavaScript, so nothing else would
   * notice if this stopped happening.
   */
  it('disposes the client and drops the pass when the screen is left', fakeAsync(() => {
    const { fixture, probe } = build(of(aPass('meet.jit.si')));
    tick();
    expect(probe.pass()).not.toBeNull();

    fixture.destroy();

    expect(FakeJitsi.disposed).toBe(1);
    expect(probe.pass()).toBeNull();
  }));
});
