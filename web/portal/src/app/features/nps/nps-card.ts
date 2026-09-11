import {
  ChangeDetectionStrategy, Component, DestroyRef, ElementRef, effect, inject, signal, viewChild,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';

import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { DueSurvey, NpsApi } from '../../core/api/nps-api';

/**
 * The satisfaction question, put in front of the parent once they sign in.
 *
 * It draws nothing at all unless the service says there is something to ask,
 * which is almost always. WHEN it is asked is not decided here and must not
 * be: hbh.nps_due reads the survey's own `cooldown_days` and answers with a
 * question or with null. A period counted in the client would be a business
 * rule in the one layer that cannot be audited and can be edited by anybody
 * with the page open.
 *
 * IT IS A DIALOG, NOT A CARD IN THE PAGE. Owner's decision, 2026-09-05. In
 * the page it sat below the child's next session and the invoice that is due,
 * and lost to both. The cost is real and is not pretended away: an unasked-for
 * dialog is an interruption, and this one arrives in front of a family who
 * came to read about their child. What makes it acceptable is that it takes
 * one tap to answer and one to dismiss, and that dismissing it is honoured for
 * a month.
 *
 * DISMISSING IT TELLS THE SERVICE - by the ×, by Escape, by the backdrop, all
 * three. The cooldown starts when something is RECORDED, and closing a window
 * records nothing; a dialog that merely hid itself would be back at the next
 * sign-in, and the one after that, forever.
 */
@Component({
  selector: 'hbh-nps-card',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon, TranslatePipe],
  template: `
    @if (survey(); as due) {
      <!-- The backdrop closes it, and closing it is a dismissal like any
           other. (click) on the backdrop only - not on the card - so a tap
           inside does not fall through and throw the question away
           mid-answer. -->
      <div class="nps-modal" (click)="skip()">
        <div #dialog class="nps" role="dialog" aria-modal="true" aria-labelledby="nps-q"
             tabindex="-1" (click)="$event.stopPropagation()">
        <div class="nps__head">
          <span class="nps__q" id="nps-q">{{ due.question_ar }}</span>
          <button class="nps__x" type="button"
                  [attr.aria-label]="'nps.dismiss' | t" (click)="skip()">
            <hbh-icon name="ic-x" />
          </button>
        </div>

        <!-- Zero to ten, drawn as eleven buttons rather than a slider: a
             slider has to be dragged to a number, and this is a choice. -->
        <div class="nps__scale" dir="ltr">
          @for (value of scores; track value) {
            <button class="nps__s" type="button"
                    [class.is-on]="picked() === value"
                    [disabled]="busy()"
                    (click)="answer(value)">{{ value }}</button>
          }
        </div>
        <div class="nps__ends">
          <span>{{ 'nps.low' | t }}</span>
          <span>{{ 'nps.high' | t }}</span>
        </div>

        @if (picked() !== null) {
          <div class="fld" style="margin-top:12px">
            <label class="fld__l" for="nps-note">
              {{ (due.followup_question_ar || ('nps.commentLabel' | t)) }}
            </label>
            <div class="fld__box">
              <textarea id="nps-note" rows="2" dir="rtl" [value]="comment()"
                        (input)="setComment($any($event.target).value)"></textarea>
            </div>
          </div>
          <button class="hbh-btn hbh-btn--primary hbh-btn--block" type="button"
                  style="margin-top:10px"
                  [class.is-busy]="busy()" [disabled]="busy()" (click)="send()">
            {{ (busy() ? 'action.saving' : 'nps.send') | t }}
          </button>
        }
        </div>
      </div>
    }
  `,
  host: {
    // Escape closes it, and closes it the same way the × does. A dialog
    // that ignores Escape is the one people describe as "stuck".
    '(document:keydown.escape)': 'onEscape()',
  },
})
export class NpsCard {
  private readonly api = inject(NpsApi);
  private readonly destroyRef = inject(DestroyRef);
  private readonly toast = inject(ToastService);
  private readonly i18n = inject(I18nService);

  private readonly dialog = viewChild<ElementRef<HTMLElement>>('dialog');

  protected readonly scores = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

  protected readonly survey = signal<DueSurvey | null>(null);
  protected readonly picked = signal<number | null>(null);
  protected readonly comment = signal('');
  protected readonly busy = signal(false);

  constructor() {
    // Move focus into the dialog the moment it appears. Without this the
    // caret stays where it was on the page underneath: a keyboard user tabs
    // through a screen that is covered by something they cannot see, and a
    // screen reader goes on describing the page behind the question.
    // The dialog itself takes focus rather than a score button, so the first
    // thing read is the question and not the number nought.
    //
    // There is no focus trap beyond this, deliberately. It is a dialog with
    // a close button and an Escape key, and a hand-rolled trap that gets one
    // edge wrong strands people far worse than no trap at all.
    effect(() => this.dialog()?.nativeElement.focus());

    this.api.due()
      .pipe(takeUntilDestroyed(this.destroyRef))
      // A failure here is silence. Nothing on this card is worth interrupting
      // a parent looking at their child's file for.
      .subscribe({
        next: (answer) => this.survey.set(answer.survey),
        error: () => this.survey.set(null),
      });
  }

  protected answer(score: number): void {
    this.picked.set(score);
  }

  protected setComment(value: string): void {
    this.comment.set(value);
  }

  protected send(): void {
    const due = this.survey();
    const score = this.picked();
    if (!due || score === null || this.busy()) {
      return;
    }
    this.busy.set(true);
    this.api.respond(due.survey_id, score, this.comment(), due.context_kind, due.context_id)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.busy.set(false);
          this.survey.set(null);
        },
        // A FAILURE STAYS ON SCREEN. This used to close the dialog either
        // way, on the reasoning that re-asking is worse than losing one
        // answer - and it hid a defect for as long as it existed: every
        // answer was refused 400 by a constraint, and the parent watched
        // the dialog accept a score and a sentence they had typed out, and
        // nothing was written. Losing what somebody wrote WITHOUT SAYING SO
        // is the worst of the three outcomes. The dialog stays, the toast
        // says it did not save, and the × is still there for anybody who
        // would rather not try again.
        error: () => {
          this.busy.set(false);
          this.toast.error(this.i18n.translate('nps.failed'));
        },
      });
  }

  /** Escape, only while something is actually being asked. */
  protected onEscape(): void {
    if (this.survey()) {
      this.skip();
    }
  }

  protected skip(): void {
    const due = this.survey();
    if (!due) {
      return;
    }
    this.survey.set(null);
    this.api.skip(due.survey_id)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({ next: () => undefined, error: () => undefined });
  }
}
