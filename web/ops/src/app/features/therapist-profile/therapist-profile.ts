import { TablePages } from '@hbh/shared/ui/table-pages';
import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute, Router } from '@angular/router';
import { Observable, forkJoin } from 'rxjs';

import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { OpsApi, Row } from '../../core/api/ops-api';
import { readRefusal, refusalKey } from '../../core/api/ops-error';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { TherapistProfileApi } from '../../core/api/therapist-profile-api';

/** The language levels the schema accepts. */
const LEVELS = ['NATIVE', 'FLUENT', 'WORKING', 'BASIC'] as const;

/**
 * Editing a therapist's own profile, and publishing it.
 *
 * This is the screen that makes the profile possible at all: eight write
 * endpoints existed with nothing calling them, so the only way to write a
 * biography was curl.
 *
 * THE CONSENT IS THE CENTRE OF IT. The page goes out to families about a
 * named person, so publishing requires that person's own recorded agreement.
 * The service refuses anybody else with NOT_YOUR_CONSENT - an administrator
 * holding every permission included - so this screen does not offer the
 * consent button to anybody but the therapist themselves. It offers PUBLISH
 * to a manager, because that is a different act.
 *
 * TWO REFUSALS ARE KEPT APART because the service keeps them apart and they
 * send somebody to different places:
 *   CONSENT_REQUIRED - you may publish, but they have not agreed yet
 *   NOT_YOUR_CONSENT - this is not yours to give
 * Collapsing them into "not permitted" would send a manager to ask for a
 * permission that would not have helped.
 */
@Component({
  selector: 'hbh-therapist-profile',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [TablePages, Icon, TranslatePipe, Skeleton, ErrorNote],
  templateUrl: './therapist-profile.html',
})
export class TherapistProfileEditor {
  private readonly api = inject(TherapistProfileApi);
  private readonly crud = inject(OpsApi);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  private readonly toast = inject(ToastService);
  private readonly i18n = inject(I18nService);
  protected readonly auth = inject(OpsAuthService);

  private readonly therapistId = Number(this.route.snapshot.paramMap.get('therapistId'));

  protected readonly person = signal<Row | null>(null);
  protected readonly languages = signal<readonly Row[]>([]);
  protected readonly certificates = signal<readonly Row[]>([]);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);
  protected readonly saving = signal(false);

  // ---- the profile form ----
  protected readonly bio = signal('');
  protected readonly practiceYear = signal('');
  protected readonly ageFrom = signal('');
  protected readonly ageTo = signal('');

  // ---- adding a language ----
  protected readonly levels = LEVELS;
  protected readonly newLang = signal('ar');
  protected readonly newLevel = signal<string>('NATIVE');
  protected readonly newNative = signal(false);
  protected readonly newRuns = signal(true);

  // ---- adding a certificate ----
  protected readonly certTitle = signal('');
  protected readonly certIssuer = signal('');
  protected readonly certYear = signal('');

  protected readonly name = computed(() => String(this.person()?.['full_name_ar'] ?? ''));
  protected readonly status = computed(
    () => String(this.person()?.['profile_status'] ?? 'DRAFT'));
  protected readonly isPublished = computed(() => this.status() === 'PUBLISHED');
  protected readonly hasConsent = computed(() => !!this.person()?.['consent_at']);

  /**
   * Whether the signed-in user IS this therapist.
   *
   * Only they may record the consent. Drawing the button for anybody else
   * would produce a refusal every single time - and worse, would suggest that
   * a manager can agree on a clinician's behalf.
   */
  protected readonly isSelf = computed(() => {
    const userId = this.person()?.['user_id'];
    return userId !== null && userId !== undefined
      && Number(userId) === this.auth.me()?.userId;
  });

  protected readonly canManage = computed(() => this.auth.can('STAFF.MANAGE'));

  constructor() {
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    forkJoin({
      person: this.crud.get('therapists', this.therapistId),
      languages: this.api.languages(this.therapistId),
      certificates: this.api.certificates(this.therapistId),
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.person.set(result.person);
          this.languages.set(result.languages);
          this.certificates.set(result.certificates);
          this.bio.set(String(result.person['bio_ar'] ?? ''));
          this.practiceYear.set(this.text(result.person, 'practice_since_year'));
          this.ageFrom.set(this.text(result.person, 'age_from_mon'));
          this.ageTo.set(this.text(result.person, 'age_to_mon'));
          this.loading.set(false);
        },
        error: () => {
          this.loading.set(false);
          this.failed.set(true);
        },
      });
  }

  protected text(row: Row, key: string): string {
    const value = row[key];
    return value === null || value === undefined ? '' : String(value);
  }

  /**
   * Saves the profile columns.
   *
   * A field the person emptied is sent in `clear`, not as an empty string:
   * absent means "leave it", and the service made that distinction rather
   * than guessing. This screen shows all four, so all four are its to decide.
   */
  protected saveProfile(): void {
    if (this.saving()) {
      return;
    }
    const edit: Record<string, unknown> = {};
    const clear: string[] = [];

    const bio = this.bio().trim();
    if (bio) {
      edit['bio_ar'] = bio;
    } else {
      clear.push('bio_ar');
    }
    for (const [field, value] of [
      ['practice_since_year', this.practiceYear()],
      ['age_from_mon', this.ageFrom()],
      ['age_to_mon', this.ageTo()],
    ] as const) {
      const trimmed = value.trim();
      if (trimmed) {
        edit[field] = Number(trimmed);
      } else {
        clear.push(field);
      }
    }
    if (clear.length) {
      edit['clear'] = clear;
    }

    this.write(this.api.patchProfile(this.therapistId, edit), 'tprofile.saved');
  }

  protected addLanguage(): void {
    const code = this.newLang().trim();
    if (!code || this.saving()) {
      return;
    }
    this.write(
      this.api.putLanguage(
        this.therapistId, code, this.newLevel(), this.newNative(), this.newRuns()),
      'tprofile.languageSaved',
    );
  }

  protected removeLanguage(code: string): void {
    this.write(this.api.removeLanguage(this.therapistId, code), 'tprofile.languageRemoved');
  }

  protected addCertificate(): void {
    const title = this.certTitle().trim();
    if (!title || this.saving()) {
      return;
    }
    const year = this.certYear().trim();
    this.write(
      this.api.addCertificate(this.therapistId, {
        title_ar: title,
        issuer_ar: this.certIssuer().trim() || undefined,
        year_awarded: year ? Number(year) : undefined,
      }),
      'tprofile.certificateAdded',
      () => {
        this.certTitle.set('');
        this.certIssuer.set('');
        this.certYear.set('');
      },
    );
  }

  /**
   * Publishing or withdrawing the SCAN of one certificate.
   *
   * Its own action, never folded into a general save: the scan of an Egyptian
   * certificate usually carries a national identity number, a date of birth
   * and a signature, and somebody correcting a spelling must not publish an
   * identity document as a side effect.
   */
  protected toggleImage(certificate: Row): void {
    const id = Number(certificate['certificate_id']);
    const next = !certificate['is_image_public'];
    this.write(
      this.api.setImagePublic(id, next),
      next ? 'tprofile.imagePublished' : 'tprofile.imageHidden',
    );
  }

  protected giveConsent(): void {
    this.write(this.api.giveConsent(this.therapistId), 'tprofile.consentGiven');
  }

  protected withdrawConsent(): void {
    this.write(this.api.withdrawConsent(this.therapistId), 'tprofile.consentWithdrawn');
  }

  protected publish(): void {
    this.write(this.api.publish(this.therapistId), 'tprofile.published');
  }

  protected back(): void {
    void this.router.navigate(['/therapists']);
  }

  private write(
    // Any of the eight calls. They answer with different bodies - an id, or
    // nothing at all - and none of those bodies is used: the screen reloads
    // from the service rather than patching itself from a response, so the
    // row it shows is the row that exists.
    call: Observable<unknown>,
    doneKey: string, after?: () => void,
  ): void {
    this.saving.set(true);
    call.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: () => {
        this.saving.set(false);
        after?.();
        this.toast.show(this.i18n.translate(doneKey));
        this.load();
      },
      error: (error: unknown) => {
        this.saving.set(false);
        this.toast.error(this.i18n.translate(this.messageFor(error)));
      },
    });
  }

  /**
   * The refusal in this screen's words.
   *
   * The two consent codes are named separately because they send somebody to
   * different places: one is "they have not agreed yet", the other is "this
   * is not yours to give".
   */
  private messageFor(error: unknown): string {
    const status = (error as { status?: number })?.status;
    if (status === 0 || status === undefined) {
      return 'error.connection';
    }
    const code = (error as { error?: { error?: { code?: string } } })?.error?.error?.code;
    // PROFILE_CONSENT_REQUIRED since 2026-09-18: the therapist's own consent
    // to publish, which the service used to answer with the same word as a
    // family's live-view consent. No special case is needed for either now -
    // each code carries its own sentence in the bundle.
    if (code === 'NOT_YOUR_CONSENT') {
      return `error.${code}`;
    }
    return refusalKey(readRefusal(error));
  }
}
