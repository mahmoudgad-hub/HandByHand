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
        fields?: { field?: string; constraint?: string };
      };
    };
  };
  const body = shaped?.error?.error;
  const code = body?.code as OpsFailure | undefined;
  const constraint = body?.fields?.constraint as FieldConstraint | undefined;

  return {
    failure: code && FAILURES.includes(code) ? code : 'UNKNOWN',
    field: body?.fields?.field ?? null,
    constraint: constraint && CONSTRAINTS.includes(constraint) ? constraint : null,
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
    return `error.field.${refusal.constraint}`;
  }
  return `error.${refusal.failure}`;
}
