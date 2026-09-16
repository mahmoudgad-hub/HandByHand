import { personAvatarChoice } from './person-avatar-choice';

describe('personAvatarChoice', () => {
  const today = new Date(2026, 8, 14);
  it('selects child portraits before the eighteenth birthday', () => {
    expect(personAvatarChoice('F', '2008-09-15', today)).toBe('child-girl');
    expect(personAvatarChoice('M', '2020-01-01', today)).toBe('child-boy');
  });
  it('switches to an adult on the eighteenth birthday', () => {
    expect(personAvatarChoice('F', '2008-09-14', today)).toBe('adult-woman');
    expect(personAvatarChoice('M', '1990-01-01T00:00:00Z', today)).toBe('adult-man');
  });
  it('keeps missing, invalid and future demographics neutral', () => {
    expect(personAvatarChoice('', '2020-01-01', today)).toBeNull();
    for (const date of ['', 'bad', '2020-02-30', '2030-01-01']) {
      expect(personAvatarChoice('F', date, today)).toBeNull();
    }
  });
});
