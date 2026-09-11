import { afterRenderEffect, ChangeDetectionStrategy, Component, computed, ElementRef, inject, viewChild } from '@angular/core';
import { ToastService } from './toast.service';
import { I18nService } from '../i18n/i18n.service';
@Component({
  selector: 'hbh-toast',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <dialog #popup class="feedback" [class.feedback--warning]="toast.tone() !== 'success'" [class.feedback--delete]="deleted()"
      aria-labelledby="feedbackTitle" aria-describedby="feedbackDescription" (cancel)="dismiss()">
      <button class="feedback-close" type="button" [attr.aria-label]="en() ? 'Close' : 'إغلاق'" (click)="dismiss()">×</button>
      <div class="feedback-brand" aria-hidden="true"><img src="assets/brand/hbh-logo-mark.png" alt=""><img src="assets/brand/hbh-logo-wordmark.png" alt=""></div>
      <div class="feedback-symbol" aria-hidden="true"><svg viewBox="0 0 48 48">
        @if (toast.tone() !== 'success') { <path d="M24 13v14m0 7v1"/> }
        @else if (deleted()) { <path d="M12 15h24M19 15V9h10v6M15 15l2 24h14l2-24M21 21v12m6-12v12"/> }
        @else { <path d="m12 25 8 8 17-19"/> }
      </svg></div>
      <h2 id="feedbackTitle">{{ toast.message()?.text }}</h2>
      <p id="feedbackDescription">{{ toast.tone() === 'success' ? (en() ? 'You can continue.' : 'يمكنك المتابعة الآن') : (en() ? 'Review the details and try again.' : 'يرجى مراجعة البيانات قبل المتابعة') }}</p>
      <button class="feedback-ok" type="button" autofocus (click)="dismiss()">{{ en() ? 'OK' : 'حسنًا' }}</button>
    </dialog>
  `,
  styleUrl: './toast.css',
})
export class Toast {
  protected readonly toast = inject(ToastService);
  private readonly i18n = inject(I18nService);
  protected readonly en = computed(() => this.i18n.currentLang() === 'en');
  protected readonly deleted = computed(() => /^(تم الحذف بنجاح|Deleted successfully)/i.test(this.toast.message()?.text ?? ''));
  private readonly popup = viewChild<ElementRef<HTMLDialogElement>>('popup');
  constructor() {
    afterRenderEffect(() => {
      const message = this.toast.message();
      const dialog = this.popup()?.nativeElement;
      if (!dialog) return;
      if (message) {
        if (!dialog.open) dialog.showModal();
        if (!matchMedia('(prefers-reduced-motion: reduce)').matches) {
          dialog.animate([{transform:'translateX(0)'},{transform:'translateX(-6px)'},{transform:'translateX(6px)'},{transform:'translateX(-3px)'},{transform:'translateX(0)'}],{duration:360});
          try { navigator.vibrate?.(60); } catch { /* Haptics are optional. */ }
        }
      } else if (dialog.open) dialog.close();
    });
  }
  protected dismiss(): void { this.toast.dismiss(); this.popup()?.nativeElement.close(); }
}
