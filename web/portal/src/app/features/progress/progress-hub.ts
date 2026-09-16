import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Progress } from './progress';
import { Reports } from '../reports/reports';

@Component({
  selector: 'hbh-progress-hub',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, TranslatePipe, Progress, Reports],
  template: `
    <nav class="seg" [attr.aria-label]="'nav.progress' | t">
      @for (item of tabs; track item.key) {
        <a class="seg__i" [class.is-on]="tab() === item.key" [attr.aria-current]="tab() === item.key ? 'page' : null"
           routerLink="/progress" [queryParams]="{tab: item.key}" queryParamsHandling="merge">{{ item.label | t }}</a>
      }
    </nav>
    @switch (tab()) {
      @case ('reports') { <hbh-reports scope="reports" /> }
      @case ('notes') { <hbh-reports scope="notes" /> }
      @default { <hbh-progress /> }
    }
  `,
})
export class ProgressHub {
  private readonly route = inject(ActivatedRoute);
  private readonly query = toSignal(this.route.queryParamMap, { initialValue: this.route.snapshot.queryParamMap });
  protected readonly tabs = [
    { key: 'progress', label: 'progress.tabGoals' },
    { key: 'reports', label: 'reports.tabReports' },
    { key: 'notes', label: 'reports.tabNotes' },
  ];
  protected tab(): string {
    const tab = this.query().get('tab');
    return tab === 'reports' || tab === 'notes' ? tab : 'progress';
  }
}
