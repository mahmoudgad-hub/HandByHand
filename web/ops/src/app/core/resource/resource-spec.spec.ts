import ar from '../../../assets/i18n/ar.json';
import * as all from './resource-spec';
import { ResourceSpec } from './resource-spec';

/**
 * Search placeholders (#17). Every list screen that takes a search term says
 * what the term is matched against; one that takes none offers no box to
 * type into.
 *
 * What this cannot check is the other half - that the sentence names the
 * columns crud.go actually searches. That pairing is written next to
 * `searchKey` in resource-spec.ts, and each sentence was written from the
 * `search` list on 2026-09-13.
 */
const BUNDLE = ar as Record<string, string>;

const SPECS = Object.values(all).filter(
  (value): value is ResourceSpec =>
    !!value && typeof value === 'object' && 'resource' in value && 'fields' in value);

describe('search placeholders', () => {
  it('has specs to read', () => {
    expect(SPECS.filter((s) => s.searchable).length).toBeGreaterThanOrEqual(8);
  });

  it('gives every searchable list its own sentence', () => {
    for (const spec of SPECS.filter((s) => s.searchable)) {
      expect(spec.searchKey).withContext(`${spec.resource} is searchable with no searchKey`).toBeDefined();
      expect(BUNDLE[spec.searchKey ?? ''])
        .withContext(`${spec.resource}: "${spec.searchKey}" is not in ar.json`).toBeDefined();
    }
  });

  it('does not describe a search on a list that takes none', () => {
    for (const spec of SPECS.filter((s) => !s.searchable)) {
      expect(spec.searchKey).withContext(`${spec.resource} has a searchKey but is not searchable`).toBeUndefined();
    }
  });

  it('never promises a code where none is searched', () => {
    // The generic sentence said "by name or code". Therapists have no code
    // column searched - the case this item was opened for.
    const therapists = SPECS.find((s) => s.resource === 'therapists');
    expect(BUNDLE[therapists?.searchKey ?? '']).not.toContain('كود');
  });
});
