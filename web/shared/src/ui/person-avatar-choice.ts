/** Missing demographics stay neutral; never infer them from a name. */
export function personAvatarChoice(gender: string, birthDate: string, today = new Date()): string | null {
  if (gender !== 'M' && gender !== 'F') return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})(?:T.*)?$/.exec(birthDate);
  if (!match) return null;
  const [, y, m, d] = match.map(Number);
  const birth = new Date(y, m - 1, d);
  if (birth.getFullYear() !== y || birth.getMonth() !== m - 1 || birth.getDate() !== d || birth > today) return null;
  const age = today.getFullYear() - y - (today.getMonth() < m - 1 || (today.getMonth() === m - 1 && today.getDate() < d) ? 1 : 0);
  return age >= 18 ? (gender === 'F' ? 'adult-woman' : 'adult-man') : (gender === 'F' ? 'child-girl' : 'child-boy');
}
