import { PortraitCrop } from './portrait-crop';
import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { FormControl, ReactiveFormsModule } from '@angular/forms';
import { forkJoin } from 'rxjs';

import { ModalDialog } from '@hbh/shared/a11y/modal-dialog';
import { FormatService } from '@hbh/shared/format/format.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon, IconName } from '@hbh/shared/icon/icon';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { EmptyState } from '@hbh/shared/ui/empty-state';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';

import { OpsApi, OpsResource, Row } from '../../core/api/ops-api';
import { readRefusal, refusalKey } from '../../core/api/ops-error';
import { OpsAuthService } from '../../core/auth/ops-auth.service';

const text = (row: Row, key: string): string => {
  const value = row[key];
  return value === null || value === undefined ? '' : String(value);
};

const idOf = (row: Row, key: string): number => Number(row[key]);

/**
 * How long a film runs, in whole seconds, or null when it cannot be read.
 *
 * NULL IS A REAL ANSWER HERE and not a failure to handle. A browser that
 * cannot decode the container reports Infinity or NaN, and rounding either
 * of those to a number would put a confident wrong length under a video.
 * ck_stm_duration accepts null so that "not measured" stays distinct from
 * "zero seconds", and the card prints nothing rather than 00:00.
 *
 * The object URL is revoked on every path - it pins the whole file in memory
 * until it is, and these are films.
 */
function videoDuration(file: File, kind: 'VIDEO' | 'PHOTO'): Promise<number | null> {
  if (kind !== 'VIDEO') {
    return Promise.resolve(null);
  }
  return new Promise((resolve) => {
    const url = URL.createObjectURL(file);
    const probe = document.createElement('video');
    const done = (value: number | null) => {
      URL.revokeObjectURL(url);
      resolve(value);
    };
    // A file the browser will not decode never fires either event, so the
    // upload would hang on a promise that never settles.
    const timer = setTimeout(() => done(null), 10_000);
    probe.preload = 'metadata';
    probe.onloadedmetadata = () => {
      clearTimeout(timer);
      const seconds = probe.duration;
      done(Number.isFinite(seconds) && seconds > 0 ? Math.round(seconds) : null);
    };
    probe.onerror = () => {
      clearTimeout(timer);
      done(null);
    };
    probe.src = url;
  });
}

type Tab = 'profile' | 'facts' | 'videos' | 'certificates' | 'photos';
type ListKind = 'facts' | 'certificates';

/** One field of the small editor used for qualifications and certificates. */
interface DetailField {
  readonly name: string;
  readonly labelKey: string;
  readonly kind: 'text' | 'number' | 'date';
  readonly required?: boolean;
  readonly ltr?: boolean;
}

const FACT_FIELDS: readonly DetailField[] = [
  { name: 'text_ar', labelKey: 'site.fact', kind: 'text', required: true },
  { name: 'text_en', labelKey: 'site.factEn', kind: 'text', ltr: true },
  { name: 'sort_order', labelKey: 'site.order', kind: 'number', ltr: true },
];

const CERT_FIELDS: readonly DetailField[] = [
  { name: 'path', labelKey: 'site.certPath', kind: 'text', ltr: true, required: true },
  { name: 'caption_ar', labelKey: 'site.certCaption', kind: 'text' },
  { name: 'caption_en', labelKey: 'site.certCaptionEn', kind: 'text', ltr: true },
  { name: 'consent_given_at', labelKey: 'site.certConsent', kind: 'date', ltr: true },
  { name: 'redaction_checked_at', labelKey: 'site.certRedaction', kind: 'date', ltr: true },
  { name: 'sort_order', labelKey: 'site.order', kind: 'number', ltr: true },
];

/** The profile form. Written through one PATCH when the person saves. */
const PROFILE_FIELDS = [
  'name_ar', 'role_ar', 'org_ar', 'bio_ar',
] as const;

const BIO_MAX = 500;

/**
 * The team, as master and detail.
 *
 * It replaced three sibling tabs - members, qualifications, certificates -
 * which were three flat tables of the same people. A qualification means
 * nothing apart from whose it is, so a list of them ordered by member id asks
 * the reader to hold the join in their head, and every edit began by looking
 * up an identifier in another tab.
 *
 * NOTHING HERE IS SAVED AS YOU TYPE. The profile fields are a form with an
 * explicit save and a cancel beside it, because a name and a biography are
 * edited in passes - half a sentence is not a state anybody wants published,
 * and an autosaving field would put one there.
 *
 * The media and the specialities are the exception, and deliberately: adding
 * a film is one act, and asking somebody to press save afterwards is how a
 * file ends up uploaded and unreferenced.
 *
 * WHAT THE FILMS ARE, AND ARE NOT. A member of staff introducing themselves,
 * for the public page. The project's permanent rule - the centre streams a
 * session live and never records it - is untouched: hbh.site_team_media hangs
 * off site_team, which has no child, no session, no appointment and no
 * camera, and the conventions suite refuses to let it grow one while it holds
 * the NO_RECORDING exemption registered in migration 0057. The guarantee is
 * the shape of the table, not this paragraph.
 *
 * EVERY FILE CARRIES ITS OWN CONSENT. The member row's consent covers a name,
 * a portrait and a list of credentials - what was asked for when that row was
 * made. It does not cover a film taken later or a second photograph from a
 * different day, so each file is consented separately and the database
 * refuses to publish one without it. This screen says which gate is open
 * before somebody presses publish rather than after.
 */
@Component({
  selector: 'hbh-team-screen',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [PortraitCrop,
    ReactiveFormsModule, ModalDialog, Icon, TranslatePipe,
    Skeleton, EmptyState, ErrorNote,
  ],
  templateUrl: './team-screen.html',
})
export class TeamScreen {
  private readonly api = inject(OpsApi);
  private readonly destroyRef = inject(DestroyRef);
  private readonly toast = inject(ToastService);
  private readonly i18n = inject(I18nService);
  protected readonly auth = inject(OpsAuthService);
  protected readonly format = inject(FormatService);

  protected readonly members = signal<readonly Row[]>([]);
  protected readonly facts = signal<readonly Row[]>([]);
  protected readonly certificates = signal<readonly Row[]>([]);
  protected readonly media = signal<readonly Row[]>([]);
  protected readonly specialties = signal<readonly Row[]>([]);

  protected readonly loading = signal(true);
  protected readonly failed = signal(false);
  protected readonly busy = signal<string | null>(null);

  protected readonly selectedId = signal<number | null>(null);
  protected readonly tab = signal<Tab>('profile');
  protected readonly listKind = signal<ListKind>('facts');

  /** The profile form, and whether it differs from the stored row. */
  protected readonly profile = signal<Record<string, FormControl<string>>>({});
  protected readonly dirty = signal(false);
  protected readonly savingProfile = signal(false);

  /** The small editor for a qualification or a certificate. */
  protected readonly editing = signal<{ kind: ListKind; row: Row } | null>(null);
  protected readonly saving = signal(false);
  protected readonly formError = signal('');
  protected readonly badField = signal<string | null>(null);
  protected readonly controls = signal<Record<string, FormControl<string>>>({});

  /** Adding a member: a name and a role, which is all the table requires. */
  protected readonly addingMember = signal(false);
  protected readonly newMember = signal<Record<string, FormControl<string>>>({});

  protected readonly specialtyInput = new FormControl('', { nonNullable: true });

  protected readonly canWrite = computed(() => this.auth.can('SITE.EDIT'));
  protected readonly bioMax = BIO_MAX;

  protected readonly selected = computed<Row | null>(() => {
    const id = this.selectedId();
    return id === null
      ? null
      : this.members().find((m) => idOf(m, 'member_id') === id) ?? null;
  });

  private mine(rows: readonly Row[]): readonly Row[] {
    const id = this.selectedId();
    return id === null ? [] : rows.filter((r) => idOf(r, 'member_id') === id);
  }

  protected readonly memberFacts = computed(() => this.mine(this.facts()));
  protected readonly memberCertificates = computed(() => this.mine(this.certificates()));
  protected readonly memberSpecialties = computed(() => this.mine(this.specialties()));
  protected readonly memberVideos = computed(
    () => this.mine(this.media()).filter((m) => text(m, 'kind') === 'VIDEO'));
  protected readonly memberPhotos = computed(
    () => this.mine(this.media()).filter((m) => text(m, 'kind') === 'PHOTO'));

  protected readonly bioLength = computed(() => {
    this.dirty();  // recompute as the field changes
    return this.profile()['bio_ar']?.value.length ?? 0;
  });

  /**
   * What still stands between this member and being published.
   *
   * The database enforces all of it; nothing is decided from these strings.
   * They exist so the answer arrives before somebody presses publish rather
   * than as a refusal afterwards.
   */
  protected readonly blockers = computed<readonly string[]>(() => {
    const member = this.selected();
    if (!member) {
      return [];
    }
    const out: string[] = [];
    if (!text(member, 'consent_given_at')) {
      out.push(this.i18n.translate('team.blocker.consent'));
    }
    const unconsented = this.mine(this.media())
      .filter((m) => !text(m, 'consent_given_at')).length;
    if (unconsented > 0) {
      out.push(this.i18n.plural('team.blocker.media', unconsented));
    }
    return out;
  });

  constructor() {
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    forkJoin({
      members: this.api.list('site-team'),
      facts: this.api.list('site-team-facts'),
      certificates: this.api.list('site-team-certificates'),
      media: this.api.list('site-team-media'),
      specialties: this.api.list('site-team-specialties'),
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (result) => {
          this.members.set(result.members.rows);
          this.facts.set(result.facts.rows);
          this.certificates.set(result.certificates.rows);
          this.media.set(result.media.rows);
          this.specialties.set(result.specialties.rows);

          const open = this.selectedId();
          const stillThere = result.members.rows
            .some((m) => idOf(m, 'member_id') === open);
          if (!stillThere) {
            this.selectedId.set(result.members.rows.length
              ? idOf(result.members.rows[0], 'member_id') : null);
          }
          this.buildProfileForm();
          this.loading.set(false);
        },
        error: () => {
          this.loading.set(false);
          this.failed.set(true);
        },
      });
  }

  protected select(member: Row): void {
    if (this.dirty() && !confirm(this.i18n.translate('team.discardConfirm'))) {
      return;
    }
    this.selectedId.set(idOf(member, 'member_id'));
    this.tab.set('profile');
    this.buildProfileForm();
  }

  protected showTab(tab: Tab): void {
    this.tab.set(tab);
  }

  protected showList(kind: ListKind): void {
    this.listKind.set(kind);
  }

  protected cell(row: Row, column: string): string {
    return text(row, column);
  }

  protected isArchived(row: Row): boolean {
    return row['active_flg'] === false;
  }

  protected statusKey(row: Row): string {
    if (this.isArchived(row)) {
      return 'status.archived';
    }
    return `site.status.${text(row, 'status') || 'DRAFT'}`;
  }

  protected statusTone(row: Row): string {
    if (this.isArchived(row)) {
      return 'hbh-badge--muted';
    }
    return text(row, 'status') === 'PUBLISHED' ? 'hbh-badge--success' : 'hbh-badge--info';
  }

  /**
   * The file name alone, whatever prefix the row carries.
   *
   * The prefix is a parameter (SITE_MEDIA_PREFIX) belonging to the SITE's
   * paths; the service keys media on the name, so hardcoding "assets/" here
   * would break every image the day somebody changed the row.
   */
  protected assetUrl(path: string): string {
    if (!path) {
      return '';
    }
    const name = path.slice(path.lastIndexOf('/') + 1);
    return name ? `/api/v1/site-media/${name}` : '';
  }

  /** mm:ss from seconds, or empty when the length was never measured. */
  protected duration(row: Row): string {
    const raw = text(row, 'duration_s');
    if (!raw) {
      return '';
    }
    const total = Number(raw);
    const mm = Math.floor(total / 60);
    const ss = total % 60;
    return `${String(mm).padStart(2, '0')}:${String(ss).padStart(2, '0')}`;
  }

  // ---- the profile form ----------------------------------------------

  private buildProfileForm(): void {
    const member = this.selected();
    const controls: Record<string, FormControl<string>> = {};
    for (const name of PROFILE_FIELDS) {
      controls[name] = new FormControl(member ? text(member, name) : '',
        { nonNullable: true });
      controls[name].valueChanges
        .pipe(takeUntilDestroyed(this.destroyRef))
        .subscribe(() => this.dirty.set(true));
    }
    this.profile.set(controls);
    this.dirty.set(false);
  }

  protected cancelProfile(): void {
    this.buildProfileForm();
  }

  protected saveProfile(): void {
    const member = this.selected();
    if (!member || this.savingProfile()) {
      return;
    }
    const controls = this.profile();
    const body: Record<string, unknown> = {};
    for (const name of PROFILE_FIELDS) {
      const value = controls[name]?.value.trim() ?? '';
      // Empty clears the column rather than being skipped: on a form with a
      // save button, deleting the text and saving means "remove this".
      body[name] = value === '' ? null : value;
    }
    // The two the table will not accept as null.
    if (!body['name_ar'] || !body['role_ar']) {
      this.toast.error(this.i18n.translate('error.field.REQUIRED'));
      return;
    }

    this.savingProfile.set(true);
    this.api.update('site-team', idOf(member, 'member_id'), body)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.savingProfile.set(false);
          this.dirty.set(false);
          this.toast.show(this.i18n.translate('crud.updated'));
          this.load();
        },
        error: (error: unknown) => {
          this.savingProfile.set(false);
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error))));
        },
      });
  }

  // ---- adding a member -----------------------------------------------

  protected startAddMember(): void {
    const controls: Record<string, FormControl<string>> = {};
    for (const name of ['name_ar', 'role_ar'] as const) {
      controls[name] = new FormControl('', { nonNullable: true });
    }
    this.newMember.set(controls);
    this.formError.set('');
    this.addingMember.set(true);
  }

  protected cancelAddMember(): void {
    this.addingMember.set(false);
  }

  protected saveMember(event?: Event): void {
    event?.preventDefault();
    const controls = this.newMember();
    const name = controls['name_ar']?.value.trim() ?? '';
    const role = controls['role_ar']?.value.trim() ?? '';
    if (!name || !role) {
      this.formError.set('error.field.REQUIRED');
      return;
    }
    this.saving.set(true);
    // No status and no consent: a member is created as a draft, and both
    // the consent and the publish are separate acts with their own gates.
    this.api.create('site-team', { name_ar: name, role_ar: role })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (row) => {
          this.saving.set(false);
          this.addingMember.set(false);
          this.selectedId.set(idOf(row, 'member_id'));
          this.toast.show(this.i18n.translate('crud.created'));
          this.load();
        },
        error: (error: unknown) => {
          this.saving.set(false);
          this.formError.set(refusalKey(readRefusal(error)));
        },
      });
  }

  // ---- specialities ---------------------------------------------------

  protected addSpecialty(event?: Event): void {
    event?.preventDefault();
    const member = this.selected();
    const name = this.specialtyInput.value.trim();
    if (!member || !name) {
      return;
    }
    this.api.create('site-team-specialties', {
      member_id: idOf(member, 'member_id'),
      name_ar: name,
      sort_order: this.memberSpecialties().length * 10,
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.specialtyInput.setValue('');
          this.load();
        },
        error: (error: unknown) =>
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error)))),
      });
  }

  protected removeSpecialty(row: Row): void {
    this.api.archive('site-team-specialties', idOf(row, 'specialty_id'))
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => this.load(),
        error: (error: unknown) =>
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error)))),
      });
  }

  // ---- media -----------------------------------------------------------

  /** The portrait, which lives on the member row and not in the gallery. */
  protected onPickPortrait(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    const member = this.selected();
    if (!file || !member) {
      return;
    }
    this.cropFile.set(file);
  }

  protected readonly cropFile = signal<File | null>(null);
  protected saveCroppedPortrait(file: File): void {
    const member = this.selected();
    if (!member) { return; }
    this.cropFile.set(null);
    this.busy.set('portrait');
    this.api.upload(file).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: (result) => {
        this.api.update('site-team', idOf(member, 'member_id'), { photo_path: result.path })
          .pipe(takeUntilDestroyed(this.destroyRef))
          .subscribe({
            next: () => { this.busy.set(null); this.load(); },
            error: (e: unknown) => this.failUpload(e),
          });
      },
      error: (e: unknown) => this.failUpload(e),
    });
  }

  /** A film or an extra photograph, each its own row with its own consent. */
  protected onPickMedia(event: Event, kind: 'VIDEO' | 'PHOTO'): void {
    const input = event.target as HTMLInputElement;
    const files = Array.from(input.files ?? []);
    input.value = '';
    const member = this.selected();
    if (!files.length || !member) {
      return;
    }
    this.busy.set(kind);
    // One at a time rather than in parallel: the failure of the third of
    // five should not leave a partially built gallery nobody can explain.
    const next = (i: number) => {
      if (i >= files.length) {
        this.busy.set(null);
        this.toast.show(this.i18n.translate('team.uploaded'));
        this.load();
        return;
      }
      const file = files[i];
      // Measured here, from the file the person chose, before it is sent.
      // The site prints it on the thumbnail, and a length shown before the
      // tap is the difference between watching and skipping on a weak
      // connection - which is most of this centre's families on a phone.
      //
      // It is not asked of the service: reading a duration server-side
      // means decoding the container, and the browser has already done it
      // to draw the preview.
      videoDuration(file, kind).then((duration) => {
        this.api.upload(file).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
          next: (result) => {
            const body: Record<string, unknown> = {
              member_id: idOf(member, 'member_id'),
              kind,
              path: result.path,
              sort_order: (this.mine(this.media()).length + i) * 10,
            };
            // Omitted rather than sent as zero when it could not be read.
            // Zero is a length; "not known" is not, and ck_stm_duration
            // accepts a null precisely so the two stay different.
            if (duration !== null) {
              body['duration_s'] = duration;
            }
            this.api.create('site-team-media', body)
              .pipe(takeUntilDestroyed(this.destroyRef))
              .subscribe({ next: () => next(i + 1), error: (e: unknown) => this.failUpload(e) });
          },
          error: (e: unknown) => this.failUpload(e),
        });
      });
    };
    next(0);
  }

  protected removeMedia(row: Row): void {
    // The FILE stays where it is. A hash name is shared by definition - the
    // same photograph uploaded twice is one file - so deleting it could blank
    // another member's card. Reaping unreferenced files is its own job.
    this.api.archive('site-team-media', idOf(row, 'media_id'))
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => { this.toast.show(this.i18n.translate('team.removed')); this.load(); },
        error: (error: unknown) =>
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error)))),
      });
  }

  protected removePortrait(): void {
    const member = this.selected();
    if (!member) {
      return;
    }
    this.api.update('site-team', idOf(member, 'member_id'), { photo_path: null })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => { this.toast.show(this.i18n.translate('team.removed')); this.load(); },
        error: (error: unknown) =>
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error)))),
      });
  }

  /** Records today's consent for one file. The database stamps who. */
  protected consentMedia(row: Row): void {
    const today = new Date().toISOString().slice(0, 10);
    this.api.update('site-team-media', idOf(row, 'media_id'), { consent_given_at: today })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => { this.toast.show(this.i18n.translate('team.consentRecorded')); this.load(); },
        error: (error: unknown) =>
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error)))),
      });
  }

  private failUpload(error: unknown): void {
    this.busy.set(null);
    this.toast.error(this.i18n.translate(refusalKey(readRefusal(error))));
  }

  // ---- the qualification / certificate editor --------------------------

  protected readonly editorFields = computed<readonly DetailField[]>(() => {
    const open = this.editing();
    return !open ? [] : open.kind === 'facts' ? FACT_FIELDS : CERT_FIELDS;
  });

  protected readonly isNewRow = computed(() => {
    const open = this.editing();
    if (!open) {
      return false;
    }
    return open.row[open.kind === 'facts' ? 'fact_id' : 'certificate_id'] === undefined;
  });

  protected startAdd(): void {
    this.openEditor(this.listKind(), {});
  }

  protected startEditRow(row: Row, kind: ListKind): void {
    this.openEditor(kind, row);
  }

  protected cancelEdit(): void {
    this.editing.set(null);
  }

  protected saveRow(event?: Event): void {
    event?.preventDefault();
    const open = this.editing();
    const member = this.selected();
    if (!open || !member || this.saving()) {
      return;
    }

    const controls = this.controls();
    const missing = this.editorFields().find(
      (field) => field.required && !controls[field.name]?.value.trim());
    if (missing) {
      this.formError.set('error.field.REQUIRED');
      this.badField.set(missing.name);
      return;
    }

    const body: Record<string, unknown> = {};
    for (const field of this.editorFields()) {
      const value = controls[field.name]?.value.trim() ?? '';
      if (value === '') {
        continue;
      }
      body[field.name] = field.kind === 'number' ? Number(value) : value;
    }

    const resource: OpsResource = open.kind === 'facts'
      ? 'site-team-facts' : 'site-team-certificates';
    const key = open.kind === 'facts' ? 'fact_id' : 'certificate_id';
    const id = open.row[key] as number | undefined;

    // Only on create: the service refuses member_id on UPDATE, so a
    // qualification cannot change hands, and it never comes from a text box.
    if (id === undefined) {
      body['member_id'] = idOf(member, 'member_id');
    }

    this.saving.set(true);
    this.formError.set('');
    this.badField.set(null);

    const call = id === undefined
      ? this.api.create(resource, body)
      : this.api.update(resource, id, body);

    call.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: () => {
        this.saving.set(false);
        this.editing.set(null);
        this.toast.show(this.i18n.translate(id === undefined ? 'crud.created' : 'crud.updated'));
        this.load();
      },
      error: (error: unknown) => {
        this.saving.set(false);
        const refusal = readRefusal(error);
        this.formError.set(refusalKey(refusal));
        this.badField.set(refusal.field);
      },
    });
  }

  protected archiveRow(row: Row, kind: ListKind): void {
    const resource: OpsResource = kind === 'facts'
      ? 'site-team-facts' : 'site-team-certificates';
    const id = row[kind === 'facts' ? 'fact_id' : 'certificate_id'] as number;
    this.api.archive(resource, id)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => { this.toast.show(this.i18n.translate('crud.archived')); this.load(); },
        error: (error: unknown) =>
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error)))),
      });
  }

  protected restoreRow(row: Row, kind: ListKind): void {
    const resource: OpsResource = kind === 'facts'
      ? 'site-team-facts' : 'site-team-certificates';
    const id = row[kind === 'facts' ? 'fact_id' : 'certificate_id'] as number;
    this.api.restore(resource, id)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => { this.toast.show(this.i18n.translate('crud.restored')); this.load(); },
        error: (error: unknown) =>
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error)))),
      });
  }

  protected onPickCertificate(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    if (!file) {
      return;
    }
    this.busy.set('scan');
    this.api.upload(file).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: (result) => {
        this.busy.set(null);
        // Into the FORM, not the row: writing it straight to the database
        // would retract the redaction attestation on a record nobody had
        // finished editing.
        this.controls()['path']?.setValue(result.path);
        this.toast.show(this.i18n.translate('team.uploaded'));
      },
      error: (e: unknown) => this.failUpload(e),
    });
  }

  protected icon(name: string): IconName {
    return name as IconName;
  }

  private openEditor(kind: ListKind, row: Row): void {
    const fields = kind === 'facts' ? FACT_FIELDS : CERT_FIELDS;
    const controls: Record<string, FormControl<string>> = {};
    for (const field of fields) {
      const raw = text(row, field.name);
      const value = field.kind === 'date' && raw ? raw.slice(0, 10) : raw;
      controls[field.name] = new FormControl(value, { nonNullable: true });
    }
    this.controls.set(controls);
    this.formError.set('');
    this.badField.set(null);
    this.editing.set({ kind, row });
  }
}
