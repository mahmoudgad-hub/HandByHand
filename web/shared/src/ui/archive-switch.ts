import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';
import { TranslatePipe } from '../i18n/translate.pipe';

/** A view filter only: switching it never archives a record. */
@Component({
  selector: 'hbh-archive-switch',
  imports: [TranslatePipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<button type="button" role="switch" [attr.aria-checked]="checked()"
    [disabled]="disabled()" (click)="changed.emit()">
    <span class="track" [class.on]="checked()" aria-hidden="true"><span></span></span>
    <span>{{ 'action.showArchived' | t }}</span>
  </button>`,
  styles: `
    :host{display:inline-flex;vertical-align:middle}
    button{display:inline-flex;align-items:center;gap:12px;min-height:44px;padding:8px 14px;border:1px solid #d4e8e9;border-radius:12px;background:#fff;color:#315c78;font:inherit;font-size:14px;cursor:pointer;white-space:nowrap}
    .track{display:flex;align-items:center;box-sizing:border-box;width:40px;height:24px;padding:3px;border-radius:20px;background:#b4c6cc;transition:background .2s}
    .track span{width:18px;height:18px;flex:none;border-radius:50%;background:#fff;box-shadow:0 1px 3px #0002;transition:transform .2s}
    .track.on{background:#008c9d}.track.on span{transform:translateX(-16px)}
    :host-context([dir=ltr]) .track.on span{transform:translateX(16px)}
    button:focus-visible{outline:3px solid #008c9d;outline-offset:3px}button:disabled{opacity:.55;cursor:wait}
    @media(prefers-reduced-motion:reduce){.track,.track span{transition:none}}
  `,
})
export class ArchiveSwitch {
  readonly checked = input(false);
  readonly disabled = input(false);
  readonly changed = output<void>();
}
