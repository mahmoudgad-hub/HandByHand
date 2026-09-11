import { AfterViewInit, Component, ElementRef, EventEmitter, Input, OnDestroy, Output, ViewChild } from '@angular/core';
import { ModalDialog } from '@hbh/shared/a11y/modal-dialog';
@Component({selector:'hbh-portrait-crop',standalone:true,imports:[ModalDialog],template:`
<dialog class="hbh-sheet" hbhModal (dismissed)="cancel.emit()" aria-labelledby="cropTitle">
<div class="hbh-sheet__box"><div class="hbh-sheet__head"><h2 id="cropTitle" class="hbh-card-title">ضبط صورة العضو</h2><button type="button" class="hbh-iconbtn" aria-label="إغلاق" (click)="cancel.emit()">×</button></div>
<div class="hbh-sheet__body crop-body"><p>حرّك الصورة لتوسيط الوجه، ثم اضبط التكبير.</p>
<canvas #preview width="600" height="600" aria-label="معاينة الصورة الدائرية" (pointerdown)="start($event)" (pointermove)="move($event)" (pointerup)="end()" (pointercancel)="end()"></canvas>
<label>التكبير<input type="range" min="1" max="6" step="0.01" [value]="zoom" (input)="setZoom($event)"></label>
<label>تحريك أفقي<input type="range" min="-100" max="100" [value]="horizontal" (input)="position($event,true)"></label>
<label>تحريك رأسي<input type="range" min="-100" max="100" [value]="vertical" (input)="position($event,false)"></label>
<p role="alert">{{error}}</p></div><div class="hbh-sheet__foot"><button type="button" class="hbh-btn hbh-btn--ghost" (click)="cancel.emit()">إلغاء</button><button type="button" class="hbh-btn hbh-btn--primary" [disabled]="!ready || saving" (click)="save()">اعتماد الصورة</button></div></div></dialog>`,styles:[`
.crop-body{text-align:center}.crop-body canvas{display:block;width:min(280px,100%);aspect-ratio:1;margin:16px auto;border-radius:50%;outline:4px solid #cce9e7;touch-action:none;cursor:grab}.crop-body label{display:flex;align-items:center;gap:12px;margin:14px 0;font-size:14px}.crop-body input{flex:1;min-width:0;accent-color:#008a96}.crop-body p{font-size:14px;line-height:1.7}
`]})
export class PortraitCrop implements AfterViewInit, OnDestroy {
 @Input({required:true}) file!:File;
 @Output() cropped=new EventEmitter<File>(); @Output() cancel=new EventEmitter<void>();
 @ViewChild('preview') canvas!:ElementRef<HTMLCanvasElement>;
 image=new Image();url='';zoom=1;horizontal=0;vertical=0;ready=false;saving=false;error='';
 private drag:{x:number;y:number;h:number;v:number}|null=null;
 ngAfterViewInit(){this.url=URL.createObjectURL(this.file);this.image.onload=()=>{this.ready=true;this.draw();};this.image.onerror=()=>{this.error='تعذّر قراءة الصورة. اختر صورة JPG أو PNG.';};this.image.src=this.url;}
 ngOnDestroy(){this.image.onload=null;this.image.onerror=null;URL.revokeObjectURL(this.url);}
 dimensions(){const s=Math.max(600/this.image.width,600/this.image.height)*this.zoom;return {w:this.image.width*s,h:this.image.height*s};}
 draw(){if(!this.ready)return;const c=this.canvas.nativeElement.getContext('2d')!;const {w,h}=this.dimensions();c.fillStyle='#fff';c.fillRect(0,0,600,600);c.drawImage(this.image,(600-w)/2+this.horizontal/100*(w-600)/2,(600-h)/2+this.vertical/100*(h-600)/2,w,h);}
 setZoom(e:Event){this.zoom=Number((e.target as HTMLInputElement).value);this.draw();}
 position(e:Event,x:boolean){if(x)this.horizontal=Number((e.target as HTMLInputElement).value);else this.vertical=Number((e.target as HTMLInputElement).value);this.draw();}
 start(e:PointerEvent){this.canvas.nativeElement.setPointerCapture(e.pointerId);this.drag={x:e.clientX,y:e.clientY,h:this.horizontal,v:this.vertical};}
 move(e:PointerEvent){if(!this.drag||!this.ready)return;const {w,h}=this.dimensions();const scale=600/this.canvas.nativeElement.getBoundingClientRect().width;this.horizontal=w>600?Math.max(-100,Math.min(100,this.drag.h+(e.clientX-this.drag.x)*scale*200/(w-600))):0;this.vertical=h>600?Math.max(-100,Math.min(100,this.drag.v+(e.clientY-this.drag.y)*scale*200/(h-600))):0;this.draw();}
 end(){this.drag=null;}
 save(){this.saving=true;this.canvas.nativeElement.toBlob(blob=>{if(blob)this.cropped.emit(new File([blob],'portrait-cropped.jpg',{type:'image/jpeg'}));else{this.error='تعذّر حفظ الصورة، حاول مرة أخرى.';this.saving=false;}},'image/jpeg',.92);}
}
