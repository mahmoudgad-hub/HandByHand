import { of, throwError } from 'rxjs';
import { readAllPages } from './read-all-pages';

describe('readAllPages', () => {
  it('includes records beyond the first page in one complete result', () => {
    const fetch = jasmine.createSpy().and.callFake((page: number) => of({
      rows: page === 1 ? [{ id: 1 }, { id: 2 }] : [{ id: 3 }],
      total: 3, limit: 2, offset: (page - 1) * 2,
    }));
    const next = jasmine.createSpy();
    readAllPages(fetch).subscribe(next);
    expect(fetch.calls.allArgs()).toEqual([[1], [2]]);
    expect(next.calls.allArgs()).toEqual([[[{ id: 1 }, { id: 2 }, { id: 3 }]]]);
  });

  it('does not publish a partial list when a later page fails', () => {
    const next = jasmine.createSpy();
    const error = jasmine.createSpy();
    readAllPages(page => page === 1
      ? of({ rows: [{ id: 1 }], total: 2, limit: 1, offset: 0 })
      : throwError(() => new Error('unavailable'))).subscribe({ next, error });
    expect(next).not.toHaveBeenCalled();
    expect(error).toHaveBeenCalled();
  });

  it('fails instead of treating a repeated page as complete', () => {
    const error = jasmine.createSpy();
    readAllPages(() => of({ rows: [{ id: 1 }], total: 2, limit: 1, offset: 0 }))
      .subscribe({ next: () => fail('partial data'), error });
    expect(error).toHaveBeenCalled();
  });

  it('accepts an empty list', () => {
    readAllPages(() => of({ rows: [], total: 0, limit: 0, offset: 0 }))
      .subscribe(rows => expect(rows).toEqual([]));
  });
});
