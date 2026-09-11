import { Injectable, signal } from '@angular/core';
export type ToastTone = 'success' | 'error' | 'warning';
export interface ToastMessage { readonly text: string; readonly tone: ToastTone; }
/** Global, explicitly dismissed feedback, emitted only by completed actions. */
@Injectable({ providedIn: 'root' })
export class ToastService {
  private readonly current = signal<ToastMessage | null>(null);
  readonly message = this.current.asReadonly();
  private readonly lastTone = signal<ToastTone>('success');
  readonly tone = this.lastTone.asReadonly();
  show(text: string, _durationMs?: number): void { this.emit({ text, tone: 'success' }); }
  error(text: string, _durationMs?: number): void { this.emit({ text, tone: 'error' }); }
  warning(text: string): void { this.emit({ text, tone: 'warning' }); }
  dismiss(): void { this.current.set(null); }
  private emit(message: ToastMessage): void {
    this.lastTone.set(message.tone);
    this.current.set(message);
  }
}
