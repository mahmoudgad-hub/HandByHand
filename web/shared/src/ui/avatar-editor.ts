import { Component, DestroyRef, ElementRef, ViewChild, inject, input, output, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ModalDialog } from '../a11y/modal-dialog';
import { HttpErrorResponse } from '@angular/common/http';
import { UserAvatars } from './user-avatar';
import { cropGeometry } from './avatar-crop';

@Component({
  selector: 'hbh-avatar-editor', imports: [ModalDialog],
  template: `<input #fileInput type="file" accept="image/jpeg,image/png,image/webp" hidden (change)="pick($event)">
    <button type="button" class="hbh-btn hbh-btn--ghost" (click)="fileInput.click()" [disabled]="busy()">تغيير الصورة <span aria-hidden="true">＋</span></button>
    @if(error()) {<p role="alert" class="error">{{error()}}</p>}
    @if(done()) {<p role="status">تم حفظ الصورة.</p>}
    @if(source()) {
      <dialog hbhModal (dismissed)="cancel()" aria-labelledby="avatarEditorTitle">
        <header><h2 id="avatarEditorTitle">ضبط الصورة</h2><button type="button" (click)="cancel()" [disabled]="busy()" aria-label="إغلاق">×</button></header>
        <p>كبّر أو صغّر الصورة، واضبط موضعها داخل الدائرة.</p>
        <canvas #preview width="512" height="512" aria-label="معاينة الصورة الدائرية"></canvas>
        <label>الحجم<input type="range" min="1" max="4" step="0.01" [value]="zoom" [disabled]="busy()" (input)="adjust('zoom',$event)"></label>
        <label>يمين / يسار<input type="range" min="0" max="100" [value]="x" [disabled]="busy()" (input)="adjust('x',$event)"></label>
        <label>أعلى / أسفل<input type="range" min="0" max="100" [value]="y" [disabled]="busy()" (input)="adjust('y',$event)"></label>
        @if(error()) {<p role="alert" class="error">{{error()}}</p>}
        <footer><button class="hbh-btn hbh-btn--primary" type="button" (click)="save()" [disabled]="busy()">{{busy()?'جارٍ الحفظ…':'حفظ الصورة'}}</button><button class="hbh-btn hbh-btn--ghost" type="button" (click)="cancel()" [disabled]="busy()">إلغاء</button></footer>
      </dialog>
    }`,
  styles: [`:host{display:block}dialog{box-sizing:border-box;width:min(450px,calc(100vw - 24px));max-height:calc(100dvh - 24px);margin:auto;padding:24px;border:1px solid #dcebed;border-radius:20px;color:#164e65;overflow:auto}dialog::backdrop{background:#073f5973}header,footer{display:flex;align-items:center;justify-content:space-between;gap:12px}h2{margin:0;font-size:21px}header button{border:0;background:#edf7f7;border-radius:50%;width:36px;height:36px;font-size:24px;color:inherit}canvas{display:block;width:min(240px,100%);height:auto;border-radius:50%;margin:18px auto;background:#eef7f7;outline:3px solid #d6e9eb}label{display:flex;flex-direction:column;text-align:start;gap:6px;margin:14px 0}input[type=range]{width:100%;accent-color:#008e9b;direction:ltr}footer{margin-top:20px}p{font-size:14px;line-height:1.7}.error{color:#b33a36}`],
})
export class AvatarEditor {
  readonly userId = input.required<number>();
  readonly saved = output<void>();
  private readonly avatars = inject(UserAvatars);
  private readonly destroy = inject(DestroyRef);
  protected readonly source = signal(false);
  protected readonly busy = signal(false);
  protected readonly error = signal('');
  protected readonly done = signal(false);
  protected zoom = 1; protected x = 50; protected y = 50;
  private picture?: ImageBitmap;
  private selection = 0;
  private canvas?: HTMLCanvasElement;
  // The dialog is created after the image has decoded.
  @ViewChild('preview') set preview(ref: ElementRef<HTMLCanvasElement> | undefined) { this.canvas=ref?.nativeElement; this.draw(); }
  constructor() { this.destroy.onDestroy(() => { this.selection++; this.picture?.close(); }); }
  protected async pick(event: Event) {
    const input = event.target as HTMLInputElement, file = input.files?.[0]; input.value = '';
    if(!file || this.busy()) return;
    this.error.set(''); this.done.set(false);
    if(!['image/jpeg','image/png','image/webp'].includes(file.type) || file.size > 10*1024*1024) { this.error.set('اختر صورة JPG أو PNG أو WebP بحجم أقل من ١٠ ميجابايت.'); return; }
    const version = ++this.selection;
    try {
      const bitmap = await createImageBitmap(file);
      if(version !== this.selection || this.destroy.destroyed) { bitmap.close(); return; }
      this.picture?.close(); this.picture = bitmap;
      this.zoom=1; this.x=50; this.y=50; this.source.set(true);
    } catch { this.error.set('تعذر فتح الصورة. جرّب صورة أخرى.'); }
  }
  protected adjust(key:'zoom'|'x'|'y', event: Event) { this[key]=Number((event.target as HTMLInputElement).value); this.draw(); }
  private draw() {
    if(!this.canvas || !this.picture) return;
    const ctx=this.canvas.getContext('2d'); if(!ctx) return;
    const g=cropGeometry(this.picture.width,this.picture.height,this.zoom,this.x,this.y);
    ctx.fillStyle='#fff';ctx.fillRect(0,0,512,512);
    ctx.drawImage(this.picture,g.sx,g.sy,g.side,g.side,0,0,512,512);
  }
  protected cancel() { if(this.busy()) return; this.selection++; this.source.set(false); this.picture?.close();this.picture=undefined;this.error.set(''); }
  protected save() {
    if(this.busy() || !this.canvas) return;
    this.busy.set(true);this.error.set('');
    this.canvas.toBlob(blob => {
      if(this.destroy.destroyed) return;
      if(!blob) {this.busy.set(false);this.error.set('تعذر تجهيز الصورة.');return;}
      this.avatars.save(this.userId(),blob).pipe(takeUntilDestroyed(this.destroy)).subscribe({
        next:()=>{this.busy.set(false);this.cancel();this.done.set(true);this.saved.emit();},
        error:(error:unknown)=>{this.busy.set(false);this.error.set(avatarSaveError(error));},
      });
    },'image/jpeg',0.9);
  }
}

export function avatarSaveError(error: unknown): string {
  if (!(error instanceof HttpErrorResponse)) return 'تعذر حفظ الصورة. حاول مرة أخرى.';
  if (error.status === 404 || error.status === 405) return 'خدمة حفظ صور الحساب لم تُفعّل على السيرفر بعد. تواصل مع مسؤول النظام.';
  if (error.status === 503) return 'تخزين الصور غير متاح حاليًا على السيرفر. تواصل مع مسؤول النظام.';
  if (error.status === 413) return 'حجم الصورة أكبر من المسموح. اختر صورة أصغر.';
  if (error.status === 401) return 'انتهت الجلسة. سجّل الدخول ثم أعد حفظ الصورة.';
  if (error.status === 403) return 'لا يمكنك تغيير صورة هذا الحساب.';
  if (error.status === 0) return 'تعذر الاتصال بالسيرفر. تحقق من الاتصال ثم حاول مرة أخرى.';
  return 'تعذر حفظ الصورة على السيرفر. حاول مرة أخرى أو تواصل مع مسؤول النظام.';
}
