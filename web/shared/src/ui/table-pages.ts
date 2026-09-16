import { ChangeDetectionStrategy, Component, computed, input, linkedSignal, signal } from '@angular/core';
import { TranslatePipe } from '../i18n/translate.pipe';

/** Paginates complete, already-loaded collections without mutating their order. */
@Component({
  selector: 'hbh-table-pages',
  imports: [TranslatePipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="controls hbh-table-toolbar"><ng-content select="[tableFilters]" /><label class="ops-page-size"><span>{{ 'table.rowsPerPage' | t }}</span>
      <select [attr.aria-label]="'table.rowsPerPage' | t" [value]="size()" (change)="resize($any($event.target).value)">
        @for (n of [10,20,30,50]; track n) { <option [value]="n">{{n}}</option> }
      </select></label><span>{{ 'table.total' | t }}: {{ rows().length }}</span></div>
    <div class="hbh-table-scroll"><ng-content /></div>
    <nav class="controls hbh-table-pagination" [attr.aria-label]="'table.page' | t">
      <button type="button" (click)="move(-1)" [disabled]="current() <= 1">{{ 'table.previous' | t }}</button>
      <span aria-live="polite">{{ 'table.page' | t }} {{current()}} {{ 'table.of' | t }} {{pages()}}</span>
      <button type="button" (click)="move(1)" [disabled]="current() >= pages()">{{ 'table.next' | t }}</button>
    </nav>`,
  styles: `:host{display:block;min-width:0}.controls{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;padding:12px 0;font-size:13px}label{display:flex;align-items:center;gap:10px}button,select{font:inherit;background:white;color:inherit;border:1px solid #d6e6e9;border-radius:10px;padding:9px 14px}button:disabled{opacity:.45}button:focus-visible,select:focus-visible{outline:2px solid #008b99;outline-offset:2px}`,
})
export class TablePages<T> {
  readonly rows = input<readonly T[]>([]);
  readonly size = signal(10);
  private readonly page = linkedSignal({ source: this.rows, computation: () => 1 });
  readonly pages = computed(() => Math.max(1, Math.ceil(this.rows().length / this.size())));
  readonly current = computed(() => Math.min(this.page(), this.pages()));
  readonly visible = computed(() => this.rows().slice((this.current()-1)*this.size(), this.current()*this.size()));
  resize(value: string): void { const size=Number(value); if (![10,20,30,50].includes(size)) return; this.size.set(size); this.page.set(1); }
  move(delta: number): void { this.page.set(Math.max(1, Math.min(this.pages(), this.current()+delta))); }
}
