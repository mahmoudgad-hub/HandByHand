import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';

import { DEFAULT_HBH_CONFIG, HBH_CONFIG } from '@hbh/shared/config/app-config';
import { DrawerRequest } from '../../core/ops/record-drawer';
import { RecordDrawerService } from '../../core/ops/record-drawer.service';
import { Task } from '../../core/tasks/task-model';
import { TaskCard } from './task-card';

/**
 * A card's button opens the record drawer here when the task is about a
 * record the drawer shows, and navigates otherwise. Nothing is done from
 * the card either way.
 */
describe('TaskCard', () => {
  let opened: DrawerRequest[];

  const ROW = { appointment_id: 881, status: 'BOOKED' };
  const base: Task = {
    id: 'APPOINTMENT_CONFIRM:881', taskType: 'APPOINTMENT_CONFIRM',
    titleKey: 'tasks.type.APPOINTMENT_CONFIRM.title', descriptionKey: 'tasks.type.APPOINTMENT_CONFIRM.action',
    entityType: 'APPOINTMENT', entityId: 881, entityDisplayName: 'عمر خالد', childName: 'عمر خالد', childId: 5,
    priority: 'normal', assignedRole: 'APPOINTMENT.BOOK', row: ROW,
    primaryAction: {
      labelKey: 'tasks.type.APPOINTMENT_CONFIRM.cta', link: ['/tasks'],
      query: { open: 'appointment:881', action: 'confirm' },
      drawer: { entity: 'appointment', id: 881, action: 'confirm' },
    },
    secondaryActions: [{ labelKey: 'tasks.openList', link: ['/appointments'], query: { focus: '881' } }],
  };

  function mount(task: Task): ComponentFixture<TaskCard> {
    TestBed.configureTestingModule({
      imports: [TaskCard],
      providers: [
        provideRouter([]), provideHttpClient(), provideHttpClientTesting(),
        { provide: HBH_CONFIG, useValue: { ...DEFAULT_HBH_CONFIG, apiBaseUrl: '' } },
        { provide: RecordDrawerService, useValue: { open: (request: DrawerRequest) => opened.push(request) } },
      ],
    });
    const fixture = TestBed.createComponent(TaskCard);
    fixture.componentRef.setInput('task', task);
    fixture.detectChanges();
    return fixture;
  }

  beforeEach(() => { opened = []; });

  it('opens the drawer on its own row, with the step, without navigating', () => {
    const fixture = mount(base);
    const el = fixture.nativeElement as HTMLElement;
    const primary = el.querySelector<HTMLButtonElement>('.task__actions button.hbh-btn--primary');
    expect(primary).withContext('a button, not a link').not.toBeNull();
    primary!.click();
    expect(opened.length).toBe(1);
    expect(opened[0]).toEqual(jasmine.objectContaining({
      entity: 'appointment', id: 881, action: 'confirm', source: 'TASK_INBOX', row: ROW,
    }));
    expect(opened[0].context?.childId).toBe(5);
    // The list link stays a link.
    expect(el.querySelector('.task__actions a[href="/appointments?focus=881"]')).not.toBeNull();
  });

  it('keeps a plain navigation for a task the drawer does not show', () => {
    const fixture = mount({
      ...base, id: 'REQUEST_DECIDE:3', taskType: 'REQUEST_DECIDE', entityType: 'REQUEST', entityId: 3, row: undefined,
      primaryAction: { labelKey: 'tasks.type.REQUEST_DECIDE.cta', link: ['/requests'], query: { status: 'NEW', focus: '3' } },
    });
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('.task__actions button')).toBeNull();
    expect(el.querySelector('.task__actions a.hbh-btn--primary[href="/requests?status=NEW&focus=3"]')).not.toBeNull();
    expect(opened.length).toBe(0);
  });
});
