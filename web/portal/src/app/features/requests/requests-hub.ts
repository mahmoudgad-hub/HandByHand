import { ChangeDetectionStrategy, Component, effect, inject, signal } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { FamilyMessages } from '@hbh/shared/ui/family-messages';
import { Requests } from './requests';

/** Family messages have no child context; the route guards only the request tab. */
@Component({
  selector: 'hbh-requests-hub',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, TranslatePipe, FamilyMessages, Requests],
  template: `
    <nav class="seg" [attr.aria-label]="'nav.requests' | t">
      <a class="seg__i" [class.is-on]="!messages()" [attr.aria-current]="!messages() ? 'page' : null"
         routerLink="/requests" [queryParams]="{tab: 'requests'}" queryParamsHandling="merge">{{ 'requests.tabRequests' | t }}</a>
      <a class="seg__i" [class.is-on]="messages()" [attr.aria-current]="messages() ? 'page' : null"
         routerLink="/requests" [queryParams]="{tab: 'messages'}" queryParamsHandling="merge">{{ 'requests.tabMessages' | t }}</a>
    </nav>
    @if (visitedMessages()) { <div [hidden]="!messages()"><hbh-family-messages [guardianPortal]="true" [active]="messages()" /></div> }
    @if (visitedRequests()) { <div [hidden]="messages()"><hbh-requests /></div> }
  `,
})
export class RequestsHub {
  private readonly route = inject(ActivatedRoute);
  private readonly query = toSignal(this.route.queryParamMap, { initialValue: this.route.snapshot.queryParamMap });
  protected readonly visitedMessages = signal(false);
  protected readonly visitedRequests = signal(false);
  constructor() {
    // Retain drafts and in-flight request identifiers when switching tabs.
    effect(() => {
      if (this.messages()) this.visitedMessages.set(true);
      else this.visitedRequests.set(true);
    });
  }
  protected messages(): boolean { return this.query().get('tab') === 'messages'; }
}
