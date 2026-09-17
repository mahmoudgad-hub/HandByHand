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

  /**
   * An option whose label is missing renders as its own key - "nps.code.
   * PARENT_SESSION" in a box a receptionist picks from. Every list on every
   * form, checked at once, because the next list added will be added the
   * same way this one was.
   */
  it('has a translated label for every option on every list', () => {
    const missing: string[] = [];
    for (const spec of SPECS) {
      for (const field of spec.fields) {
        for (const option of field.options ?? []) {
          if (BUNDLE[option.labelKey] === undefined) {
            missing.push(`${spec.resource}.${field.name}: ${option.labelKey}`);
          }
        }
      }
    }
    expect(missing).toEqual([]);
  });

  /**
   * The survey code is picked, not typed: two spellings of one purpose are
   * two surveys under `uq_nps_code`, and the results screen then reports one
   * question twice.
   */
  it('offers the survey codes as a list', () => {
    const surveys = SPECS.find((s) => s.resource === 'nps-surveys');
    const code = surveys?.fields.find((f) => f.name === 'code');
    expect(code?.kind).toBe('select');
    expect(code?.options?.map((o) => o.value)).toContain('PARENT_SESSION');
  });

  it('never promises a code where none is searched', () => {
    // The generic sentence said "by name or code". Therapists have no code
    // column searched - the case this item was opened for.
    const therapists = SPECS.find((s) => s.resource === 'therapists');
    expect(BUNDLE[therapists?.searchKey ?? '']).not.toContain('كود');
  });
});
