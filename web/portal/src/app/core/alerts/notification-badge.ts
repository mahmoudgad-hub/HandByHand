import { Injectable, signal } from '@angular/core';

@Injectable({providedIn:'root'})
export class NotificationBadge {
  readonly unread = signal<number | null>(null);
}
