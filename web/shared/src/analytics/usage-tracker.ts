import { ChangeDetectionStrategy, Component, DestroyRef, Injectable, effect, inject, input } from '@angular/core';
import { HttpBackend, HttpClient, HttpInterceptorFn, HttpResponse } from '@angular/common/http';
import { ActivatedRouteSnapshot, NavigationEnd, Router } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { filter, tap } from 'rxjs';
import { HBH_CONFIG } from '../config/app-config';

/** Route metadata only: never send URLs, query values, names or record IDs. */
export function usageFeature(root: ActivatedRouteSnapshot, app: string): string {
  let route = root;
  while (route.firstChild) route = route.firstChild;
  const title = String(route.data['titleKey'] ?? '');
  if (!title || /^(login|otp|apply)\./.test(title)) return '';
  let suffix = '';
  if (app === 'portal') {
    const tab = route.queryParamMap.get('tab');
    if (title === 'requests.title') suffix = tab === 'messages' ? '.messages' : '.requests';
    if (title === 'nav.progress') suffix = tab === 'notes' ? '.notes' : tab === 'reports' ? '.reports' : '.goals';
  }
  return `${app}.${title}${suffix}`;
}

@Injectable({ providedIn: 'root' })
export class UsageTelemetry {
  private readonly http = new HttpClient(inject(HttpBackend));
  private readonly config = inject(HBH_CONFIG);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  private app = '';
  private token: string | null = null;
  private lastVisit = '';

  constructor() {
    this.router.events.pipe(filter(e => e instanceof NavigationEnd), takeUntilDestroyed())
      .subscribe(() => this.visit());
  }

  configure(app: string, token: string | null): void {
    if (token !== this.token) this.lastVisit = '';
    this.app = app;
    this.token = token;
    if (this.router.navigated) this.visit();
  }

  private visit(): void {
    const feature = usageFeature(this.router.routerState.snapshot.root, this.app);
    if (!this.token || !feature || feature === this.lastVisit) return;
    this.lastVisit = feature;
    this.send(this.token, this.app, feature, 'page', 'view');
  }

  action(method: string): (() => void) | null {
    const token = this.token, app = this.app;
    const feature = usageFeature(this.router.routerState.snapshot.root, app);
    if (!token || app !== 'portal' || !feature) return null;
    return () => { if (this.token === token) this.send(token, app, feature, 'action', method); };
  }

  private send(token: string, app: string, feature: string, kind: string, action: string): void {
    if (this.config.useFixtures) return;
    // Bypass auth/error interceptors: a failed telemetry call cannot sign out
    // the user or change the outcome of their original action. No retries.
    this.http.post(`${this.config.apiBaseUrl}/api/v1/usage-events`, {app, feature, kind, action}, {
      headers: { Authorization: `Bearer ${token}` },
    }).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({ error: () => {} });
  }
}

export const usageInterceptor: HttpInterceptorFn = (req, next) => {
  const config = inject(HBH_CONFIG);
  const base = `${config.apiBaseUrl}/api/v1/`;
  if (!req.url.startsWith(base) || !['POST','PUT','PATCH','DELETE'].includes(req.method) ||
      req.url.startsWith(`${base}auth/`) || req.url.startsWith(`${base}usage-events`)) return next(req);
  const completed = inject(UsageTelemetry).action(req.method);
  return next(req).pipe(tap(event => { if (event instanceof HttpResponse) completed?.(); }));
};

@Component({ selector: 'hbh-usage-tracker', template: '', changeDetection: ChangeDetectionStrategy.OnPush })
export class UsageTracker {
  readonly app = input.required<'ops' | 'portal'>();
  readonly token = input<string | null>(null);
  private readonly telemetry = inject(UsageTelemetry);
  constructor() { effect(() => this.telemetry.configure(this.app(), this.token())); }
}
