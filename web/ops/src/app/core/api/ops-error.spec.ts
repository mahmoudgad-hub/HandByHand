import ar from '../../../assets/i18n/ar.json';
import { readRefusal, refusalKey, refusalSentence } from './ops-error';

/**
 * Reading a refusal, and turning it into a sentence somebody can act on.
 *
 * WHY THIS FILE EXISTS. The centre owner saved a staff record with a
 * national id one digit short and was told "صيغة القيمة غير صحيحة." - true,
 * and unusable: it named no field, stated no rule, and vanished with the
 * toast. The repair carries the required length FROM THE SERVICE, because
 * sys_params.NATIONAL_ID_LENGTH decides it and a 14 written into this
 * console would be a business value in code.
 *
 * That repair introduces a failure mode worse than the message it replaces:
 * a key holding {length} reached without its value prints the word
 * "{length}" to the person the sentence was written for. Most callers store
 * a KEY in a signal that a template renders through `| t` with no values,
 * so the last two tests are the ones that matter - they are the reason
 * refusalKey is forbidden to return the .len variant at all.
 */

/** The bundle, as the running app loads it. */
const BUNDLE = ar as Record<string, string>;

/** An HttpErrorResponse as the interceptor hands it on. */
function refusalFrom(fields: Record<string, unknown>): unknown {
  return { status: 400, error: { error: { code: 'VALIDATION', request_id: 'req-1', fields } } };
}

/** The bundle's sentence, filled the way I18nService fills it. */
function render(key: string, params: Record<string, string | number> = {}): string {
  const text = BUNDLE[key] ?? key;
  return text.replace(/\{(\w+)\}/g, (whole, name: string) =>
    name in params ? String(params[name]) : whole,
  );
}

const i18n = {
  translate: (key: string, params?: Readonly<Record<string, string | number>>) =>
    render(key, (params ?? {}) as Record<string, string | number>),
};

describe('readRefusal', () => {
  it('lifts the field, the constraint and the required length', () => {
    const refusal = readRefusal(
      refusalFrom({ field: 'national_id', constraint: 'FORMAT', expected_length: 14 }),
    );
    expect(refusal.failure).toBe('VALIDATION');
    expect(refusal.field).toBe('national_id');
    expect(refusal.constraint).toBe('FORMAT');
    expect(refusal.expectedLength).toBe(14);
  });

  it('takes no length from a service that sent none', () => {
    const refusal = readRefusal(refusalFrom({ field: 'national_id', constraint: 'FORMAT' }));
    expect(refusal.expectedLength).toBeNull();
  });

  it('refuses a length that is not a whole positive number', () => {
    // A string, a float or a zero would each put a number in a sentence
    // that is meant to BE the correction. Anything but an integer is
    // treated as "the service did not say".
    for (const odd of ['14', 14.5, 0, -14, null, {}]) {
      const refusal = readRefusal(
        refusalFrom({ field: 'national_id', constraint: 'FORMAT', expected_length: odd }),
      );
      expect(refusal.expectedLength).withContext(JSON.stringify(odd)).toBeNull();
    }
  });
});

describe('refusalSentence', () => {
  it('states the field and the length the service sent', () => {
    const text = refusalSentence(
      i18n,
      refusalFrom({ field: 'national_id', constraint: 'FORMAT', expected_length: 14 }),
    );
    expect(text).toContain('الرقم القومي');
    expect(text).toContain('14');
    expect(text).not.toContain('{');
  });

  it('uses the length the service sent and never a remembered one', () => {
    // A centre may override NATIONAL_ID_LENGTH. If this console ever
    // prefers its own idea of the number, the sentence sends somebody to
    // count digits in a value that was already right.
    const text = refusalSentence(
      i18n,
      refusalFrom({ field: 'national_id', constraint: 'FORMAT', expected_length: 15 }),
    );
    expect(text).toContain('15');
    expect(text).not.toContain('14');
  });

  it('falls back to the field sentence with no count when none was sent', () => {
    const text = refusalSentence(i18n, refusalFrom({ field: 'national_id', constraint: 'FORMAT' }));
    expect(text).toContain('الرقم القومي');
    expect(text).not.toContain('{');
  });

  it('still answers for a field this console has no sentence for', () => {
    const text = refusalSentence(i18n, refusalFrom({ field: 'city', constraint: 'FORMAT' }));
    expect(text).toBe(BUNDLE['error.field.FORMAT']);
  });
});

describe('refusalKey', () => {
  it('never returns a key that needs a value', () => {
    // THE ONE THAT GUARDS THE REPAIR. Callers store this key and a
    // template renders it with no parameters, so a key carrying {length}
    // would put that word on the screen. Every key this function can
    // return is checked against the bundle it will be rendered from.
    const fields = ['national_id', 'mobile', 'city', null];
    const constraints = ['FORMAT', 'DUPLICATE', 'REQUIRED', 'NO_SUCH_REFERENCE', 'REFUSED'];
    for (const field of fields) {
      for (const constraint of constraints) {
        for (const length of [14, undefined]) {
          const key = refusalKey(
            readRefusal(refusalFrom({ field, constraint, expected_length: length })),
          );
          expect(BUNDLE[key]).withContext(`${key} is missing from ar.json`).toBeDefined();
          expect(BUNDLE[key]).withContext(`${key} needs a value`).not.toContain('{');
        }
      }
    }
  });

  it('names the field when the console has a sentence for it', () => {
    const key = refusalKey(readRefusal(refusalFrom({ field: 'national_id', constraint: 'FORMAT' })));
    expect(key).toBe('error.field.national_id.FORMAT');
  });

  it('leaves a failure that is not about a field alone', () => {
    const key = refusalKey(
      readRefusal({ status: 403, error: { error: { code: 'FORBIDDEN' } } }),
    );
    expect(key).toBe('error.FORBIDDEN');
  });

  it('names a draft a colleague saved, rather than calling it unexpected', () => {
    // Migration 0141. As UNKNOWN the editor would say "try again" - and the
    // same save is refused the same way until the newer text is loaded.
    const refusal = readRefusal(
      { status: 409, error: { error: { code: 'REPORT_CHANGED' } } });
    expect(refusal.failure).toBe('REPORT_CHANGED');
    expect(BUNDLE[refusalKey(refusal)]).toBeDefined();
  });
});

describe('the bundle', () => {
  it('carries every sentence refusalSentence can reach', () => {
    // refusalSentence composes `.len` keys by hand. A key with no entry
    // renders as its own name - "error.field.national_id.FORMAT.len" on
    // the screen - which is the failure this repair exists to end.
    for (const key of ['error.field.national_id.FORMAT.len']) {
      expect(BUNDLE[key]).withContext(key).toBeDefined();
      expect(BUNDLE[key]).withContext(`${key} must interpolate {length}`).toContain('{length}');
    }
  });
});
