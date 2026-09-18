import ar from '../assets/i18n/ar.json';

const BUNDLE = ar as Record<string, string>;

/**
 * Keys a SHARED component names from TypeScript, which this app must carry.
 *
 * A shared component under web/shared has no bundle of its own: it names a
 * key and each application resolves it from its own ar.json. So a key added
 * for one application is silently missing in the other, and translate()
 * returns the KEY when it finds nothing - the person reads
 * "chat.cannotMessage" where a sentence should be. This project has shipped
 * a raw key on screen twice.
 *
 * A key inside a template is at least visible to anybody reading it. These
 * are named from code, where nothing points at them from this application at
 * all, which is why they are the ones written down here.
 */
describe('Shared-component keys this console must carry', () => {
  // CH-05: the one sentence for an account that is hidden and one that is
  // not there. Named in family-messages.ts, never in its template.
  it('has the sentence for a conversation you may not have', () => {
    expect(BUNDLE['chat.cannotMessage']).toBeDefined();
  });
});
