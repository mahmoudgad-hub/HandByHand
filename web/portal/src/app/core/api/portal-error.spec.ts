import { loadErrorKey, readRefusal, traceIdFor } from './portal-error';

/**
 * These guard a distinction that a screen already got wrong once: every
 * failure was shown as "could not load the data", so a bad query parameter -
 * which no amount of retrying will fix - looked exactly like a dropped
 * network, which retrying fixes. A parent was bounced off their own child's
 * diary by a message that pointed at nothing.
 */
describe('portal-error', () => {
  /** A refusal shaped the way the service actually sends one. */
  const refusal = (status: number, code: string, requestId?: string): unknown => ({
    status,
    error: { error: { code, request_id: requestId, fields: { field: 'from|to (RFC3339)' } } },
  });

  it('reads the code, the field and the request id', () => {
    const read = readRefusal(refusal(400, 'VALIDATION', 'b53164867ce1220b'));

    expect(read.code).toBe('VALIDATION');
    expect(read.field).toBe('from|to (RFC3339)');
    expect(read.requestId).toBe('b53164867ce1220b');
  });

  it('survives an error that is not shaped like a refusal at all', () => {
    // A thrown TypeError, a timeout, anything. It must not crash the handler
    // that is already handling a failure.
    const read = readRefusal(new Error('boom'));

    expect(read.code).toBe('');
    expect(read.field).toBeNull();
    expect(read.status).toBe(0);
  });

  it('separates a dropped request from a wrong one', () => {
    // Status 0 means nothing arrived - retrying is the right advice.
    expect(loadErrorKey({ status: 0 })).toBe('error.network');
    // 400 means this screen sent something the service will refuse
    // identically forever. Retrying is not the right advice.
    expect(loadErrorKey(refusal(400, 'VALIDATION'))).toBe('error.badFilter');
  });

  it('keeps a permission refusal apart from a missing row', () => {
    expect(loadErrorKey(refusal(403, 'FORBIDDEN'))).toBe('error.notYours');
    expect(loadErrorKey(refusal(404, 'NOT_FOUND'))).toBe('error.notFound');
  });

  it('offers the request id only where nobody can act on the failure', () => {
    // A 500: the reason never leaves the server, so this string is the only
    // thread between what a parent saw and the line in the centre's log.
    expect(traceIdFor(refusal(500, 'INTERNAL', 'abc123'))).toBe('abc123');
  });

  it('withholds the request id from a refusal a person can act on', () => {
    // A reference number beside "check what you typed" is noise, and noise
    // beside an actionable sentence is what stops it being read.
    expect(traceIdFor(refusal(400, 'VALIDATION', 'abc123'))).toBeNull();
    expect(traceIdFor(refusal(403, 'FORBIDDEN', 'abc123'))).toBeNull();
    expect(traceIdFor({ status: 0 })).toBeNull();
  });
});
