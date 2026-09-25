import { ExtraTab } from '../../features/resource/resource-screen';
import { ResourceSpec } from '../resource/resource-spec';

/**
 * Building the `tabTitles` a route hands the announcer (HBH-039, HBH-102).
 *
 * The announcer reads ONE shape - tab name to message key - because it is
 * the one place a title is decided and a second shape there would be a
 * second answer to one question. These are the two ways a route arrives at
 * that shape, and they are data construction, not two mechanisms: both
 * return the same map, and neither is read anywhere but in app.routes.ts.
 *
 * BOTH DERIVE FROM THE LIST THAT ALREADY DEFINES THE TABS. A route repeating
 * the names by hand would drift the first time a tab is added: the tab
 * appears, its title silently stays the screen's own name, and nothing is
 * red anywhere. That is the failure worth spending two functions to avoid.
 */

/** Tabs whose keys share one prefix - the three detail screens. */
export function tabsByPrefix(
  prefix: string, tabs: readonly string[],
): Readonly<Record<string, string>> {
  return Object.fromEntries(tabs.map((tab) => [tab, `${prefix}${tab}`]));
}

/**
 * The resource screen's tabs: resources first, then the components declared
 * beside them, exactly as ResourceScreen orders and names them.
 *
 * Each already carries a title key of its own, shared with the navigation
 * and with other screens, so there is nothing to prefix - and copying those
 * sentences into twins under a prefix is how two versions of one sentence
 * start disagreeing.
 */
export function tabsOfResources(
  specs: readonly ResourceSpec[], extraTabs: readonly ExtraTab[] = [],
): Readonly<Record<string, string>> {
  return Object.fromEntries([
    ...specs.map((spec) => [spec.resource, spec.titleKey]),
    ...extraTabs.map((tab) => [tab.key, tab.titleKey]),
  ]);
}

/**
 * A resource route's `data`, with its tab titles derived rather than typed.
 *
 * Every resource screen goes through this, including the ones that carry a
 * single resource today: the map costs nothing on a screen with no tab bar,
 * and the day a second resource is added beside the first the title follows
 * without anybody remembering. "Remember to also add it here" is the
 * instruction that gets forgotten.
 */
export function resourceScreen<T extends {
  readonly specs: readonly ResourceSpec[]; readonly extraTabs?: readonly ExtraTab[];
}>(data: T): T & { tabTitles: Readonly<Record<string, string>> } {
  return { ...data, tabTitles: tabsOfResources(data.specs, data.extraTabs) };
}
