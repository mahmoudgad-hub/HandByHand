import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Location } from '@angular/common';
import { ActivatedRoute } from '@angular/router';

import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { FormatService } from '@hbh/shared/format/format.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { PortalApi } from '../../core/api/portal-api';
import { loadErrorKey, traceIdFor } from '../../core/api/portal-error';
import { TherapistProfile } from '../../core/models/portal.models';

/**
 * Who the family is booked with.
 *
 * A page ABOUT A NAMED PERSON that goes out to third parties, so almost
 * nothing on it is shown until that person has agreed. `published` is the
 * gate, and it is set only after the therapist records their own consent -
 * an administrator holding every permission in the schema is still refused
 * NOT_YOUR_CONSENT, which is the behaviour that makes the gate mean anything.
 *
 * TWO THINGS THIS SCREEN WITHHOLDS ON ITS OWN:
 *
 *   The biography, the years of practice and the age range sit on the
 *   therapist ROW, and the service currently sends them to a family even
 *   while the profile is a draft - unlike the languages and certificates,
 *   which it correctly withholds. Withheld here too, and reported. This is
 *   the client half; the server half is the one that matters.
 *
 *   The mobile number is never requested and has no field to arrive in. The
 *   service already masks it for a guardian, so this is the second wall.
 *
 * A certificate whose scan exists but is not published says so, rather than
 * showing nothing: a family that cannot tell "no scan" from "a scan not for
 * you" rings the centre asking for what they will not be given.
 */
@Component({
  selector: 'hbh-therapist',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [Icon, TranslatePipe, Skeleton, ErrorNote],
  templateUrl: './therapist.html',
})
export class Therapist {
  private readonly api = inject(PortalApi);
  private readonly route = inject(ActivatedRoute);
  private readonly location = inject(Location);
  private readonly destroyRef = inject(DestroyRef);
  private readonly i18n = inject(I18nService);
  protected readonly format = inject(FormatService);

  protected readonly therapist = signal<TherapistProfile | null>(null);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);
  protected readonly failureKey = signal('error.load');
  protected readonly traceId = signal<string | null>(null);

  /**
   * The short facts under the biography: how long they have practised, and
   * the ages they work with.
   *
   * Built as a list so an absent one leaves no empty box. A centre that has
   * filled in the years and not the age range should show one fact, not one
   * fact and a gap.
   */
  protected readonly facts = computed(() => {
    const person = this.therapist();
    if (!person) {
      return [];
    }
    const out: { labelKey: string; value: string }[] = [];
    if (person.yearsOfPractice !== null) {
      out.push({
        labelKey: 'therapist.experience',
        value: this.i18n.plural('therapist.years', person.yearsOfPractice),
      });
    }
    if (person.ageFromMonths !== null && person.ageToMonths !== null) {
      // Months in the schema, years on the screen: a parent thinks in years,
      // and "24 - 108 months" is arithmetic nobody should be asked to do.
      out.push({
        labelKey: 'therapist.ageRange',
        value: this.i18n.translate('therapist.ageSpan', {
          from: this.format.count(Math.floor(person.ageFromMonths / 12)),
          to: this.format.count(Math.floor(person.ageToMonths / 12)),
        }),
      });
    }
    return out;
  });

  constructor() {
    this.load();
  }

  protected load(): void {
    const id = this.route.snapshot.paramMap.get('therapistId') ?? '';
    this.loading.set(true);
    this.failed.set(false);
    this.api.therapist(id)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (profile) => {
          this.therapist.set(profile);
          this.loading.set(false);
        },
        error: (error: unknown) => {
          this.loading.set(false);
          this.failed.set(true);
          this.failureKey.set(loadErrorKey(error));
          this.traceId.set(traceIdFor(error));
        },
      });
  }

  /**
   * Back to wherever they came from - an appointment on the diary, or the
   * home screen. A fixed destination would strand somebody who arrived from
   * the other one.
   */
  protected back(): void {
    this.location.back();
  }
}
