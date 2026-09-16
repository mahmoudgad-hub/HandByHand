import { TestBed } from '@angular/core/testing';
import { Subject } from 'rxjs';
import { FormatService } from '@hbh/shared/format/format.service';
import { OpsApi, Page } from '../api/ops-api';
import { OpsAuthService } from '../auth/ops-auth.service';
import { DayApi } from '../ops/day-api';
import { Task } from './task-model';
import { TasksService, sortTasks } from './tasks.service';

describe('TasksService complete assignment reads', () => {
  function setup() {
    const children = new Subject<Page>();
    const first = new Subject<Page>();
    const second = new Subject<Page>();
    const list = jasmine.createSpy().and.callFake((resource: string, query: { page: number }) =>
      resource === 'children' ? children : query.page === 1 ? first : second);
    TestBed.configureTestingModule({ providers: [
      { provide: OpsApi, useValue: { list } },
      { provide: DayApi, useValue: {} },
      { provide: FormatService, useValue: { today: () => '2026-09-14' } },
      { provide: OpsAuthService, useValue: { can: (p: string) => p === 'STAFF.MANAGE', me: () => ({}) } },
    ] });
    return { service: TestBed.inject(TasksService), children, first, second, list };
  }

  it('shares concurrent loads and excludes a child assigned on a later page', () => {
    const { service, children, first, second, list } = setup();
    const run = service.load();
    const received = jasmine.createSpy();
    run.subscribe(received);
    expect(service.load()).toBe(run);
    expect(list.calls.count()).toBe(2);
    children.next({ rows: [{ child_id: 5, status: 'ACTIVE' }, { child_id: 6, status: 'ACTIVE' }], total: 2, limit: 100, offset: 0 });
    children.complete();
    first.next({ rows: [{ child_id: 99 }], total: 2, limit: 1, offset: 0 });
    first.complete();
    expect(received).not.toHaveBeenCalled();
    second.next({ rows: [{ child_id: 5 }], total: 2, limit: 1, offset: 1 });
    second.complete();
    expect(service.tasks().map(t => t.entityId)).toEqual([6]);
    expect(service.tasks()[0].primaryAction).toEqual(jasmine.objectContaining({
      link: ['/children', 6], query: { action: 'assign' },
    }));
    expect(received).toHaveBeenCalledTimes(1);
    run.subscribe();
    expect(list.calls.count()).toBe(3);
    expect(service.loading()).toBeFalse();
  });

  it('reports a failed assignment source instead of false unassigned children', () => {
    const { service, children, first, second } = setup();
    service.load();
    children.next({ rows: [{ child_id: 5, status: 'ACTIVE' }], total: 1, limit: 100, offset: 0 });
    children.complete();
    first.next({ rows: [{ child_id: 99 }], total: 2, limit: 1, offset: 0 });
    first.complete();
    second.error(new Error('unavailable'));
    expect(service.tasks()).toEqual([]);
    expect(service.failed()).toEqual(['CHILD_ASSIGN_THERAPIST']);
    expect(service.loading()).toBeFalse();
  });
});

/** Display order: newest first across every surface. */
describe('sortTasks', () => {
  function task(id: string, extra: Partial<Task>): Task {
    return {
      id, taskType: 'APPOINTMENT_CONFIRM', titleKey: 't', descriptionKey: 'd', entityType: 'APPOINTMENT',
      entityId: 1, entityDisplayName: id, priority: 'normal', assignedRole: 'APPOINTMENT.BOOK',
      primaryAction: { labelKey: 'l', link: ['/tasks'] }, secondaryActions: [], ...extra,
    };
  }

  it('uses newest timestamps regardless of priority or assignee', () => {
    const sorted = sortTasks([
      task('shared-late', { dueDate: '2026-09-13T12:00:00Z' }),
      task('mine-late', { assignedUser: 'me', dueDate: '2026-09-13T12:00:00Z' }),
      task('shared-early', { dueDate: '2026-09-13T08:00:00Z' }),
      task('urgent-shared', { priority: 'urgent', dueDate: '2026-09-13T15:00:00Z' }),
      task('mine-early', { assignedUser: 'me', dueDate: '2026-09-13T09:00:00Z' }),
    ]).map((t) => t.id);
    expect(sorted).toEqual(['urgent-shared', 'shared-late', 'mine-late', 'mine-early', 'shared-early']);
  });

  it('uses creation before due dates, handles timezone offsets and keeps undated tasks last',()=>{
    const rows=[task('old-urgent',{priority:'urgent',createdAt:'2026-09-13T12:00:00Z',dueDate:'2099-01-01'}),task('new',{createdAt:'2026-09-14T12:00:00Z'}),task('offset',{createdAt:'2026-09-14T13:00:00+03:00'}),task('unknown',{})];
    expect(sortTasks(rows).map(t=>t.id)).toEqual(['new','offset','old-urgent','unknown']);
    expect(rows[0].id).toBe('old-urgent');
  });
  it('is silent for an account nothing is addressed to', () => {
    const sorted = sortTasks([
      task('b', { dueDate: '2026-09-13T12:00:00Z' }),
      task('a', { dueDate: '2026-09-13T08:00:00Z' }),
    ]).map((t) => t.id);
    expect(sorted).toEqual(['b', 'a']);
  });
});
