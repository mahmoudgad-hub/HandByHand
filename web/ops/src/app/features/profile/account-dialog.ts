import { Component, inject, output } from '@angular/core';
import { Router } from '@angular/router';
import { ModalDialog } from '@hbh/shared/a11y/modal-dialog';
import { Icon } from '@hbh/shared/icon/icon';
import { MyProfile } from './my-profile';

@Component({
  selector: 'hbh-account-dialog',
  imports: [ModalDialog, Icon, MyProfile],
  template: `<dialog hbhModal aria-labelledby="accountDialogTitle" (dismissed)="closed.emit()">
    <header><h2 id="accountDialogTitle">حسابي</h2><button type="button" autofocus aria-label="إغلاق حسابي" (click)="closed.emit()"><hbh-icon name="ic-x" /></button></header>
    <div class="account-dialog-body"><hbh-my-profile /></div>
  </dialog>`,
  styles: [`dialog{box-sizing:border-box;width:min(880px,calc(100vw - 24px));max-width:100%;max-height:calc(100dvh - 24px);padding:0;margin:auto;border:1px solid #d5e8eb;border-radius:22px;background:#f8fcfc;color:#164e65;overflow:hidden;box-shadow:0 24px 80px #073f5933}dialog[open]{display:flex;flex-direction:column}dialog::backdrop{background:#173e5866;backdrop-filter:blur(3px)}header{display:flex;align-items:center;justify-content:space-between;gap:16px;padding:14px 20px;border-bottom:1px solid #dfedef;background:white;flex:none}h2{margin:0;font-size:21px}header button{display:grid;place-items:center;width:44px;height:44px;border:0;border-radius:50%;background:#eaf6f7;color:inherit;cursor:pointer}.account-dialog-body{padding:20px;overflow:auto;overscroll-behavior:contain;min-height:0}button:focus-visible{outline:2px solid #008b9b;outline-offset:2px}@media(max-width:600px){dialog{width:calc(100vw - 16px);max-height:calc(100dvh - 16px);border-radius:18px}.account-dialog-body{padding:12px}header{padding:10px 14px}}`],
})
export class AccountDialog { readonly closed = output<void>(); }

@Component({
 selector:'hbh-account-route', imports:[AccountDialog],
 template:`<hbh-account-dialog (closed)="close()" />`,
})
export class AccountRoute {
 private readonly router = inject(Router);
 protected close(): void { void this.router.navigateByUrl('/dashboard', { replaceUrl:true }); }
}
