/**
 * Reading a refusal from the service.
 *
 * The service answers with codes and never with sentences - the Arabic
 * wording lives in the translation bundle, so it changes without a release on
 * either side. This file is the only place that knows the codes; everything
 * above it asks for a message key.
 */

/** Refusals shaped for a screen, from the codes the service documents. */
export type OpsFailure =
  | 'VALIDATION'
  | 'FORBIDDEN'
  | 'NOT_FOUND'
  | 'UNAUTHENTICATED'
  | 'RATE_LIMITED'
  | 'ALREADY_LOGGED'
  | 'NOT_LIVE'
  | 'STREAM_UNAVAILABLE'
  | 'UNAVAILABLE'
  // The value is not a setting: a product decision or a security ceiling.
  // Its own code because no permission turns it on.
  | 'NOT_EDITABLE'
  // The centre row: a value frozen by history, and a value frozen full
  // stop. Separate codes because the first may thaw and the second never
  // does.
  | 'CURRENCY_LOCKED'
  | 'IMMUTABLE'
  // Identity. Each one sends a person somewhere different, which is the
  // whole reason they are not one code:
  //
  //   LAST_ADMIN - the change would leave nobody able to grant anything,
  //     and no screen could ever undo it. Go and give another role
  //     USER.MANAGE first.
  //   NO_SUCH_PERMISSION - a code that does not exist was sent.
  //   NOT_YOUR_OWN_ROLES / NOT_YOURSELF - an account acting on itself.
  //     Ask a different administrator; retrying cannot help.
  //
  // A refusal that arrives as UNKNOWN reads as "try again", and each of
  // these fails identically forever on the second try.
  | 'LAST_ADMIN'
  | 'NO_SUCH_PERMISSION'
  | 'NOT_YOUR_OWN_ROLES'
  | 'NOT_YOURSELF'
  | 'USERNAME_TAKEN'
  | 'NO_SUCH_ROLE'
  | 'SETUP_CODE_INVALID'
  | 'PASSWORD_TOO_SHORT'
  | 'BAD_CURRENT_PASSWORD'
  | 'PASSWORD_UNCHANGED'
  | 'ACCOUNT_LOCKED'
  // A colleague saved the draft report after this editor opened it
  // (migration 0141). Not "try again": the same save fails the same way
  // until the newer text is loaded.
  | 'REPORT_CHANGED'
  | 'UNKNOWN';

/** Why one field was refused, when the service says which and why. */
export type FieldConstraint =
  | 'DUPLICATE'
  | 'REQUIRED'
  | 'NO_SUCH_REFERENCE'
  | 'FORMAT'
  | 'REFUSED';

export interface OpsRefusal {
  readonly failure: OpsFailure;
  /** The field the service named, when it named one. */
  readonly field: string | null;
  readonly constraint: FieldConstraint | null;
  /**
   * The length the refused field had to be, when the rule is a length.
   *
   * It is sent by the service and never assumed here. The national id is
   * fourteen digits in Egypt because sys_params.NATIONAL_ID_LENGTH says so,
   * and a centre may override it - a 14 written into this console would be
   * a business value in code, and would read as authoritative on the day it
   * stopped being true.
   */
  readonly expectedLength: number | null;
  /**
   * The request id from the service. Shown on an unexpected failure so a
   * complaint can be matched to a log line - it identifies the request and
   * says nothing about the account.
   */
  readonly requestId: string | null;
}

const FAILURES: readonly OpsFailure[] = [
  'VALIDATION', 'FORBIDDEN', 'NOT_FOUND', 'UNAUTHENTICATED', 'RATE_LIMITED',
  'ALREADY_LOGGED', 'NOT_LIVE', 'STREAM_UNAVAILABLE', 'UNAVAILABLE', 'NOT_EDITABLE',
  'CURRENCY_LOCKED', 'IMMUTABLE',
  'LAST_ADMIN', 'NO_SUCH_PERMISSION', 'NOT_YOUR_OWN_ROLES', 'NOT_YOURSELF',
  'USERNAME_TAKEN', 'NO_SUCH_ROLE', 'SETUP_CODE_INVALID', 'PASSWORD_TOO_SHORT',
  'BAD_CURRENT_PASSWORD', 'PASSWORD_UNCHANGED', 'ACCOUNT_LOCKED',
  'REPORT_CHANGED',
];

const CONSTRAINTS: readonly FieldConstraint[] = [
  'DUPLICATE', 'REQUIRED', 'NO_SUCH_REFERENCE', 'FORMAT', 'REFUSED',
];

/**
 * Reads the shape only. A code this console has not been taught becomes
 * UNKNOWN and reaches a generic message - guessing would put the wrong
 * sentence in front of someone about to change a child's record.
 */
export function readRefusal(error: unknown): OpsRefusal {
  const shaped = error as {
    status?: number;
    error?: {
      error?: {
        code?: string;
        request_id?: string;
        fields?: { field?: string; constraint?: string; expected_length?: unknown };
      };
    };
  };
  const body = shaped?.error?.error;
  const code = body?.code as OpsFailure | undefined;
  const constraint = body?.fields?.constraint as FieldConstraint | undefined;

  // A number or nothing. The service sends an integer; anything else on
  // this key is a shape this console has not been taught, and a length
  // read out of a string that is not one would put a wrong number in a
  // sentence that is meant to be the correction.
  const length = body?.fields?.expected_length;

  return {
    failure: code && FAILURES.includes(code) ? code : 'UNKNOWN',
    field: body?.fields?.field ?? null,
    constraint: constraint && CONSTRAINTS.includes(constraint) ? constraint : null,
    expectedLength:
      typeof length === 'number' && Number.isInteger(length) && length > 0 ? length : null,
    requestId: body?.request_id ?? null,
  };
}

/**
 * The message key for a refusal.
 *
 * A refused field gets the reason for that field - "this number is already
 * used" is actionable where "invalid input" is not. Everything else falls
 * back to the failure itself.
 *
 * 403 and 404 are kept apart on purpose, because the service keeps them
 * apart: 403 means the permission is missing, 404 means the row is not
 * yours or not there. Collapsing them would tell a user to ask for a
 * permission that would not have helped.
 */
export function refusalKey(refusal: OpsRefusal): string {
  if (refusal.failure === 'VALIDATION' && refusal.constraint) {
    // The field first, when the service named one and this console has a
    // sentence for that field.
    //
    // WHY: "the value is not in the correct format" was the whole message
    // the centre owner got on the staff card, over a national id one digit
    // short. It is true and it is useless - it names no field, states no
    // rule, and the form highlighted nothing, so the only way forward was
    // to guess which of three inputs was wrong and what it wanted.
    //
    // Specific first, generic second, and never a blank: an unmapped field
    // falls back to the constraint's own sentence, which is what every
    // refusal used to get.
    // NEVER the .len variant from here. Most callers store this key in a
    // signal and a template renders it through `| t` with no values, so a
    // key carrying {length} would put the word "{length}" on the screen -
    // a worse message than the vague one it replaced. The key with the
    // number in it is reachable only through refusalSentence, which is the
    // only function here that has the values to fill it.
    const specific = refusal.field ? `error.field.${refusal.field}.${refusal.constraint}` : null;
    if (specific && NAMED_FIELD_KEYS.has(specific)) {
      return specific;
    }
    return `error.field.${refusal.constraint}`;
  }
  return `error.${refusal.failure}`;
}

/**
 * The field sentences this console actually carries.
 *
 * A set and not a guess at the bundle: translate() returns the KEY when it
 * finds no entry, so composing a key that does not exist would print
 * `error.field.national_id.FORMAT` on the screen - worse than the generic
 * sentence it replaced. Adding a field here and to ar.json is one step.
 */
const NAMED_FIELD_KEYS: ReadonlySet<string> = new Set([
  'error.field.national_id.FORMAT',
  'error.field.national_id.FORMAT.len',
  'error.field.national_id.DUPLICATE',
  'error.field.mobile.FORMAT',
  'error.field.mobile.DUPLICATE',
]);

/** Only what a bundle entry can interpolate. Kept narrow on purpose. */
type Translator = {
  translate(key: string, params?: Readonly<Record<string, string | number>>): string;
};

/**
 * The whole sentence for a refusal - field named, rule stated.
 *
 * Use this wherever the message is shown immediately (a toast, an inline
 * note). refusalKey is for the callers that must hand a KEY to a template,
 * and those give up the number; there is no way to pass values through a
 * signal that a `| t` pipe reads with none.
 *
 * The service is the only source of the number. When it did not send one -
 * an older build, an unreadable parameter - the sentence falls back to the
 * one that states the shape without the count, rather than inventing 14.
 */
export function refusalSentence(i18n: Translator, error: unknown): string {
  const refusal = readRefusal(error);
  if (refusal.expectedLength !== null && refusal.field && refusal.constraint) {
    const withLength = `error.field.${refusal.field}.${refusal.constraint}.len`;
    if (NAMED_FIELD_KEYS.has(withLength)) {
      return i18n.translate(withLength, { length: refusal.expectedLength });
    }
  }
  return i18n.translate(refusalKey(refusal));
}
