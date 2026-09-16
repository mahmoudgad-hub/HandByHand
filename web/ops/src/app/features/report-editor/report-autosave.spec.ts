import { AutosaveState, AutosaveTimer, autosaveHold } from './report-autosave';

/**
 * Autosave for report drafts (#13). The two things tested are the two that
 * fail silently: saving when it must not (over a colleague, or creating a
 * report nobody asked for), and not saving when it should (someone who
 * never stops typing).
 */
describe('autosaveHold', () => {
  const ready: AutosaveState = {
    hasReport: true, published: false, saving: false, publishing: false,
    changed: false, dirty: true,
  };

  it('saves an edited draft', () => {
    expect(autosaveHold(ready)).toBeNull();
  });

  it('never creates a report on its own', () => {
    // Even dirty: a report number and a record on the child are a decision.
    expect(autosaveHold({ ...ready, hasReport: false })).toBe('NEW');
  });

  it('stops after a colleague saved, even with unsaved text', () => {
    // The #14 refusal would repeat forever; the text must stay on screen.
    expect(autosaveHold({ ...ready, changed: true })).toBe('CHANGED');
  });

  it('waits for a save already on its way', () => {
    expect(autosaveHold({ ...ready, saving: true })).toBe('BUSY');
    expect(autosaveHold({ ...ready, publishing: true })).toBe('BUSY');
  });

  it('leaves a published report and a clean draft alone', () => {
    expect(autosaveHold({ ...ready, published: true })).toBe('PUBLISHED');
    expect(autosaveHold({ ...ready, dirty: false })).toBe('CLEAN');
  });
});

describe('AutosaveTimer', () => {
  let fired: number;
  let timer: AutosaveTimer;

  beforeEach(() => {
    jasmine.clock().install();
    fired = 0;
    timer = new AutosaveTimer(() => fired++, 3000, 30000);
  });
  afterEach(() => {
    timer.cancel();
    jasmine.clock().uninstall();
  });

  it('fires once typing pauses', () => {
    timer.poke();
    jasmine.clock().tick(2999);
    expect(fired).toBe(0);
    jasmine.clock().tick(1);
    expect(fired).toBe(1);
  });

  it('restarts the pause on every keystroke', () => {
    timer.poke();
    jasmine.clock().tick(2000);
    timer.poke();
    jasmine.clock().tick(2000);
    expect(fired).toBe(0);
    jasmine.clock().tick(1000);
    expect(fired).toBe(1);
  });

  it('still saves someone who never pauses', () => {
    // A keystroke every second for a minute: the pause never comes.
    for (let second = 0; second < 60; second++) {
      timer.poke();
      jasmine.clock().tick(1000);
    }
    expect(fired).toBeGreaterThanOrEqual(1);
    expect(fired).toBeLessThanOrEqual(2);
  });

  it('fires once, not twice, when the pause and the ceiling meet', () => {
    timer.poke();
    jasmine.clock().tick(30000);
    expect(fired).toBe(1);
  });

  it('does nothing after cancel', () => {
    timer.poke();
    timer.cancel();
    jasmine.clock().tick(60000);
    expect(fired).toBe(0);
  });
});
