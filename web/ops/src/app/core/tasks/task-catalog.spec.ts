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
