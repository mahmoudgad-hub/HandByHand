import { Route } from '@angular/router';

import ar from '../assets/i18n/ar.json';
import { routes } from './app.routes';
import { permissionGuard } from './core/auth/ops-auth.guard';
import { NavEntry, OPS_NAV } from './layout/shell/nav';

/**
 * The route table and the menu, checked as data (HBH-047).
 *
 * Every defect this file looks for is SILENT. Nothing throws, no request
 * fails, and the screen still renders:
 *
 *   - a titleKey with no entry in the bundle puts the key itself in the
 *     browser tab and the screen-reader announcement, because translate()
 *     answers a missing key with the key;
 *   - a navKey naming the wrong menu entry lights up the wrong item, sets
 *     aria-current on the wrong page and puts the wrong word in the shell's
 *     top bar. This file found exactly that on /therapist-services;
 *   - a screen under permissionGuard with no `permission` in its data is
 *     let through for everyone - the guard reads "nothing needed";
 *   - a menu entry whose permission differs from its route's draws a link
 *     that bounces to /denied, or hides one that would have opened.
 *
 * None of this is the control - the server refuses what a role may not
 * read. It decides whether the console tells the truth about it.
 *
 * The checks are functions run TWICE: over the real table, which must
 * produce nothing, and over a small broken one, which must produce each
 * defect. A check that has only ever been seen passing has not been seen
 * reading anything.
 */

type Bundle = Readonly<Record<string, string>>;

interface Found {
  readonly path: string;
  readonly route: Route;
  /** True for the shell's children - the screens behind sign-in. */
  readonly inShell: boolean;
}

/**
 * Screens behind sign-in that deliberately carry NO permission guard, each
 * with its reason. An exemption living only in a loop condition would be a
 * rule every new route could quietly join.
 */
const UNGUARDED: Readonly<Record<string, string>> = {
  // app.routes.ts: the consent a therapist records about their own profile
  // needs no permission, so the one person who can record it can reach it.
  'therapists/:therapistId/profile': 'own profile; the database decides whose row it is',
  // Where the guard itself sends a refusal. Guarding it would loop.
  denied: 'the destination of every refusal',
  // "حسابي": the caller's own avatar, password and profile summary. Its
  // author confirmed 2026-09-16 that it is for every signed-in account.
  profile: 'own account; the shell already requires sign-in and the API only writes the caller\'s own account',
};

function walk(list: readonly Route[], prefix = '', inShell = false): Found[] {
  return list.flatMap((route) => {
    const path = [prefix, route.path ?? ''].filter(Boolean).join('/');
    const isShell = !!route.children && route.path === '';
    return [{ path, route, inShell }, ...walk(route.children ?? [], path, inShell || isShell)];
  });
}

/** Routes that draw a screen - not redirects, not the shell. */
function screens(table: readonly Route[]): Found[] {
  return walk(table).filter(({ route }) =>
    !route.redirectTo && !route.children && !!(route.component || route.loadComponent));
}

function dataOf(route: Route): Record<string, unknown> {
  return (route.data ?? {}) as Record<string, unknown>;
}

function routeProblems(table: readonly Route[], nav: readonly NavEntry[], bundle: Bundle): string[] {
  const out: string[] = [];
  const navKeys = new Set(nav.map((entry) => entry.key));

  for (const { path, route, inShell } of screens(table)) {
    const d = dataOf(route);

    const title = d['titleKey'];
    if (typeof title !== 'string') {
      out.push(`${path}: no titleKey`);
    } else if (bundle[title] === undefined) {
      out.push(`${path}: titleKey "${title}" is not in the bundle`);
    }
    if (d['subKey'] !== undefined && bundle[d['subKey'] as string] === undefined) {
      out.push(`${path}: subKey "${d['subKey']}" is not in the bundle`);
    }

    // DayScreen falls back to spec.titleKey; ResourceScreen shows one per tab.
    const specs = [d['spec'], ...((d['specs'] as unknown[] | undefined) ?? [])]
      .filter(Boolean) as { titleKey?: string }[];
    for (const spec of specs) {
      if (spec.titleKey && bundle[spec.titleKey] === undefined) {
        out.push(`${path}: spec title "${spec.titleKey}" is not in the bundle`);
      }
    }

    // The tab titles the announcer reads (HBH-039, HBH-102). Same silence as
    // titleKey and for the same reason - translate() answers a missing key
    // with the key, so a gap here puts "child.tab.goals" in the browser tab
    // and in a screen reader's ear. And a tab the map has never heard of is
    // not a defect: the announcer falls back to the screen's own name, which
    // is what an old link or a removed tab should get.
    const tabTitles = d['tabTitles'];
    if (tabTitles !== undefined) {
      if (typeof tabTitles !== 'object' || tabTitles === null) {
        out.push(`${path}: tabTitles is not a map`);
      } else {
        for (const [tab, key] of Object.entries(tabTitles as Record<string, unknown>)) {
          if (typeof key !== 'string' || bundle[key] === undefined) {
            out.push(`${path}: tab "${tab}" names "${String(key)}", which is not in the bundle`);
          }
        }
      }
    }
    // A screen with more than one tab and no map announces one name for all
    // of them - the defect HBH-039 was opened for.
    const tabCount = ((d['specs'] as unknown[] | undefined) ?? []).length
      + ((d['extraTabs'] as unknown[] | undefined) ?? []).length;
    if (tabCount > 1 && tabTitles === undefined) {
      out.push(`${path}: ${tabCount} tabs and no tabTitles - every tab would say the screen's name`);
    }

    if (d['navKey'] !== undefined && !navKeys.has(d['navKey'] as string)) {
      out.push(`${path}: navKey "${d['navKey']}" names no menu entry`);
    }

    if (inShell && !(path in UNGUARDED)) {
      if (!(route.canActivate ?? []).includes(permissionGuard)) {
        out.push(`${path}: no permissionGuard`);
      }
      const needed = d['permission'];
      if (!(typeof needed === 'string' && needed.length > 0)) {
        out.push(`${path}: names no permission - the guard lets everyone in`);
      }
    }
  }
  return out;
}

function menuProblems(table: readonly Route[], nav: readonly NavEntry[], bundle: Bundle): string[] {
  const out: string[] = [];
  const all = screens(table);
  for (const entry of nav) {
    if (bundle[entry.labelKey] === undefined) {
      out.push(`${entry.key}: label "${entry.labelKey}" is not in the bundle`);
    }
    const target = all.find((s) => `/${s.path}` === entry.path);
    if (!target) {
      out.push(`${entry.key}: no screen at ${entry.path}`);
      continue;
    }
    const d = dataOf(target.route);
    if (d['permission'] !== entry.permission) {
      out.push(`${entry.key}: menu needs ${entry.permission}, its screen needs ${String(d['permission'])}`);
    }
    if (d['navKey'] !== entry.key) {
      out.push(`${entry.key}: its screen lights up "${String(d['navKey'])}" instead`);
    }
  }
  return out;
}

describe('the route table and the menu', () => {
  const bundle = ar as Bundle;

  it('has something to read, so "no problems" means something', () => {
    expect(screens(routes).length).toBeGreaterThan(20);
    expect(OPS_NAV.length).toBeGreaterThan(10);
  });

  it('has no route problems', () => {
    expect(routeProblems(routes, OPS_NAV, bundle)).toEqual([]);
  });

  it('has no menu problems', () => {
    expect(menuProblems(routes, OPS_NAV, bundle)).toEqual([]);
  });

  it('keeps every exemption pointed at a route that still exists', () => {
    // A deleted route would leave a line here that excuses nothing.
    const paths = new Set(screens(routes).map((s) => s.path));
    for (const path of Object.keys(UNGUARDED)) {
      expect(paths.has(path)).withContext(`exemption for missing route ${path}`).toBeTrue();
    }
  });
});

describe('the checks themselves', () => {
  const load = () => Promise.resolve(class {});
  const bundle: Bundle = { 'good.title': 'عنوان', 'nav.a': 'أ', 'nav.b': 'ب', 'spec.ok': 'مواصفة' };
  const nav: NavEntry[] = [
    { key: 'a', path: '/a', icon: 'ic-bell', labelKey: 'nav.a', permission: 'A.VIEW' },
    { key: 'b', path: '/b', icon: 'ic-bell', labelKey: 'nav.missing', permission: 'B.VIEW' },
  ];
  const shell = (children: Route[]): Route[] => [{ path: '', loadComponent: load, children }];

  it('stay quiet on a table with nothing wrong', () => {
    const table = shell([
      { path: 'a', canActivate: [permissionGuard], loadComponent: load,
        data: { navKey: 'a', titleKey: 'good.title', permission: 'A.VIEW', spec: { titleKey: 'spec.ok' } } },
    ]);
    expect(routeProblems(table, nav, bundle)).toEqual([]);
  });

  it('see each silent route defect', () => {
    const table = shell([
      { path: 'untitled', canActivate: [permissionGuard], loadComponent: load, data: { permission: 'X' } },
      { path: 'raw-key', canActivate: [permissionGuard], loadComponent: load,
        data: { titleKey: 'nav.catalog.typo', permission: 'X' } },
      { path: 'bad-spec', canActivate: [permissionGuard], loadComponent: load,
        data: { titleKey: 'good.title', permission: 'X', specs: [{ titleKey: 'spec.gone' }] } },
      { path: 'wrong-nav', canActivate: [permissionGuard], loadComponent: load,
        data: { titleKey: 'good.title', permission: 'X', navKey: 'nowhere' } },
      { path: 'open-door', canActivate: [permissionGuard], loadComponent: load,
        data: { titleKey: 'good.title' } },
      { path: 'no-guard', loadComponent: load, data: { titleKey: 'good.title', permission: 'X' } },
      // HBH-102: a tab named with a key nobody translated, and a screen with
      // tabs that declared none - the two halves of "every tab says the
      // screen's name".
      { path: 'raw-tab', canActivate: [permissionGuard], loadComponent: load,
        data: { titleKey: 'good.title', permission: 'X', specs: [{ titleKey: 'spec.ok' }],
                tabTitles: { family: 'tab.gone' } } },
      { path: 'unnamed-tabs', canActivate: [permissionGuard], loadComponent: load,
        data: { titleKey: 'good.title', permission: 'X',
                specs: [{ titleKey: 'spec.ok' }, { titleKey: 'spec.ok' }] } },
    ]);
    const found = routeProblems(table, nav, bundle).join('\n');
    expect(found).toContain('untitled: no titleKey');
    expect(found).toContain('raw-key: titleKey "nav.catalog.typo"');
    expect(found).toContain('bad-spec: spec title "spec.gone"');
    expect(found).toContain('wrong-nav: navKey "nowhere"');
    expect(found).toContain('open-door: names no permission');
    expect(found).toContain('no-guard: no permissionGuard');
    expect(found).toContain('raw-tab: tab "family" names "tab.gone"');
    expect(found).toContain('unnamed-tabs: 2 tabs and no tabTitles');
  });

  it('see each silent menu defect', () => {
    const table = shell([
      // Right path, wrong permission, and it lights up another entry - the
      // /therapist-services shape.
      { path: 'a', canActivate: [permissionGuard], loadComponent: load,
        data: { navKey: 'b', titleKey: 'good.title', permission: 'OTHER' } },
    ]);
    const found = menuProblems(table, nav, bundle).join('\n');
    expect(found).toContain('a: menu needs A.VIEW, its screen needs OTHER');
    expect(found).toContain('a: its screen lights up "b" instead');
    expect(found).toContain('b: label "nav.missing"');
    expect(found).toContain('b: no screen at /b');
  });
});
