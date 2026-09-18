/**
 * The tabs of one enrolment application. See child-tabs.ts for why they live
 * apart from the component.
 */
export type EnrolmentTab = 'overview' | 'beneficiary' | 'family' | 'appointments'
  | 'assessment' | 'recommendations' | 'notes' | 'activity';

export const ENROLMENT_TABS: readonly EnrolmentTab[] = [
  'overview', 'beneficiary', 'family', 'appointments', 'assessment', 'recommendations',
  'notes', 'activity',
];
