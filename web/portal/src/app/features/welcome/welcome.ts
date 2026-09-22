import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  computed,
  inject,
  signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Router } from '@angular/router';

import { PortalApi } from '../../core/api/portal-api';
import { AuthService } from '../../core/auth/auth.service';
import { ChildContextService } from '../../core/auth/child-context.service';
import { FormatService } from '@hbh/shared/format/format.service';
import { HbhAgePipe } from '@hbh/shared/format/format.pipes';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Child, WelcomeSummary } from '../../core/models/portal.models';
import { Icon } from '@hbh/shared/icon/icon';
import { PersonAvatar } from '../../shared/ui/person-avatar';
import { AttendanceView, attendanceView } from './attendance';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';

/**
 * The first screen after sign-in. It has one job: hand the guardian to the
 * right child's file. Everything else on it is a pointer, capped at what fits
 * in a glance, so this does not quietly become a second dashboard.
 *
 * Choosing a child here is not permission to see them. The server re-checks
 * the guardian's link on every request the next screen makes.
 */
@Component({
  selector: 'hbh-welcome',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon, PersonAvatar, TranslatePipe, HbhAgePipe, Skeleton, EmptyState, ErrorNote],
  templateUrl: './welcome.html',
  styleUrl: './welcome.css',
})
export class Welcome {
  private readonly api = inject(PortalApi);
  private readonly auth = inject(AuthService);
  private readonly childContext = inject(ChildContextService);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  private readonly i18n = inject(I18nService);

  /** The ring, or null - in which case the card draws no ring at all. */
  protected attendance(child: Child): AttendanceView | null {
    return attendanceView(child.attendanceMonth);
  }

  protected readonly format = inject(FormatService);

  protected readonly data = signal<WelcomeSummary | null>(null);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);

  protected readonly today = new Date().toISOString();
  protected readonly greetingKey = computed(
    () => `welcome.greeting.${this.format.partOfDay()}`);

  constructor() {
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    this.api.welcome().pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: (summary) => {
        this.data.set(summary);
        this.loading.set(false);
      },
      error: () => {
        this.loading.set(false);
        this.failed.set(true);
      },
    });
  }

  /** Service names joined with the language's own separator. */
  protected serviceList(child: Child): string {
    return this.i18n.list(child.services);
  }

  /** "الجلسة القادمة ٧ سبتمبر — 11:00 ص", assembled in the bundle. */
  protected nextSessionLabel(child: Child): string {
    const next = child.nextAppointment;
    if (!next) {
      return this.i18n.translate('welcome.noNextSession');
    }
    return this.i18n.translate('welcome.nextSessionAt', {
      date: this.format.shortDate(next.startsAt),
      time: this.format.time(next.startsAt),
    });
  }

  protected open(child: Child): void {
    this.childContext.select(child);
    void this.router.navigate(['/home']);
  }

  protected signOut(): void {
    this.childContext.clear();
    this.auth.signOut();
  }

}
