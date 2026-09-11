import { ChangeDetectionStrategy, Component } from '@angular/core';

/**
 * The icon sprite, rendered once at the app root. Every <hbh-icon> points at
 * a symbol in here, so an icon costs one <use> and not a copy of the path.
 */
@Component({
  selector: 'hbh-icon-sprite',
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './icon-sprite.html',
  styles: [':host { display: contents; }'],
})
export class IconSprite {}
