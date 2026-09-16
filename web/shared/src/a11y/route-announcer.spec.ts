import { Component } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { RouterOutlet, provideRouter } from '@angular/router';
import { RouterTestingHarness } from '@angular/router/testing';

import { I18nService } from '../i18n/i18n.service';
import { RouteAnnouncer } from './route-announcer';

/**
 * The screen's name, from route data, into the live region and the tab
 * (HBH-047). Tested here once - portal and ops both mount this component,
 * and a copy of the test in each would be two answers to one question.
 *
 * The rule under test is the walk: the DEEPEST activated route names the
 * screen. The console nests every screen under a shell route, so reading
 * the first route that has data - or the root - announces the shell (or
 * nothing) on every navigation, and a screen reader user never hears where
 * they went. Nothing throws when that happens.
 */
@Component({ template: '' })
class Blank {}

@Component({ imports: [RouteAnnouncer, RouterOutlet], template: '<hbh-route-announcer /><router-outlet />' })
class Root {}

/** The shell stand-in: an outlet with a title of its own, and no announcer. */
@Component({ imports: [RouterOutlet], template: '<router-outlet />' })
class Shell {}

const WORDS: Record<string, string> = {
  'app.name': 'هاند باي هاند',
  'shell.title': 'الإطار',
  'screen.title': 'ملفّ الطفل',
};

describe('RouteAnnouncer', () => {
  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        // The real service needs a bundle over HTTP; the walk does not.
        { provide: I18nService, useValue: { translate: (key: string) => WORDS[key] ?? key } },
        provideRouter([
          {
            path: '', component: Root,
            children: [
              {
                path: 'shell', component: Shell, data: { titleKey: 'shell.title' },
                children: [
                  { path: 'screen', component: Blank, data: { titleKey: 'screen.title' } },
                  { path: 'untitled', component: Blank },
                ],
              },
            ],
          },
        ]),
      ],
    });
  });

  async function arrive(url: string): Promise<{ tab: string; heard: string }> {
    const harness = await RouterTestingHarness.create();
    await harness.navigateByUrl(url);
    harness.detectChanges();
    const region = harness.routeNativeElement?.ownerDocument
      .querySelector('hbh-route-announcer [role="status"]');
    return { tab: document.title, heard: (region?.textContent ?? '').trim() };
  }

  it('names the deepest screen, not the shell around it', async () => {
    const { tab, heard } = await arrive('/shell/screen');
    expect(tab).toBe('ملفّ الطفل — هاند باي هاند');
    expect(heard).toBe('ملفّ الطفل');
  });

  it('falls back to the app name when the screen has no title', async () => {
    // Not the shell's title: that would announce a place the user is not.
    const { tab } = await arrive('/shell/untitled');
    expect(tab).toBe('هاند باي هاند');
  });
});
