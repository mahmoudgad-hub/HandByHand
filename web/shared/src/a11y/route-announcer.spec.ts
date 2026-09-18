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

/**
 * The tab inside the screen (HBH-039).
 *
 * A screen whose tabs live in the address bar is many places wearing one
 * name: the child's file announced the same three words for all thirteen of
 * its tabs, so a screen reader user moving between them heard nothing change
 * and the browser tab said the same thing every time.
 *
 * MEASURED FROM document.title AFTER NAVIGATING, which is the card's own
 * criterion and not an accident of wording: the title is what a bookmark, a
 * task switcher and a reopened window show, and reading it is the only way
 * to know it moved.
 */
describe('RouteAnnouncer and a screen with tabs', () => {
  const WORDS_WITH_TABS: Record<string, string> = {
    'app.name': 'هاند باي هاند',
    'file.title': 'ملفّ المستفيد',
    'file.tab.family': 'الأسرة',
    'file.tab.invoices': 'الفواتير',
    'subject.title': 'الأخصائيون',
    'nav.therapists': 'الأخصائيون',
    'therapistServices.title': 'الخدمات التي يقدّمونها',
  };

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        { provide: I18nService, useValue: { translate: (key: string) => WORDS_WITH_TABS[key] ?? key } },
        provideRouter([
          {
            path: '', component: Root,
            children: [
              {
                path: 'file', component: Blank,
                data: {
                  titleKey: 'file.title',
                  tabTitles: { family: 'file.tab.family', invoices: 'file.tab.invoices' },
                },
              },
              // A screen whose tabs carry keys of their own rather than one
              // prefix - the resource screen's shape (HBH-102). The announcer
              // reads ONE map for both; how a route builds it is the route's
              // business.
              {
                path: 'subject', component: Blank,
                data: {
                  titleKey: 'subject.title',
                  tabTitles: { therapists: 'nav.therapists', services: 'therapistServices.title' },
                },
              },
              // The same screen WITHOUT the map: a route that does not say
              // its tabs are in the address bar must not have them guessed.
              { path: 'plain', component: Blank, data: { titleKey: 'file.title' } },
            ],
          },
        ]),
      ],
    });
  });

  const titleAt = async (url: string): Promise<string> => {
    const harness = await RouterTestingHarness.create();
    await harness.navigateByUrl(url);
    harness.detectChanges();
    return document.title;
  };

  it('names the open tab', async () => {
    expect(await titleAt('/file?tab=family')).toBe('ملفّ المستفيد · الأسرة — هاند باي هاند');
  });

  it('and moves with it: a second tab is a second title', async () => {
    // One harness per test is the framework's rule, so the change of tab is
    // its own case rather than a second navigation here.
    expect(await titleAt('/file?tab=invoices')).toBe('ملفّ المستفيد · الفواتير — هاند باي هاند');
  });

  it('names the screen alone when no tab is open', async () => {
    expect(await titleAt('/file')).toBe('ملفّ المستفيد — هاند باي هاند');
  });

  it('does not print a key for a tab the bundle has never heard of', async () => {
    // An old link, a typed URL, a tab removed in a later build. The screen's
    // own name is the honest answer; "file.tab.nonsense" in a task switcher
    // is worse than the vague one.
    expect(await titleAt('/file?tab=nonsense')).toBe('ملفّ المستفيد — هاند باي هاند');
  });

  it('leaves a screen that never declared tabs exactly as it was', async () => {
    expect(await titleAt('/plain?tab=family')).toBe('ملفّ المستفيد — هاند باي هاند');
  });

  /**
   * HBH-102: the second half of the card, and the reason the mechanism
   * changed shape rather than gaining a twin.
   *
   * The resource screen's tabs are a list of resources followed by a list of
   * components, and each already owns a title key that other screens use -
   * there is no prefix to add. Reading one map covers both this screen and
   * the three detail screens, so nothing here is a special case.
   */
  it('names a tab whose key is its own, not a prefix plus its name', async () => {
    expect(await titleAt('/subject?tab=services'))
      .toBe('الأخصائيون · الخدمات التي يقدّمونها — هاند باي هاند');
  });
});
