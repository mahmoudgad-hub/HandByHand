import ar from '../../../assets/i18n/ar.json';
import { OpsFailure, readRefusal, refusalKey } from './ops-error';

const BUNDLE = ar as Record<string, string>;

const refusal = (code: string, status = 409) =>
  ({ status, error: { error: { code, request_id: 'r1' } } });

/**
 * The twenty-one codes that stopped being answered by a catch-all (HBH-050).
 *
 * On 2026-09-12 the service gave twenty-one live HB codes their own answers.
 * Five became 404, six became 500, and three arrived here as codes of their
 * own that this console had never been taught - so they were filed under
 * UNKNOWN and reached the person as "an unexpected error occurred, try
 * again". Two of the three cannot succeed on a second try, and the third is
 * the live-view consent gate, where "refused" sends reception to an
 * administrator instead of to the family.
 *
 * WHAT THESE TESTS ARE FOR is the next time rather than this one. The API
 * contract will grow another code, and the failure will look exactly like
 * this one did: nothing throws, nothing is red, and a person reads a
 * sentence that tells them to do something that cannot work.
 */
describe('Refusal codes the service actually sends', () => {
  it('names the three that used to fall through to UNKNOWN', () => {
    for (const code of ['CONSENT_REQUIRED', 'PROFILE_CONSENT_REQUIRED', 'TEXT_LOCKED', 'NOT_A_PASSWORD_USER']) {
      expect(readRefusal(refusal(code)).failure)
        .withContext(`${code} is read as itself, not as UNKNOWN`).toBe(code as OpsFailure);
    }
  });

  /**
   * The fourth acceptance criterion, as a guard rather than a reading: no
   * code is read in a screen without an Arabic sentence behind it.
   *
   * translate() returns the KEY when it finds nothing, so a missing entry
   * does not fail - it prints "error.TEXT_LOCKED" at a receptionist, which
   * is worse than the vague sentence it replaced.
   */
  it('has an Arabic sentence for every failure this console can read', () => {
    const missing: string[] = [];
    // Every member of the union, reached the way a screen reaches it.
    const codes: readonly OpsFailure[] = [
      'VALIDATION', 'FORBIDDEN', 'NOT_FOUND', 'UNAUTHENTICATED', 'RATE_LIMITED',
      'ALREADY_LOGGED', 'NOT_LIVE', 'STREAM_UNAVAILABLE', 'UNAVAILABLE', 'NOT_EDITABLE',
      'CURRENCY_LOCKED', 'IMMUTABLE', 'LAST_ADMIN', 'NO_SUCH_PERMISSION',
      'NOT_YOUR_OWN_ROLES', 'NOT_YOURSELF', 'USERNAME_TAKEN', 'NO_SUCH_ROLE',
      'SETUP_CODE_INVALID', 'PASSWORD_TOO_SHORT', 'BAD_CURRENT_PASSWORD',
      'PASSWORD_UNCHANGED', 'ACCOUNT_LOCKED', 'REPORT_CHANGED',
      'CONSENT_REQUIRED', 'PROFILE_CONSENT_REQUIRED', 'TEXT_LOCKED', 'NOT_A_PASSWORD_USER', 'UNKNOWN',
    ];
    for (const code of codes) {
      const key = refusalKey(readRefusal(refusal(code)));
      if (BUNDLE[key] === undefined) {
        missing.push(`${code} -> ${key}`);
      }
    }
    expect(missing).toEqual([]);
  });

  /**
   * The six that became 500.
   *
   * HB001, HB010, HB012, HB220, HB230 and HB231 are assertions inside our
   * own machinery - an append-only table edited, a number series never
   * seeded. They are not a rule the caller broke and must not be dressed as
   * one: the person reads the unexpected-failure sentence, with the request
   * id that lets the complaint be matched to a log line.
   */
  it('does not dress our own failure as a business rule', () => {
    const read = readRefusal({ status: 500, error: { error: { code: 'INTERNAL', request_id: 'abc' } } });
    expect(read.failure).toBe('UNKNOWN');
    expect(refusalKey(read)).toBe('error.UNKNOWN');
    // And the id survives, because it is the only thing that makes such a
    // failure reportable.
    expect(read.requestId).toBe('abc');
  });

  /**
   * The five that became 404 - HB041, HB073, HB082, HB094, HB201 - and the
   * two that became 403. The schema refuses to say which of "gone" and "not
   * yours" it means, and the console must not guess either: these are
   * different sentences and collapsing them would tell somebody to ask for
   * a permission that would not have helped.
   */
  it('keeps "not yours" and "not allowed" apart', () => {
    expect(refusalKey(readRefusal(refusal('NOT_FOUND', 404)))).toBe('error.NOT_FOUND');
    expect(refusalKey(readRefusal(refusal('FORBIDDEN', 403)))).toBe('error.FORBIDDEN');
    expect(BUNDLE['error.NOT_FOUND']).not.toBe(BUNDLE['error.FORBIDDEN']);
  });
});

/**
 * Two consents are not one word (2026-09-18).
 *
 * For one day the service answered CONSENT_REQUIRED for both a family's
 * live-view consent (HB081) and a therapist's consent to publish their
 * profile (HB142), and two screens had to override the shared sentence to
 * avoid telling somebody that a therapist had not agreed to a camera. The
 * service split them; these hold the split down from this side, so the day
 * anybody folds them back the console says so rather than quietly printing
 * the wrong sentence on one of the two screens.
 */
describe('The two consents', () => {
  it('reads each as itself', () => {
    expect(readRefusal(refusal('CONSENT_REQUIRED')).failure).toBe('CONSENT_REQUIRED');
    expect(readRefusal(refusal('PROFILE_CONSENT_REQUIRED')).failure).toBe('PROFILE_CONSENT_REQUIRED');
  });

  it('says a different thing for each, and says what to do', () => {
    const family = BUNDLE[refusalKey(readRefusal(refusal('CONSENT_REQUIRED')))];
    const therapist = BUNDLE[refusalKey(readRefusal(refusal('PROFILE_CONSENT_REQUIRED')))];
    expect(family).not.toBe(therapist);
    // Each names WHOSE consent is missing. A sentence that says neither is
    // the one reception cannot act on.
    expect(family).toContain('الأسرة');
    expect(therapist).toContain('الأخصائي');
  });
});
