import ar from '../assets/i18n/ar.json';

const BUNDLE = ar as Record<string, string>;

/**
 * Keys a SHARED component names from TypeScript, which this portal must carry.
 *
 * The twin of the console's file, and it exists because the two bundles are
 * separate: FamilyMessages is mounted in both, names its keys in code, and a
 * key added to one ar.json is missing from the other with nothing to say so.
 * translate() returns the KEY when it finds none, so the failure reaches a
 * parent as "chat.cannotMessage" printed where a sentence belongs.
 */
describe('Shared-component keys this portal must carry', () => {
  // CH-05: one sentence for an account that is hidden and one that is not
  // there. Named in family-messages.ts, never in its template.
  it('has the sentence for a conversation you may not have', () => {
    expect(BUNDLE['chat.cannotMessage']).toBeDefined();
  });
});
