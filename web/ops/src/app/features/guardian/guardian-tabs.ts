/**
 * The tabs of a guardian's file. See child-tabs.ts for why they live apart
 * from the component: the route needs them to declare the tab titles, and
 * importing the component from the route would load a lazy screen eagerly.
 */
export type GuardianTab = 'overview' | 'beneficiaries' | 'applications' | 'appointments'
  | 'finance' | 'communication' | 'activity';

export const GUARDIAN_TABS: readonly GuardianTab[] = [
  'overview', 'beneficiaries', 'applications', 'appointments', 'finance', 'communication', 'activity',
];
