import { EMPTY, Observable, defer, expand, map, reduce } from 'rxjs';

import { Page, Row } from './ops-api';

/**
 * Read a filtered list completely before deriving facts from its absence.
 * A later-page failure must fail the source, never return an incomplete list
 * that can turn an assigned child into an unassigned one. The bound also
 * prevents a changing or broken endpoint from keeping a read alive forever.
 */
export function readAllPages(fetchPage: (page: number) => Observable<Page>): Observable<readonly Row[]> {
  return defer(() => {
    let limit: number | undefined;
    const read = (number: number) => fetchPage(number).pipe(map((page) => {
      limit ??= page.limit;
      if (!Number.isInteger(page.total) || page.total < 0
        || !Number.isInteger(page.offset) || page.offset < 0
        || page.limit !== limit || page.offset !== (number - 1) * limit
        || (page.total > 0 && (!Number.isInteger(limit) || limit <= 0))) {
        throw new Error('Invalid list pagination');
      }
      const more = page.offset + page.rows.length < page.total;
      if (more && (page.rows.length !== limit || number >= 200)) {
        throw new Error('List could not be read completely');
      }
      return { page, number, more };
    }));
    return read(1).pipe(
      expand((result) => result.more ? read(result.number + 1) : EMPTY, 1),
      reduce((rows, result) => { rows.push(...result.page.rows); return rows; }, [] as Row[]),
    );
  });
}
