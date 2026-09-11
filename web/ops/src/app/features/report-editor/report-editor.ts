import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormControl, ReactiveFormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';

import { FormatService } from '@hbh/shared/format/format.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { ChildApi } from '../../core/api/child-api';
import { Row } from '../../core/api/ops-api';
import { readRefusal, refusalKey } from '../../core/api/ops-error';
import { OpsAuthService } from '../../core/auth/ops-auth.service';

/**
 * Writing a progress report.
 *
 * A FULL PAGE, not a dialog. A report is prose a clinician writes about a
 * child over a month; a modal that has to be dismissed to look anything up,
 * and that a stray Escape closes, is the wrong container for it.
 *
 * It knows the child from the route. A therapist arriving here came from
 * that child's file, and asking them to pick the child again would be the
 * application forgetting something it was just told.
 *
 * NOTHING HERE DECIDES ANYTHING. Every rule - who may write, whose child,
 * whether a draft may still change, whether there is enough to publish -
 * belongs to the three functions in migration 0088. This screen sends what
 * was typed and renders what the service answered. The permission test
 * below only decides whether to DRAW the buttons; it is usability, and C1
 * is the reminder that it is never the control.
 */
@Component({
  selector: 'hbh-report-editor',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [ReactiveFormsModule, Icon, TranslatePipe, Skeleton, ErrorNote],
  templateUrl: './report-editor.html',
  styleUrl: './report-editor.css',
})
export class ReportEditor {
  private readonly api = inject(ChildApi);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  private readonly toast = inject(ToastService);
  protected readonly format = inject(FormatService);
  protected readonly auth = inject(OpsAuthService);

  /** Set when editing; null when opening a new report. */
  protected readonly reportId = signal<number | null>(
    Number(this.route.snapshot.paramMap.get('reportId')) || null);
  protected readonly childId = Number(this.route.snapshot.paramMap.get('childId')) || 0;

  protected readonly child = signal<Row | null>(null);
  protected readonly status = signal<string>('DRAFT');
  protected readonly reportNo = signal<string>('');
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);
  protected readonly saving = signal(false);
  protected readonly publishing = signal(false);
  protected readonly errorKey = signal('');

  protected readonly title = new FormControl('', { nonNullable: true });
  protected readonly summary = new FormControl('', { nonNullable: true });
  protected readonly from = new FormControl('', { nonNullable: true });
  protected readonly to = new FormControl('', { nonNullable: true });

  /** Shown instead of the form once a report has been published. */
  protected readonly published = computed(() => this.status() === 'PUBLISHED');

  /** Preview mode renders exactly what a family would read. */
  protected readonly preview = signal(false);

  /**
   * What was last saved, so "unsaved changes" is a fact rather than a guess.
   * Compared as one string because the four fields are saved together.
   */
  private saved = '';

  protected readonly dirty = computed(() => {
    this.tick();
    return !this.published() && this.snapshot() !== this.saved;
  });

  /** Bumped on every keystroke so `dirty` recomputes - FormControls are not signals. */
  private readonly tick = signal(0);

  constructor() {
    for (const control of [this.title, this.summary, this.from, this.to]) {
      control.valueChanges
        .pipe(takeUntilDestroyed(this.destroyRef))
        .subscribe(() => this.tick.update((n) => n + 1));
    }

    // The browser's own guard. It is the only thing that can survive a
    // refresh or a closed tab, and losing a half-written clinical report
    // to a stray Ctrl-W is not a small thing.
    window.addEventListener('beforeunload', this.guard);
    this.destroyRef.onDestroy(() => window.removeEventListener('beforeunload', this.guard));

    this.load();
  }

  private readonly guard = (event: BeforeUnloadEvent): void => {
    if (this.dirty()) { event.preventDefault(); }
  };

  private snapshot(): string {
    return JSON.stringify([
      this.title.value.trim(), this.summary.value.trim(),
      this.from.value, this.to.value,
    ]);
  }

  private markSaved(): void {
    this.saved = this.snapshot();
    this.tick.update((n) => n + 1);
  }

  private load(): void {
    this.loading.set(true);
    this.failed.set(false);

    this.api.child(this.childId).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: (row) => this.child.set(row),
      error: () => this.child.set(null),
    });

    const id = this.reportId();
    if (!id) {
      // A new report opens on the month that just ended, which is the
      // period a progress report almost always covers. Still editable.
      const now = new Date();
      const first = new Date(now.getFullYear(), now.getMonth() - 1, 1);
      const last = new Date(now.getFullYear(), now.getMonth(), 0);
      this.from.setValue(this.iso(first));
      this.to.setValue(this.iso(last));
      this.markSaved();
      this.loading.set(false);
      return;
    }

    this.api.report(id).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: (row) => {
        this.title.setValue(String(row['title_ar'] ?? ''));
        this.summary.setValue(String(row['summary_ar'] ?? ''));
        this.from.setValue(String(row['period_start'] ?? '').slice(0, 10));
        this.to.setValue(String(row['period_end'] ?? '').slice(0, 10));
        this.status.set(String(row['status'] ?? 'DRAFT'));
        this.reportNo.set(String(row['report_no'] ?? ''));
        this.markSaved();
        this.loading.set(false);
      },
      error: () => { this.loading.set(false); this.failed.set(true); },
    });
  }

  private iso(d: Date): string {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  protected save(): void {
    if (this.saving() || this.published()) { return; }   // no double submit
    this.saving.set(true);
    this.errorKey.set('');

    const id = this.reportId();
    const done = () => {
      this.saving.set(false);
      this.markSaved();
      this.toast.show('تم حفظ التقرير كمسودّة.');
    };
    // THE FORM IS NEVER CLEARED ON FAILURE. What is on screen is the only
    // copy of what the therapist wrote.
    const fail = (error: unknown) => {
      this.saving.set(false);
      this.errorKey.set(refusalKey(readRefusal(error)));
    };

    if (id) {
      this.api.updateReport(id, {
        title_ar: this.title.value.trim(),
        summary_ar: this.summary.value.trim(),
        period_start: this.from.value,
        period_end: this.to.value,
      }).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({ next: done, error: fail });
      return;
    }

    this.api.createReport({
      child_id: this.childId,
      title_ar: this.title.value.trim(),
      period_start: this.from.value,
      period_end: this.to.value,
      summary_ar: this.summary.value.trim() || null,
    }).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: (created) => {
        this.reportId.set(created.report_id);
        // Swap the address for the saved report's own, so a refresh from
        // here reopens the draft instead of starting a second one.
        void this.router.navigate(
          ['/children', this.childId, 'reports', created.report_id],
          { replaceUrl: true });
        done();
      },
      error: fail,
    });
  }

  protected publish(): void {
    const id = this.reportId();
    if (!id || this.publishing() || this.published()) { return; }
    this.publishing.set(true);
    this.errorKey.set('');
    this.api.publishReport(id).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: () => {
        this.publishing.set(false);
        this.status.set('PUBLISHED');
        this.markSaved();
        this.toast.show('تم نشر التقرير. أصبح ظاهرًا لوليّ الأمر.');
      },
      error: (error: unknown) => {
        this.publishing.set(false);
        this.errorKey.set(refusalKey(readRefusal(error)));
      },
    });
  }

  protected back(): void {
    if (this.dirty() && !confirm('لديك تعديلات لم تُحفَظ. هل تريد الخروج وفقدانها؟')) { return; }
    void this.router.navigate(['/children', this.childId]);
  }

  protected togglePreview(): void { this.preview.update((v) => !v); }

  protected childName(): string {
    return String(this.child()?.['full_name_ar'] ?? '');
  }

  /** Retry for the error note. */
  protected reload(): void { this.load(); }
}
