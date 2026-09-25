/**
 * The tabs of a child's file, and the one list that names them.
 *
 * They live apart from the component because TWO places need them and only
 * one of them may load a component: the screen draws them, and the route
 * declares their titles so the announcer can name the tab in the browser
 * title without asking a component that navigation has not created yet
 * (HBH-039, HBH-102). A file this small pulls nothing in behind it.
 *
 * ONE LIST, so a tab added here is drawn AND named. The alternative - the
 * route repeating the names - drifts silently: the new tab appears, the
 * title keeps saying the screen's own name, and nothing is red.
 */
export type ChildTab = 'overview' | 'family' | 'appointments' | 'sessions' | 'assessments'
  | 'plans' | 'goals' | 'reports' | 'packages' | 'invoices' | 'notes' | 'home' | 'activity';

export const CHILD_TABS: readonly ChildTab[] = [
  'overview', 'family', 'appointments', 'sessions', 'assessments', 'plans', 'goals',
  'reports', 'packages', 'invoices', 'notes', 'home', 'activity',
];
