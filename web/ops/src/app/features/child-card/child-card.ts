import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { ActivatedRoute, Router } from '@angular/router';
import { NgTemplateOutlet } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { forkJoin } from 'rxjs';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { FormatService } from '@hbh/shared/format/format.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';
import { ChildApi } from '../../core/api/child-api';
import { OpsApi, Row } from '../../core/api/ops-api';
import { OpsAuthService } from '../../core/auth/ops-auth.service';

/** How many cards fill one printed A4 sheet, at ID-1 size. */
const PER_SHEET = 10;

/**
 * A printed identity card for a child, at bank-card size.
 *
 * It leaves the building. The family carries it, it is shown at the door, and
 * it is read by somebody who is worried. Three constraints follow from that,
 * and every one of them is a decision rather than a style:
 *
 *   NO NATIONAL IDENTITY NUMBER AND NO HOME ADDRESS. The card gets lost, and
 *   what is on it belongs to whoever finds it. A child's name, face and home
 *   address on one piece of paper in the street is a question of that child's
 *   safety, not of data protection. The case number identifies them inside
 *   the centre and means nothing outside it.
 *
 *   NO MEDICAL ALERT. Not because it would be useless - because it is the
 *   most dangerous line that could be printed: health data on paper with no
 *   access control, left in a nursery, photographed and forwarded; and it
 *   decays silently, so an allergy written this year is wrong next year and
 *   the paper does not know. The space it would have taken went to a second
 *   telephone number, which is more use in a real emergency.
 *
 *   DARK INK ON WHITE, NEVER A COLOURED FILL. Browsers do not print
 *   background colours by default, so a card designed as white text on teal
 *   comes out of the printer as a blank white sheet - and nobody discovers
 *   that until a hundred cards have been printed.
 *
 * THE TWO NUMBERS ON THE BACK ARE ORDERED BY THE SERVICE, totally:
 * is_primary_flg, then created_at, then guardian_id. A partial order would
 * let the engine choose between equals, and the card would print a different
 * number each time it was run. The first term is guaranteed by a unique index
 * (0032); the other two settle what it does not cover - more than one
 * non-primary guardian.
 */
@Component({
  selector: 'hbh-child-card',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [NgTemplateOutlet, Icon, TranslatePipe, Skeleton, ErrorNote],
  templateUrl: './child-card.html',
  styleUrl: './child-card.css',
})
export class ChildCard {
  private readonly childApi = inject(ChildApi);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly destroyRef = inject(DestroyRef);
  private readonly http = inject(HttpClient);
  private readonly base = `${inject(HBH_CONFIG).apiBaseUrl}/api/v1`;
  protected readonly auth = inject(OpsAuthService);
  protected readonly format = inject(FormatService);

  private readonly childId = Number(this.route.snapshot.paramMap.get('childId'));

  protected readonly child = signal<Row | null>(null);
  protected readonly guardians = signal<readonly Row[]>([]);
  protected readonly plans = signal<readonly Row[]>([]);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);

  /** How many copies a full sheet holds. Repeated for the print preview. */
  protected readonly sheet = Array.from({ length: PER_SHEET });
  protected readonly wholeSheet = signal(false);

  protected readonly name = computed(() => this.text(this.child(), 'full_name_ar'));
  protected readonly girl = computed(() => ['F','FEMALE'].includes(this.text(this.child(), 'gender')));
  /**
   * The child's photograph, fetched as a blob rather than linked.
   *
   * It used to read a `photo_url` column, and an <img> pointed straight at
   * whatever address was in it. That column is gone: an address is a
   * capability that keeps working wherever it is pasted, and the row policy
   * that protects the child's record cannot protect a link once it has left
   * the page.
   *
   * The picture now comes from an authenticated route, which means the
   * browser cannot fetch it by itself - a plain <img src> sends no bearer
   * token and gets a 401. So the request goes through the HTTP client, the
   * interceptor puts the token on it, and the bytes are rendered from a
   * temporary object URL. The server records the read before it answers.
   */
  protected readonly photoFailed = signal(false);
  protected readonly portrait = signal('');
  private portraitObjectUrl: string | null = null;

  private loadPortrait(): void {
    this.http.get(`${this.base}/children/${this.childId}/photo`, { responseType: 'blob' })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (blob) => {
          this.portraitObjectUrl = URL.createObjectURL(blob);
          this.portrait.set(this.portraitObjectUrl);
        },
        // 404 is the ordinary answer for a child with no photograph on
        // record, which is most of them, and for one this caller may not
        // see. The card falls back to its drawn placeholder either way, so
        // neither is worth a message.
        error: () => this.photoFailed.set(true),
      });
  }
  protected readonly childNo = computed(() => this.text(this.child(), 'child_no'));

  /**
   * The birth DATE, not the age.
   *
   * An age printed on a card is wrong within a year and the paper cannot
   * correct itself. The date stays true for as long as the card exists.
   */
  protected readonly birthDate = computed(() => {
    const born = this.text(this.child(), 'birth_date');
    // The day and month and year, without the weekday. Which weekday a child
    // was born on is not a fact anybody reads off an identity card, and on a
    // 54mm card it costs a line that the emergency numbers need.
    return born ? this.format.dayMonthYear(born) : '';
  });

  /**
   * The centre's telephone number - and there ISN'T ONE.
   *
   * hbh.centers has no phone column and GET /me carries none, so nothing in
   * this system knows the number. The first version of this card printed
   * `config.phoneCountryCode` here, which rendered as "+20": a country code
   * standing where a telephone number belongs, on the line that tells a
   * stranger how to return a lost child's card.
   *
   * So the number is omitted and the card says the centre's name only. A card
   * that names the centre can be returned by asking; a card showing "+20"
   * looks like a number, gets dialled, and fails. Requested from the service.
   */
  protected readonly centrePhone = computed(() => '');

  /**
   * The service and the therapist, from the child's ACTIVE plan.
   *
   * Absent rather than guessed when there is no active plan: a card that
   * names a therapist who no longer sees the child sends a worried person to
   * the wrong desk.
   */
  protected readonly careLine = computed(() => {
    const plan = this.plans().find((row) => row['status'] === 'ACTIVE');
    if (!plan) {
      return '';
    }
    const service = this.ref(plan, 'service', 'name_ar');
    const therapist = this.ref(plan, 'therapist', 'full_name_ar');
    return [service, therapist].filter(Boolean).join(' · ');
  });

  /**
   * The two contacts for the back, in the order the service returned them.
   *
   * Two, never more: the card is 54mm tall and a third line would shrink all
   * of them below what somebody reads at arm's length in a hurry.
   */
  protected readonly contacts = computed(() => this.guardians().slice(0, 2));

  protected readonly centreName = computed(() => this.auth.me()?.centerName ?? '');

  constructor() {
    this.load();
    // The object URL holds the child's photograph in this tab's memory for
    // as long as it exists. Released when the screen goes, so a reference to
    // a child's face does not outlive the page that was allowed to show it.
    this.destroyRef.onDestroy(() => {
      if (this.portraitObjectUrl) {
        URL.revokeObjectURL(this.portraitObjectUrl);
        this.portraitObjectUrl = null;
      }
    });
  }

  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    forkJoin({
      child: this.childApi.child(this.childId),
      plans: this.childApi.list(this.childId, 'plans'),
      childGuardians: this.childGuardians(),
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.child.set(result.child);
          this.guardians.set(result.childGuardians);
          this.plans.set(result.plans);
          this.loading.set(false);
          // After the record, not alongside it: a child this caller may not
          // see must fail on the record and never reach a request for their
          // face.
          this.loadPortrait();
        },
        error: () => {
          this.loading.set(false);
          this.failed.set(true);
        },
      });
  }

  /**
   * This child's guardians, in the service's total order.
   *
   * Never the generic guardians list filtered here: that endpoint ignores a
   * child filter and returns the whole centre, so picking from it would print
   * another family's telephone number on a child's emergency card.
   */
  private childGuardians() {
    return this.childApi.guardians(this.childId);
  }

  protected text(row: Row | null, key: string): string {
    const value = row?.[key];
    return value === null || value === undefined ? '' : String(value);
  }

  private ref(row: Row, group: string, key: string): string {
    const nested = row[group] as Record<string, unknown> | undefined | null;
    const value = nested?.[key];
    return value === null || value === undefined ? '' : String(value);
  }

  protected printOne(): void {
    this.wholeSheet.set(false);
    setTimeout(() => window.print());
  }

  protected printSheet(): void {
    this.wholeSheet.set(true);
    setTimeout(() => window.print());
  }

  protected back(): void {
    void this.router.navigate(['/children', this.childId]);
  }
}
