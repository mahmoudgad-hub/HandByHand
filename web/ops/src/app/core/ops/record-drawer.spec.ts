import {
  childIdFromPath, formatOpen, isDrawerAction, parseOpen, sameTarget, stepFor,
} from './record-drawer';

/**
 * The drawer's address and steps, as data. Every step names an action
 * that exists in day-spec.ts; a name that does not is refused as null,
 * never guessed at.
 */
describe('record-drawer model', () => {
  it('parses the open parameter strictly', () => {
    expect(parseOpen('appointment:881')).toEqual({ entity: 'appointment', id: 881 });
    expect(parseOpen('invoice:12')).toEqual({ entity: 'invoice', id: 12 });
    for (const bad of ['', 'foo', 'appointment', 'appointment:', 'appointment:abc', 'appointment:0',
      'appointment:-1', 'session:5', 'appointment:881x', ' appointment:881', 'appointment:12345678901']) {
      expect(parseOpen(bad)).withContext(bad).toBeNull();
    }
    expect(parseOpen(null)).toBeNull();
    expect(parseOpen(undefined)).toBeNull();
  });

  it('formats and compares targets', () => {
    expect(formatOpen({ entity: 'invoice', id: 3 })).toBe('invoice:3');
    expect(sameTarget({ entity: 'invoice', id: 3 }, { entity: 'invoice', id: 3 })).toBeTrue();
    expect(sameTarget({ entity: 'invoice', id: 3 }, { entity: 'appointment', id: 3 })).toBeFalse();
    expect(sameTarget(null, { entity: 'invoice', id: 3 })).toBeFalse();
  });

  it('resolves a step to the list action it pre-fills, per entity', () => {
    expect(stepFor('appointment', 'confirm')).toEqual({ actionType: 'status', entityType: 'appointments', prefill: { status: 'CONFIRMED' } });
    expect(stepFor('appointment', 'check-in')).toEqual({ actionType: 'status', entityType: 'appointments', prefill: { status: 'CHECKED_IN' } });
    expect(stepFor('appointment', 'start')).toEqual({ actionType: 'start', entityType: 'appointments' });
    expect(stepFor('invoice', 'issue')).toEqual({ actionType: 'issue', entityType: 'invoices' });
    expect(stepFor('invoice', 'pay')).toEqual({ actionType: 'pay', entityType: 'invoices' });
    // A step of the other entity, an unknown name, no name: nothing.
    expect(stepFor('invoice', 'confirm')).toBeNull();
    expect(stepFor('appointment', 'pay')).toBeNull();
    expect(stepFor('appointment', 'reschedule')).toBeNull();
    expect(stepFor('appointment', null)).toBeNull();
  });

  it('recognises step names and nothing else', () => {
    expect(isDrawerAction('confirm')).toBeTrue();
    expect(isDrawerAction('issue')).toBeTrue();
    expect(isDrawerAction('delete')).toBeFalse();
    expect(isDrawerAction('')).toBeFalse();
    expect(isDrawerAction(undefined)).toBeFalse();
  });

  it('reads the child id from a child file address only', () => {
    expect(childIdFromPath('/children/604')).toBe(604);
    expect(childIdFromPath('/children/604?tab=appointments&open=appointment:881')).toBe(604);
    expect(childIdFromPath('/children/604/reports/9')).toBe(604);
    expect(childIdFromPath('/children')).toBeNull();
    expect(childIdFromPath('/guardians/604')).toBeNull();
    expect(childIdFromPath('/children/abc')).toBeNull();
  });
});
