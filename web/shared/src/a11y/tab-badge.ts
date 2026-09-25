import { Injectable } from '@angular/core';

@Injectable({providedIn:'root'})
export class TabBadge {
  private base = document.title;
  private count = 0;
  private original = '';
  private marked = '';
  setTitle(title:string):void {this.base=title;this.render();}
  setCount(count:number):void {this.count=count;this.render();this.icon();}
  private render():void {document.title=(this.count ? `(${this.count}) ` : '')+this.base;}
  private icon():void {
    const link=document.querySelector<HTMLLinkElement>('link[rel="icon"]');if(!link)return;
    this.original ||= link.href;
    if(!this.count){link.href=this.original;return;}
    if(this.marked){link.href=this.marked;return;}
    const img=new Image();img.onload=()=>{const canvas=document.createElement('canvas');canvas.width=32;canvas.height=32;const ctx=canvas.getContext('2d');if(!ctx)return;ctx.drawImage(img,0,0,32,32);ctx.beginPath();ctx.arc(25,7,6,0,Math.PI*2);ctx.fillStyle='#dc3545';ctx.fill();ctx.strokeStyle='white';ctx.lineWidth=2;ctx.stroke();this.marked=canvas.toDataURL();if(this.count)link.href=this.marked;};img.src=this.original;
  }
}
