import { ChangeDetectionStrategy, Component, DestroyRef, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { NavigationEnd, Router, RouterLink } from '@angular/router';
import { EMPTY, Observable, expand, filter, finalize, interval, of, reduce, switchMap, take } from 'rxjs';
import { PortalApi } from '../api/portal-api';
import { ChildContextService } from '../auth/child-context.service';
import { NotificationFeed, PortalNotification } from '../models/portal.models';
import { NotificationBadge } from './notification-badge';
import { TabBadge } from '@hbh/shared/a11y/tab-badge';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon, IconName } from '@hbh/shared/icon/icon';
import { FormatService } from '@hbh/shared/format/format.service';

/** Mounted only while authenticated. The initial feed is a baseline, not new mail. */
@Component({
  selector:'hbh-notification-push',changeDetection:ChangeDetectionStrategy.OnPush,
  imports:[RouterLink,Icon,TranslatePipe],
  template:`
    @if (pending().length) {
      <aside class="portal-push" [attr.aria-label]="'push.title' | t">
        <header><p role="status" aria-live="polite"><hbh-icon name="ic-bell" />{{ 'push.title' | t }} <b>{{ pending().length }}</b></p>
          <button type="button" (click)="dismiss()" [attr.aria-label]="'push.dismiss' | t"><hbh-icon name="ic-x" /></button></header>
        <div class="portal-push__items">
          @for (item of pending().slice(0,3);track item.id) {
            <button class="portal-push__item" type="button" [disabled]="opening() !== null" (click)="open(item)">
              <span class="portal-push__icon"><hbh-icon [name]="icon(item)" /></span>
              <span class="portal-push__copy"><strong>{{ item.title }}</strong>
                @if(item.body){<span>{{ item.body }}</span>}
                <small>{{ item.childName }} {{ format.time(item.createdAt) }}</small></span>
              <hbh-icon name="ic-chevron" />
            </button>
          }
        </div>
        @if(error()){<p class="portal-push__error" role="alert">{{ error() | t }}</p>}
        <footer><a routerLink="/notifications" (click)="dismiss()">{{ 'push.all' | t }}</a><button type="button" (click)="dismiss()">{{ 'push.dismiss' | t }}</button></footer>
      </aside>
    }
  `,
  styleUrl:'./notification-push.css',
})
export class NotificationPush {
  private readonly api=inject(PortalApi);
  private readonly router=inject(Router);
  private readonly child=inject(ChildContextService);
  private readonly badge=inject(NotificationBadge);
  private readonly tab=inject(TabBadge);
  private readonly destroy=inject(DestroyRef);
  protected readonly format=inject(FormatService);
  protected readonly pending=signal<readonly PortalNotification[]>([]);
  protected readonly opening=signal<string|null>(null);
  protected readonly error=signal('');
  private latest: number|null=null;
  private loading=false;

  constructor(){
    this.refresh();
    interval(15_000).pipe(takeUntilDestroyed()).subscribe(()=>this.refresh());
    this.router.events.pipe(filter(e=>e instanceof NavigationEnd),takeUntilDestroyed()).subscribe(()=>this.refresh());
    this.destroy.onDestroy(()=>{this.badge.unread.set(null);this.tab.setCount(0);});
  }
  protected refresh():void{
    if(this.loading)return;
    this.loading=true;
    this.api.notifications(100).pipe(
      expand((page,index)=>this.latest!==null && page.rows.length===100 && page.rows.every(r=>Number(r.id)>this.latest!)
        ? this.api.notifications(100,(index+1)*100) : EMPTY),
      reduce((all:NotificationFeed|null,page:NotificationFeed)=>all?{...all,rows:[...all.rows,...page.rows]}:page,null),
      takeUntilDestroyed(this.destroy),finalize(()=>this.loading=false)).subscribe({
      next:feed=>{
        if(!feed)return;
        this.badge.unread.set(feed.unread);
        const newest=Math.max(0,...feed.rows.map(r=>Number(r.id)));
        const fresh=this.latest===null?[]:feed.rows.filter(r=>Number(r.id)>this.latest!&&!r.read);
        const read=new Set(feed.rows.filter(r=>r.read).map(r=>r.id));
        const combined=new Map([...fresh,...this.pending()].filter(r=>!read.has(r.id)).map(r=>[r.id,r]));
        this.pending.set([...combined.values()].sort((a,b)=>(Date.parse(b.createdAt)||0)-(Date.parse(a.createdAt)||0)||Number(b.id)-Number(a.id)));
        this.latest=Math.max(this.latest??0,newest);
        this.tab.setCount(this.pending().length);
      },error:()=>{/* Keep the last known state; a network error is not zero unread. */},
    });
  }
  protected dismiss():void{this.pending.set([]);this.error.set('');this.tab.setCount(0);}
  protected open(item:PortalNotification):void{
    if(this.opening())return;
    this.opening.set(item.id);this.error.set('');
    // Chat and billing may cross children. For child-specific destinations,
    // resolve the authorized family before changing the selected child.
    const family:Observable<{children:readonly import('../models/portal.models').Child[]}|null>=item.childId?this.api.family().pipe(take(1)):of(null);
    family.pipe(switchMap(family=>{
      if(item.childId){
        const target=family?.children.find(c=>c.id===item.childId);
        if(!target){this.error.set('notifications.childUnavailable');return of(false);}
        this.child.select(target);
      }
      const commands=[...(item.target??['/notifications'])],extras={queryParams:item.targetQuery};
      return this.router.navigate(commands,extras).then(opened=>opened||this.router.isActive(this.router.createUrlTree(commands,extras),{paths:'exact',queryParams:'exact',fragment:'ignored',matrixParams:'ignored'}));
    }),takeUntilDestroyed(this.destroy),finalize(()=>this.opening.set(null))).subscribe({
      next:opened=>{
        if(!opened){if(!this.error())this.error.set('notifications.openFailed');return;}
        this.pending.update(rows=>rows.filter(r=>r.id!==item.id));this.tab.setCount(this.pending().length);
        if(!item.read)this.api.markNotificationRead(item.id).subscribe({next:()=>this.refresh(),error:()=>{}});
      },error:()=>this.error.set('notifications.openFailed'),
    });
  }
  protected icon(item:PortalNotification):IconName{
    if(item.kind==='CHAT_MESSAGE'||item.kind==='REQUEST_DECIDED')return 'ic-chat';
    if(item.kind.startsWith('INVOICE')||item.kind.startsWith('PAYMENT'))return 'ic-receipt';
    if(item.kind.startsWith('APPOINTMENT'))return 'ic-calendar';
    if(item.kind==='SESSION_STARTED')return 'ic-cast';
    if(item.kind.includes('PUBLISHED'))return 'ic-file';
    return 'ic-bell';
  }
}
