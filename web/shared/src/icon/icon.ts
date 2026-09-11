import { ChangeDetectionStrategy, Component, input } from '@angular/core';

/** Every icon id defined in the sprite, so a typo is a build error. */
export type IconName =
  | 'ic-grid' | 'ic-users' | 'ic-user' | 'ic-user-check' | 'ic-user-plus'
  | 'ic-calendar' | 'ic-cal-plus' | 'ic-activity' | 'ic-video' | 'ic-file'
  | 'ic-clipboard' | 'ic-card' | 'ic-receipt' | 'ic-money' | 'ic-chat'
  | 'ic-settings' | 'ic-bell' | 'ic-help' | 'ic-check' | 'ic-check-circle'
  | 'ic-x-circle' | 'ic-x' | 'ic-clock' | 'ic-up' | 'ic-down' | 'ic-warn'
  | 'ic-info' | 'ic-star' | 'ic-arrow' | 'ic-back' | 'ic-chevron'
  | 'ic-chev-down' | 'ic-door' | 'ic-menu' | 'ic-list' | 'ic-home'
  | 'ic-puzzle' | 'ic-shield' | 'ic-cast' | 'ic-plus' | 'ic-search'
  | 'ic-filter' | 'ic-edit' | 'ic-camera' | 'ic-mic' | 'ic-volume'
  | 'ic-maximize' | 'ic-pip' | 'ic-flag' | 'ic-dots' | 'ic-phone'
  | 'ic-target' | 'ic-eye' | 'ic-download' | 'ic-play' | 'ic-refresh'
  | 'ic-pin' | 'ic-printer' | 'ic-send' | 'ic-mail' | 'ic-lock'
  | 'ic-trash' | 'ic-upload' | 'ic-tag' | 'ic-sliders' | 'ic-db'
  | 'ic-globe' | 'ic-grip' | 'ic-eye-off'
  | 'ic-heart' | 'ic-leaf' | 'ic-chart' | 'ic-crown';

/**
 * One icon, drawn from the sprite that the app root renders once.
 *
 * The host is display:contents so the <svg> itself is the flex item. Without
 * that, every `.row .hbh-i { flex:none }` in the design system would apply to
 * the wrapper element instead of the icon, and the icons would squash.
 */
@Component({
  selector: 'hbh-icon',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <svg class="hbh-i" viewBox="0 0 24 24" fill="none" stroke="currentColor"
         stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
         focusable="false">
      <use [attr.href]="'#' + name()"></use>
    </svg>
  `,
  styles: [':host { display: contents; }'],
})
export class Icon {
  readonly name = input.required<IconName>();
}
