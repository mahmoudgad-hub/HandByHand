import { of } from 'rxjs';
import { FormatService } from '@hbh/shared/format/format.service';
import { OpsApi } from '../api/ops-api';
import { DayApi } from '../ops/day-api';
import { TASK_CATALOG } from './task-catalog';

describe('Open session task window', () => {
  it('reads previous days and carries the session day and personal scope to its list', () => {
    const list = jasmine.createSpy().and.returnValue(of({
      rows: [{ session_id: 7, started_at: '2026-09-13T23:30:00Z', therapist: { therapist_id: 2 } }],
      total: 1, limit: 100, offset: 0,
    }));
    const format = jasmine.createSpyObj<FormatService>('FormatService', ['today']);
    format.today.and.returnValue('2026-09-14');
    TASK_CATALOG.find(s => s.type === 'SESSION_CLOSE')!.fetch({
      day: { list } as unknown as DayApi, crud: {} as OpsApi, format,
      now: new Date('2026-09-14T12:00:00Z'), today: '2026-09-14', therapistId: 2,
    }).subscribe(tasks => {
      expect(tasks.map(t => t.entityId)).toEqual([7]);
      expect(tasks[0].primaryAction.query).toEqual({ status: 'IN_PROGRESS', focus: '7', date: '2026-09-14', view: 'mine' });
    });
    expect(list).toHaveBeenCalledWith('sessions', jasmine.objectContaining({
      from: '2026-08-15T12:00:00.000Z', to: '2026-09-14T12:00:00.000Z', mine: true,
    }));
    expect(format.today).toHaveBeenCalledWith(new Date('2026-09-13T23:30:00Z'));
  });
});

/**
 * The check-in card: a confirmed appointment about to start, and one whose
 * hour has passed with nobody checked in. Same state, different ask.
 */
describe('APPOINTMENT_CHECK_IN wording', () => {
  it('asks for a check-in on an appointment about to start, and for a decision on one whose hour has passed', () => {
    const rows = [
      { appointment_id: 1, status: 'CONFIRMED', starts_at: '2026-09-18T10:10:00Z', ends_at: '2026-09-18T10:55:00Z' },
      { appointment_id: 2, status: 'CONFIRMED', starts_at: '2026-09-18T08:00:00Z', ends_at: '2026-09-18T08:45:00Z' },
      // Too far ahead: not yet a card at all.
      { appointment_id: 3, status: 'CONFIRMED', starts_at: '2026-09-18T12:00:00Z', ends_at: '2026-09-18T12:45:00Z' },
    ];
    const list = jasmine.createSpy().and.returnValue(of({ rows, total: rows.length, limit: 100, offset: 0 }));
    const format = jasmine.createSpyObj<FormatService>('FormatService', ['today']);
    format.today.and.returnValue('2026-09-18');
    let seen: readonly { entityId: number; descriptionKey: string }[] = [];
    TASK_CATALOG.find(s => s.type === 'APPOINTMENT_CHECK_IN')!.fetch({
      day: { list } as unknown as DayApi, crud: {} as OpsApi, format,
      now: new Date('2026-09-18T10:00:00Z'), today: '2026-09-18', therapistId: undefined,
    }).subscribe(tasks => { seen = tasks; });
    expect(seen.map(t => t.entityId)).toEqual([1, 2]);
    expect(seen[0].descriptionKey).toBe('tasks.type.APPOINTMENT_CHECK_IN.action');
    expect(seen[1].descriptionKey).toBe('tasks.type.APPOINTMENT_CHECK_IN.actionPast');
  });
});
