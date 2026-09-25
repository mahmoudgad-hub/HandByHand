import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormControl, ReactiveFormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';

import { FormatService } from '@hbh/shared/format/format.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { DateParts } from '@hbh/shared/ui/date-parts';
import { ChildApi } from '../../core/api/child-api';
import { Row } from '../../core/api/ops-api';
import { readRefusal, refusalKey } from '../../core/api/ops-error';
import { AutosaveTimer, autosaveHold } from './report-autosave';
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
  imports: [ReactiveFormsModule, Icon, TranslatePipe, Skeleton, ErrorNote, DateParts],
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
  private readonly i18n = inject(I18nService);

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

  /**
   * The version this editor opened - the report's version, kept exactly
   * as the service sent it and named on every save (migration 0141). A
   * colleague's save in between is refused instead of being overwritten.
   */
  private version: string | null = null;

  /**
   * A colleague saved since this editor opened. Saving is held until the
   * newer text is loaded: the same save would be refused the same way, and
   * a button that fails identically every time teaches people to distrust it.
   */
  protected readonly changed = signal(false);

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

  /**
   * AUTOSAVE (#13): after a 3-second pause in typing, and at most 30 seconds
   * after the first unsaved change. Only an existing draft saves itself, and
   * only while no colleague has saved over it - see report-autosave.ts.
   */
  private readonly autosaveTimer = new AutosaveTimer(() => this.autosave(), 3000, 30000);

  /** When the draft last saved itself - the line under the buttons says so. */
  protected readonly autosavedAt = signal<string | null>(null);

  /** A report never saved: the one hold worth telling the therapist about. */
  protected readonly isNew = computed(() => this.reportId() === null);

  constructor() {
    for (const control of [this.title, this.summary, this.from, this.to]) {
      control.valueChanges
        .pipe(takeUntilDestroyed(this.destroyRef))
        .subscribe(() => {
          this.tick.update((n) => n + 1);
          if (this.holdReason() !== 'NEW') { this.autosaveTimer.poke(); }
        });
    }
    this.destroyRef.onDestroy(() => this.autosaveTimer.cancel());

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

  /**
   * Records what the SERVICE now holds. `sent` is the snapshot taken when
   * the save left: anything typed while it was in flight was not sent, and
   * marking the screen "saved" on arrival would leave that text unsaved
   * with no warning. Autosave made that window a few seconds wide, every
   * few seconds - it was the same defect before, only rarer.
   */
  private markSaved(sent: string = this.snapshot()): void {
    this.saved = sent;
    this.tick.update((n) => n + 1);
  }

  private holdReason() {
    return autosaveHold({
      hasReport: this.reportId() !== null,
      published: this.published(),
      saving: this.saving(),
      publishing: this.publishing(),
      changed: this.changed(),
      dirty: this.dirty(),
    });
  }

  private autosave(): void {
    const hold = this.holdReason();
    if (hold === 'BUSY') { this.autosaveTimer.poke(); return; }   // try after it lands
    if (hold === null) { this.save(true); }
  }

  private load(): void {
    this.autosaveTimer.cancel();
    this.autosavedAt.set(null);
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
        this.version = typeof row['version'] === 'string' ? row['version'] : null;
        this.changed.set(false);
        this.errorKey.set('');
        this.markSaved();
        this.loading.set(false);
      },
      error: () => { this.loading.set(false); this.failed.set(true); },
    });
  }

  private iso(d: Date): string {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  protected save(auto = false): void {
    if (this.saving() || this.published()) { return; }   // no double submit
    this.autosaveTimer.cancel();
    this.saving.set(true);
    this.errorKey.set('');
    const sent = this.snapshot();

    const id = this.reportId();
    const done = (saved: { version: string }) => {
      this.version = saved.version;
      this.saving.set(false);
      this.markSaved(sent);
      if (auto) {
        // No toast: a notice every few seconds while someone writes is noise.
        this.autosavedAt.set(this.format.time(new Date().toISOString()));
      } else {
        this.autosavedAt.set(null);
        this.toast.show('تم حفظ التقرير كمسودّة.');
      }
      // Typed while the save was on its way: that text still needs saving.
      if (this.dirty()) { this.autosaveTimer.poke(); }
    };
    // THE FORM IS NEVER CLEARED ON FAILURE. What is on screen is the only
    // copy of what the therapist wrote - and on REPORT_CHANGED it is the
    // only copy of text the database just declined to write.
    const fail = (error: unknown) => {
      const refusal = readRefusal(error);
      this.saving.set(false);
      this.changed.set(refusal.failure === 'REPORT_CHANGED');
      this.errorKey.set(refusalKey(refusal));
    };

    if (id) {
      this.api.updateReport(id, {
        // Sent even when null: the service refuses a save that names no
        // version, and a stale page must learn that rather than skip it.
        expected_version: this.version,
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
        done(created);
      },
      error: fail,
    });
  }

  protected publish(): void {
    const id = this.reportId();
    if (!id || this.publishing() || this.published()) { return; }
    this.autosaveTimer.cancel();
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

  /**
   * After REPORT_CHANGED: replace the screen with the colleague's version.
   * Asked first, because it discards the only copy of what was typed here.
   */
  protected loadLatest(): void {
    if (!confirm(this.i18n.translate('report.loadLatestConfirm'))) { return; }
    this.load();
  }
}
