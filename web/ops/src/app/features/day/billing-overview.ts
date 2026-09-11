import {Component, inject, signal, DestroyRef} from '@angular/core';
import {HttpClient} from '@angular/common/http';
import {takeUntilDestroyed} from '@angular/core/rxjs-interop';
import {HBH_CONFIG} from '@hbh/shared/config/app-config';
import {FormatService} from '@hbh/shared/format/format.service';
interface Summary {currency:string;invoice_count:number;outstanding:string;overdue:string;average:string;tax:string;collected:string;previous_collected:string}
@Component({selector:'hbh-billing-overview',template: `
<section class="summary"><header><div><h2>الملخص المالي</h2><p>الفواتير الصادرة والمدفوعة · التحصيل من بداية الشهر</p></div><button class="hbh-btn hbh-btn--ghost" type="button" (click)="load()">تحديث الملخص</button></header>
@if (loading()) {<p>جارٍ تحميل الملخص…</p>} @else if(failed()) {<p role="alert">تعذر تحميل الملخص المالي. حاول التحديث.</p>} @else {
@for(row of rows();track row.currency){<h3>{{row.currency}} · {{row.invoice_count}} فاتورة</h3><div class="metrics">
@for(metric of metrics;track metric.key){<article><span>{{metric.label}}</span><strong dir="ltr">{{format.money(+value(row,metric.key),row.currency)}}</strong></article>}
</div><p>تحصيل الشهر السابق كاملًا: {{format.money(+row.previous_collected,row.currency)}} · الشهر الحالي حتى اليوم: {{format.money(+row.collected,row.currency)}}</p>} @empty {<p>لا توجد فواتير صادرة لعرض ملخصها.</p>}}
</section>`,styles:[`.summary{background:#fff;border:1px solid #dcebef;border-radius:18px;padding:20px;margin-bottom:20px}.summary header{display:flex;justify-content:space-between;gap:12px;align-items:center}.summary h2{font-size:18px;margin:0}.summary p{font-size:13px;color:#688492}.summary h3{font-size:14px}.metrics{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:10px}.metrics article{background:#f0f9fa;padding:15px;border-radius:12px}.metrics span{font-size:13px}.metrics strong{display:block;font-size:20px;margin-top:12px}@media(max-width:750px){.metrics{grid-template-columns:repeat(2,minmax(0,1fr))}.summary header{flex-wrap:wrap}}`]})
export class BillingOverview {
 private http=inject(HttpClient);private base=inject(HBH_CONFIG).apiBaseUrl;private destroy=inject(DestroyRef);protected format=inject(FormatService);
 protected rows=signal<Summary[]>([]);protected loading=signal(true);protected failed=signal(false);
 protected metrics=[{key:'collected',label:'المحصّل هذا الشهر'},{key:'outstanding',label:'المبالغ المتبقية'},{key:'overdue',label:'متأخر أكثر من ٣٠ يومًا'},{key:'average',label:'متوسط قيمة الفاتورة'},{key:'tax',label:'إجمالي الضريبة'}];
 protected value(row:Summary,key:string){return row[key as keyof Summary]}
 constructor(){this.load()}
 protected load(){this.loading.set(true);this.failed.set(false);this.http.get<{currencies:Summary[]}>(this.base+'/api/v1/billing/summary').pipe(takeUntilDestroyed(this.destroy)).subscribe({next:r=>{this.rows.set(r.currencies);this.loading.set(false)},error:()=>{this.failed.set(true);this.loading.set(false)}})}
}
