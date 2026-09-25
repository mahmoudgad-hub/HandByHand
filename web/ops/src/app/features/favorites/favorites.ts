import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Icon } from '@hbh/shared/icon/icon';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { FavoritesService } from '../../core/favorites/favorites.service';

@Component({
  selector: 'hbh-favorites',
  imports: [RouterLink, Icon, TranslatePipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <header class="hbh-pagehead">
      <div class="hbh-pagehead__left"><div>
        <h1 class="hbh-pagehead__title">{{ 'nav.favorites' | t }}</h1>
        <p class="hbh-pagehead__sub">{{ 'favorites.sub' | t }}</p>
      </div></div>
      <span class="hbh-badge">{{ favorites.entries().length }}</span>
    </header>
    <div class="favorites-grid">
      @for (entry of favorites.entries(); track entry.key) {
        <article class="favorite-card">
          <a [routerLink]="favorites.pathOf(entry)" [queryParams]="favorites.queryOf(entry)">
            <span class="favorite-icon"><hbh-icon [name]="entry.icon" /></span>
            <strong>{{ entry.labelKey | t }}</strong>
            <span class="favorite-open">{{ 'action.open' | t }} <hbh-icon name="ic-arrow" /></span>
          </a>
          <button class="favorite-remove" type="button" (click)="favorites.toggle(entry.key)"
            [attr.aria-label]="('favorites.remove' | t) + ': ' + (entry.labelKey | t)" [attr.title]="'favorites.remove' | t">
            <hbh-icon name="ic-star" />
          </button>
        </article>
      } @empty {
        <div class="favorites-empty">
          <hbh-icon name="ic-star" />
          <h2>{{ 'favorites.empty' | t }}</h2>
          <p>{{ 'favorites.emptyHint' | t }}</p>
        </div>
      }
    </div>
    <p class="favorites-note">{{ 'favorites.localNote' | t }}</p>
  `,
  styles: [`
    :host{display:block}.favorites-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,260px),1fr));gap:18px}
    .favorite-card{position:relative;background:#fff;border:1px solid #d4e8e9;border-radius:18px;overflow:hidden}
    .favorite-card a{display:flex;flex-direction:column;align-items:flex-start;gap:16px;padding:24px;color:var(--hbh-ink);text-decoration:none;min-height:190px}
    .favorite-card:focus-within,.favorite-card:hover{border-color:#008c9d;box-shadow:0 4px 16px #005c6812}
    .favorite-icon{display:grid;place-items:center;width:46px;height:46px;border-radius:14px;background:#eaf5f5;color:#007d8d}
    .favorite-open{display:flex;align-items:center;gap:8px;color:#007d8d;font-size:14px}
    .favorite-remove{position:absolute;inset-inline-end:14px;top:14px;display:grid;place-items:center;width:44px;height:44px;border:0;border-radius:12px;background:#fff7da;color:#967100;cursor:pointer}
    .favorite-remove ::ng-deep .hbh-i{fill:currentColor}
    .favorites-empty{grid-column:1/-1;padding:64px 24px;text-align:center;background:#fff;border:1px dashed #bad9dc;border-radius:18px;color:#526d7a}
    .favorites-empty h2{font-size:21px}.favorites-note{font-size:13px;color:#526d7a;margin-block:20px}
    button:focus-visible,a:focus-visible{outline:3px solid #008c9d;outline-offset:-3px}
  `],
})
export class Favorites { protected readonly favorites = inject(FavoritesService); }
