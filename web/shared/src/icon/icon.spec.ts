import { childAvatar } from './icon';

/**
 * The stand-in picture for a child who has no photograph.
 *
 * IT IS TESTED HERE AND NOT ON A SCREEN because the case that matters
 * cannot be produced from real data without editing a real child's file.
 * Both dev children have a gender recorded, so the live check proves the
 * two happy paths and nothing about the third - and the third is the one
 * a centre meets constantly: a file is opened before anybody asks, and
 * some are never asked.
 */
describe('childAvatar', () => {
  it('gives a boy the boy picture', () => {
    expect(childAvatar('M')).toBe('ic-child-boy');
  });

  it('gives a girl the girl picture', () => {
    expect(childAvatar('F')).toBe('ic-child-girl');
  });

  it('falls back to the neutral one when nothing is recorded', () => {
    expect(childAvatar('')).toBe('ic-user');
  });

  it('and for any value this build has not met', () => {
    // Guessing would put a boy's face on a girl's card, which is worse
    // than the neutral one. Anything that is not exactly 'M' or 'F' -
    // a lower-case letter, a word, a value added to the schema later -
    // takes the fallback rather than the nearest match.
    for (const odd of ['m', 'f', 'MALE', 'غير محدد', 'X', ' M']) {
      expect(childAvatar(odd)).withContext(odd).toBe('ic-user');
    }
  });
});
