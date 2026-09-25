import { ChangeDetectionStrategy, Component, DestroyRef, effect, inject, input, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { FormsModule } from '@angular/forms';
import { Subscription } from 'rxjs';
import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { FormatService } from '@hbh/shared/format/format.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { ModalDialog } from '@hbh/shared/a11y/modal-dialog';
import { Icon } from '@hbh/shared/icon/icon';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { ErrorNote } from '@hbh/shared/ui/error-note';

export interface UsageGroup { feature: string; users: number; visits: number; actions?: number }
export interface PerformanceGroup { route: string; method: string; calls: number; p95_ms: number }
export interface AnalyticsSummary {
  time_zone: string; tracking_since: string | null; requests: number; successes: number; errors: number;
  p50_ms: number | null; p95_ms: number | null; registrations: number; applications: number; first_logins: number;
  staff_logins: number; staff_active: number; staff_pages: number; portal_users: number;
  portal_features: UsageGroup[]; pages: UsageGroup[]; performance: PerformanceGroup[];
}
export interface DetailRow { at: string; id: string; name: string; username: string; feature: string; action: string; visits: number; status: number | null; duration_ms: number | null }
export interface Details { total: number; rows: DetailRow[] }
type DetailKind = 'successes' | 'errors' | 'performance' | 'registrations' | 'applications' | 'first_logins' | 'staff_logins' | 'staff_active' | 'staff_pages' | 'portal_features';

export function analyticsToday(timeZone: string, now = new Date()): string {
  const parts = new Intl.DateTimeFormat('en', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(now);
  return ['year', 'month', 'day'].map(key => parts.find(p => p.type === key)?.value).join('-');
}

export function validAnalyticsDates(from: string, to: string): boolean {
  const a = Date.parse(from), b = Date.parse(to);
  return /^\d{4}-\d{2}-\d{2}$/.test(from) && /^\d{4}-\d{2}-\d{2}$/.test(to) &&
    Number.isFinite(a) && Number.isFinite(b) && new Date(a).toISOString().slice(0,10) === from &&
    new Date(b).toISOString().slice(0,10) === to && b >= a && b-a <= 365*86400000;
}

const portalFeatures = ['welcome.title','nav.home','nav.schedule','nav.progress.goals','nav.progress.reports',
  'nav.progress.notes','nav.activities','live.title','consult.title','report.title','billing.title',
  'requests.title.requests','requests.title.messages','therapist.title','notifications.title','nav.profile'];

@Component({
  selector: 'hbh-ops-analytics', changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, TranslatePipe, ModalDialog, Icon, Skeleton, ErrorNote],
  templateUrl: './ops-analytics.html', styleUrl: './ops-analytics.scss',
})
export class OpsAnalytics {
  readonly refresh = input(0);
  private readonly config = inject(HBH_CONFIG);
  private readonly http = inject(HttpClient);
  private readonly i18n = inject(I18nService);
  protected readonly format = inject(FormatService);
  private readonly base = `${this.config.apiBaseUrl}/api/v1/ops/analytics`;
  protected from = analyticsToday(this.config.timeZone);
  protected to = this.from;
  protected readonly applied = signal({ from: this.from, to: this.to });
  protected readonly data = signal<AnalyticsSummary | null>(null);
  protected readonly loading = signal(false);
  protected readonly failed = signal(false);
  protected readonly invalid = signal(false);
  protected readonly selected = signal<{kind: DetailKind; feature: string; title: string} | null>(null);
  protected readonly details = signal<Details>({ total: 0, rows: [] });
  protected readonly detailLoading = signal(false);
  protected readonly detailFailed = signal(false);
  protected readonly offset = signal(0);
  private summaryRequest?: Subscription;
  private detailRequest?: Subscription;

  constructor() {
    effect(() => { this.refresh(); this.load(); });
    inject(DestroyRef).onDestroy(() => { this.summaryRequest?.unsubscribe(); this.detailRequest?.unsubscribe(); });
  }

  protected load(): void {
    this.invalid.set(!validAnalyticsDates(this.from, this.to));
    if (this.invalid()) return;
    this.close();
    this.summaryRequest?.unsubscribe();
    this.loading.set(true); this.failed.set(false);
    const range = {from: this.from, to: this.to};
    this.summaryRequest = this.http.get<AnalyticsSummary>(this.base, {params: range}).subscribe({
      next: data => { this.data.set(data); this.applied.set(range); this.loading.set(false); },
      error: () => { this.failed.set(true); this.loading.set(false); },
    });
  }

  protected today(): void { this.from = this.to = analyticsToday(this.data()?.time_zone ?? this.config.timeZone); this.load(); }
  protected percentage(value: number, total: number): string { return total ? `${(100*value/total).toFixed(1)}%` : '—'; }
  protected portalFeatures(data: AnalyticsSummary): UsageGroup[] {
    const groups = new Map<string, UsageGroup>(portalFeatures.map(key => [`portal.${key}`, {feature:`portal.${key}`,users:0,visits:0,actions:0}]));
    data.portal_features.forEach(row => groups.set(row.feature,row));
    return [...groups.values()].sort((a,b)=>b.users-a.users);
  }
  protected ring(value: number, total: number, color: string): string {
    return `conic-gradient(${color} ${total ? 360*value/total : 0}deg, #e8eff1 0deg)`;
  }
  protected width(value: number, rows: readonly UsageGroup[]): number { return 100*value/Math.max(1,...rows.map(r=>r.users)); }
  protected performanceWidth(value: number): number { return 100*value/Math.max(1,...(this.data()?.performance ?? []).map(r=>r.p95_ms)); }
  protected featureName(feature: string): string {
    if (feature.startsWith('ops.')) return this.i18n.translate(feature.slice(4));
    if (feature.startsWith('portal.')) return this.i18n.translate(`analytics.feature.${feature.slice(7)}`);
    return feature;
  }
  protected actionName(action: string): string { return this.i18n.translate(`analytics.action.${action}`); }
  protected at(at: string): string { return `${this.format.dayMonthYear(at)} · ${this.format.time(at)}`; }
  /** Metrics on cards and in tables: Latin digits (#22). */
  protected count(value: number): string { return this.format.number(value); }
  protected open(kind: DetailKind, title: string, feature = ''): void {
    this.selected.set({kind, title: title.startsWith('analytics.') ? this.i18n.translate(title) : title, feature}); this.offset.set(0); this.fetchDetails();
  }
  protected close(): void { this.detailRequest?.unsubscribe(); this.selected.set(null); }
  protected changePage(delta: number): void { this.offset.update(n=>Math.max(0,n+delta*50)); this.fetchDetails(); }
  protected fetchDetails(): void {
    const selected = this.selected(); if (!selected) return;
    this.detailRequest?.unsubscribe(); this.detailLoading.set(true); this.detailFailed.set(false);
    this.details.set({total:0,rows:[]});
    this.detailRequest=this.http.get<Details>(this.base,{params:{...this.applied(),kind:selected.kind,feature:selected.feature,offset:this.offset()}}).subscribe({
      next: details=>{this.details.set(details);this.detailLoading.set(false);},
      error:()=>{this.detailFailed.set(true);this.detailLoading.set(false);},
    });
  }
  protected requestDetails(): boolean { return ['successes','errors','performance'].includes(this.selected()?.kind ?? ''); }
}
