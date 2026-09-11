import {
  ChangeDetectionStrategy, Component, DestroyRef, computed, inject, signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { HttpClient } from '@angular/common/http';
import { FormControl, ReactiveFormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { forkJoin } from 'rxjs';

import { ModalDialog } from '@hbh/shared/a11y/modal-dialog';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { FormatService } from '@hbh/shared/format/format.service';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import { Icon } from '@hbh/shared/icon/icon';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { DateParts } from '@hbh/shared/ui/date-parts';
import { Skeleton } from '@hbh/shared/ui/skeleton';

import { Row } from '../../core/api/ops-api';
import { readRefusal, refusalKey } from '../../core/api/ops-error';
import { OpsAuthService } from '../../core/auth/ops-auth.service';
import { OPS_NAV } from '../../layout/shell/nav';

interface RoleRow {
  readonly code: string;
  readonly name_ar: string;
  readonly is_system: boolean;
  readonly permissions: readonly string[];
}

interface UserRole {
  readonly code: string;
  readonly name_ar: string;
}

interface UserRow {
  readonly user_id: number;
  readonly username: string;
  readonly full_name_ar: string;
  readonly user_type: string;
  readonly status: string;
  readonly active_flg: boolean;
  readonly mobile: string | null;
  readonly roles: readonly UserRole[];
}

/** A list endpoint answers with one named array; this finds it. */
const pickArray = (body: Record<string, unknown>): readonly Row[] => {
  for (const value of Object.values(body ?? {})) {
    if (Array.isArray(value)) {
      return value as readonly Row[];
    }
  }
  return [];
};

type Tab = 'people' | 'roles' | 'screens';

/**
 * Who may open what, and how to change it.
 *
 * THE ROLE IS THE GROUP. Somebody asking for "a group of screens I can hand
 * to a person" is asking for a role, and this system has had them all along:
 * a role holds permissions, a permission opens screens and unlocks actions,
 * and a person holds roles. This screen makes that chain visible in both
 * directions instead of leaving it in five tables nobody can see.
 *
 * IT USED TO SAY THERE WAS NO WAY TO GRANT ANYTHING, and that note was true
 * when it was written and stale by the time anybody read it: hbh.users and
 * hbh.user_roles grew endpoints and this screen went on telling people to
 * ask a developer. A page that reports its own limitations has to be
 * re-read every time the limitation might have moved.
 *
 * WHAT IT STILL CANNOT DO, said plainly rather than left to be discovered:
 * changing WHICH PERMISSIONS A ROLE HOLDS. There is no endpoint for
 * hbh.role_permissions, and it is not an oversight worth routing around from
 * a screen - editing a role changes it for everybody who holds it at once,
 * which is a different act from moving one person between roles and deserves
 * its own decision. Granting and revoking a ROLE is here and works.
 *
 * NOTHING HERE DECIDES ANYTHING. Every list is read from the service, and the
 * service reads it from the same tables the policies consult. The screens
 * come from OPS_NAV - the one constant the shell builds the menu from and the
 * router guards routes with - so this page cannot disagree with the menu
 * about which permission opens which screen. A second copy of the mapping is
 * the thing that would be wrong, silently, on the page people consult to
 * answer exactly that question.
 */
@Component({
  selector: 'hbh-access',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    RouterLink, ReactiveFormsModule, ModalDialog, Icon, TranslatePipe,
    Skeleton, ErrorNote, DateParts,
  ],
  templateUrl: './access.html',
})
export class Access {
  private readonly http = inject(HttpClient);
  private readonly base = `${inject(HBH_CONFIG).apiBaseUrl}/api/v1`;
  private readonly destroyRef = inject(DestroyRef);
  private readonly toast = inject(ToastService);
  private readonly i18n = inject(I18nService);
  protected readonly auth = inject(OpsAuthService);
  private readonly format = inject(FormatService);

  protected readonly tab = signal<Tab>('people');
  protected readonly users = signal<readonly UserRow[]>([]);
  protected readonly roles = signal<readonly RoleRow[]>([]);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);
  protected readonly saving = signal(false);

  protected readonly search = new FormControl('', { nonNullable: true });
  protected readonly searchTerm = signal('');
  protected readonly selectedUserId = signal<number | null>(null);

  /** The roles ticked in the editor, which is not yet what the user holds. */
  protected readonly draftRoles = signal<readonly string[]>([]);

  protected readonly canManage = computed(() => this.auth.can('USER.MANAGE'));

  protected readonly selectedUser = computed<UserRow | null>(() => {
    const id = this.selectedUserId();
    return id === null ? null : this.users().find((u) => u.user_id === id) ?? null;
  });

  /**
   * Matched on the display name, the username and the mobile.
   *
   * "What can Ahmed do?" is the question this screen exists for, and Ahmed is
   * a full_name_ar - not a username somebody would have to know already.
   */
  /**
   * Show everyone, or only the accounts that are not plainly active.
   *
   * "Who is suspended?" was a question this screen could not answer: the
   * standing lived in the detail pane, so it took one click per member of
   * staff and a memory of what each said. That is not a list, it is an
   * interview.
   */
  protected readonly onlyInactive = signal(false);

  protected toggleOnlyInactive(): void {
    this.onlyInactive.update((value) => !value);
  }

  /** Active, and not archived: the ordinary case, which needs no badge. */
  protected isPlainActive(user: UserRow): boolean {
    return user.active_flg && user.status === 'ACTIVE';
  }

  /**
   * What to call this account's standing.
   *
   * Archived wins over the status column, because an archived account is
   * out of the list whatever its status says - showing "active" on a row
   * that is archived would be true about one column and false about the
   * account.
   */
  protected standingKey(user: UserRow): string {
    return user.active_flg ? `access.status.${user.status}` : 'status.archived';
  }

  protected readonly shownUsers = computed(() => {
    const term = this.searchTerm().trim().toLowerCase();
    const rows = this.onlyInactive()
      ? this.users().filter((u) => !this.isPlainActive(u))
      : this.users();
    if (!term) {
      return rows;
    }
    return rows.filter((u) =>
      u.full_name_ar.toLowerCase().includes(term)
      || u.username.toLowerCase().includes(term)
      || (u.mobile ?? '').includes(term));
  });

  /**
   * Everything the ticked roles would give, with no duplicates.
   *
   * Computed from the DRAFT rather than from the stored user, so the effect
   * of ticking a box is visible before it is saved. Two roles overlapping is
   * normal and not worth showing twice.
   */
  protected readonly draftPermissions = computed(() => {
    const byCode = new Map(this.roles().map((r) => [r.code, r]));
    const out = new Set<string>();
    for (const code of this.draftRoles()) {
      for (const perm of byCode.get(code)?.permissions ?? []) {
        out.add(perm);
      }
    }
    return [...out].sort();
  });

  /** The screens those permissions open, named as the menu names them. */
  protected readonly draftScreens = computed(() => {
    const held = new Set(this.draftPermissions());
    return OPS_NAV.filter((entry) => held.has(entry.permission));
  });

  protected readonly dirty = computed(() => {
    const user = this.selectedUser();
    if (!user) {
      return false;
    }
    const now = [...user.roles.map((r) => r.code)].sort().join('|');
    return [...this.draftRoles()].sort().join('|') !== now;
  });

  /**
   * Whether this change would take USER.MANAGE away from the person making
   * it - which would close this screen behind them and leave nobody able to
   * reopen it if they are the only administrator.
   *
   * A warning and not a block: an owner with two administrators has a
   * legitimate reason to demote one of them, and a screen that refuses on a
   * guess is worse than one that says what will happen.
   */
  protected readonly selfLockout = computed(() => {
    const user = this.selectedUser();
    const me = this.auth.me();
    if (!user || !me || user.user_id !== me.userId) {
      return false;
    }
    return !this.draftPermissions().includes('USER.MANAGE');
  });

  /** Every screen in the console, with the permission it needs. */
  protected readonly screens = computed(() => OPS_NAV.map((entry) => ({
    key: entry.key,
    labelKey: entry.labelKey,
    path: entry.path,
    permission: entry.permission,
    held: this.auth.can(entry.permission),
  })));

  protected readonly heldCount = computed(
    () => this.format.count(this.screens().filter((row) => row.held).length));

  protected readonly totalCount = computed(
    () => this.format.count(this.screens().length));

  /**
   * Permissions this account holds that no screen needs.
   *
   * They are not spare: they gate ACTIONS - closing a session, cancelling an
   * appointment, taking a payment - inside screens whose entry permission is
   * something else. Listed so that a manager reading "she has nineteen
   * permissions but ten menu entries" does not conclude that nine are
   * pointless and take them away.
   */
  protected readonly actionOnly = computed(() => {
    const onScreens = new Set(OPS_NAV.map((entry) => entry.permission));
    return (this.auth.me()?.permissions ?? []).filter((code) => !onScreens.has(code));
  });

  constructor() {
    this.search.valueChanges
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe((value) => this.searchTerm.set(value));
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    // Roles first: the user list is useless without the map from a role code
    // to what it actually grants, and a half-loaded screen here would show
    // somebody's access as smaller than it is.
    this.http.get<{ roles?: readonly RoleRow[] }>(`${this.base}/roles`)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (body) => {
          this.roles.set(body.roles ?? []);
          // Every permission the schema defines, not only the ones some
          // role already holds - otherwise a permission nobody has yet
          // could never be granted from this screen.
          this.http.get<{ permissions?: readonly { code: string }[] }>(`${this.base}/permissions`)
            .pipe(takeUntilDestroyed(this.destroyRef))
            .subscribe({
              next: (perms) => {
                this.allPermissions.set((perms.permissions ?? []).map((p) => p.code));
                this.loadUsers();
              },
              error: () => this.loadUsers(),
            });
        },
        error: () => { this.loading.set(false); this.failed.set(true); },
      });
  }

  /**
   * Whether the list includes archived accounts.
   *
   * It has to be reachable, and not as a convenience: the screen offers
   * "archive", the service drops archived accounts from the default list,
   * and without this the account is gone from the only page that could
   * bring it back. Archive with no way to restore is a delete with a
   * gentler word on the button.
   */
  protected readonly showArchived = signal(false);

  protected toggleArchived(): void {
    this.showArchived.update((v) => !v);
    this.loadUsers();
  }

  private loadUsers(): void {
    const query = this.showArchived() ? '?archived=true' : '';
    this.http.get<{ users?: readonly UserRow[] }>(`${this.base}/users${query}`)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (body) => {
          // GET /users needs USER.MANAGE and answers a receptionist with an
          // empty list - correctly. But the personal record admits the
          // OWNER as well as an administrator, and with nothing in the list
          // there was nothing to select, so a person could not reach their
          // own record from the one screen that shows it. The policy said
          // yes and the screen offered no door.
          //
          // So when the list comes back empty, it is filled with the one
          // person this caller can always see: themselves.
          const listed = body.users ?? [];
          const me = this.auth.me();
          this.users.set(listed.length || !me ? listed : [{
            user_id: me.userId,
            username: me.username,
            full_name_ar: me.fullName,
            user_type: me.userType,
            status: 'ACTIVE',
            active_flg: true,
            mobile: null,
            roles: [],
          }]);
          if (this.selectedUserId() === null && this.users().length === 1) {
            this.selectedUserId.set(this.users()[0].user_id);
          }
          if (this.selectedUserId() !== null) {
            this.syncDraft();
          }
          // The personal records, which the policy narrows to what this
          // caller may see: everything with STAFF.PII, otherwise their own
          // row and nothing else. An empty answer is a correct answer here.
          forkJoin({
            profiles: this.http.get<Record<string, unknown>>(`${this.base}/staff-profiles`),
            documents: this.http.get<Record<string, unknown>>(`${this.base}/staff-documents`),
          })
            .pipe(takeUntilDestroyed(this.destroyRef))
            .subscribe({
              next: (extra) => {
                this.profiles.set(pickArray(extra.profiles));
                this.documents.set(pickArray(extra.documents));
                this.buildPiiForm();
                this.loadPhoto();
                this.loading.set(false);
              },
              error: () => {
                this.profiles.set([]);
                this.documents.set([]);
                this.buildPiiForm();
                this.loading.set(false);
              },
            });
        },
        error: () => { this.loading.set(false); this.failed.set(true); },
      });
  }

  protected showTab(tab: Tab): void {
    this.tab.set(tab);
  }

  protected selectUser(user: UserRow): void {
    this.selectedUserId.set(user.user_id);
    this.syncDraft();
    this.buildPiiForm();
    this.loadPhoto();
  }

  private syncDraft(): void {
    this.draftRoles.set((this.selectedUser()?.roles ?? []).map((r) => r.code));
  }

  protected hasRole(code: string): boolean {
    return this.draftRoles().includes(code);
  }

  protected toggleRole(code: string): void {
    this.draftRoles.update((current) =>
      current.includes(code)
        ? current.filter((c) => c !== code)
        : [...current, code]);
  }

  protected cancelRoles(): void {
    this.syncDraft();
  }

  protected saveRoles(): void {
    const user = this.selectedUser();
    if (!user || this.saving()) {
      return;
    }
    this.saving.set(true);
    // The COMPLETE set, always. The endpoint replaces rather than merges, and
    // it refuses a missing key outright - stripping somebody's access because
    // a field was absent is the one mistake it must not make quietly.
    this.http.put(`${this.base}/users/${user.user_id}/roles`,
      { role_codes: [...this.draftRoles()] })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.saving.set(false);
          this.toast.show(this.i18n.translate('access.saved'));
          this.load();
        },
        error: (error: unknown) => {
          this.saving.set(false);
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error))));
        },
      });
  }

  // ---- changing your own password ---------------------------------------

  /**
   * Shown only on your OWN record, because that is the only account this
   * can reach: the service resolves the caller itself and takes no user
   * id, so there is no shape of the request that changes somebody else's.
   *
   * An administrator resetting another person issues a setup code. That is
   * not a limitation worked around here - it is the point.
   */
  protected readonly isMe = computed(() => {
    const user = this.selectedUser();
    const me = this.auth.me();
    return !!user && !!me && user.user_id === me.userId;
  });

  protected readonly pwOpen = signal(false);
  protected readonly pwCurrent = new FormControl('', { nonNullable: true });
  protected readonly pwNext = new FormControl('', { nonNullable: true });
  protected readonly pwBusy = signal(false);
  protected readonly pwError = signal('');
  protected readonly pwDone = signal(false);

  protected togglePasswordForm(): void {
    this.pwOpen.update((v) => !v);
    this.pwError.set('');
    this.pwDone.set(false);
    this.pwCurrent.setValue('');
    this.pwNext.setValue('');
  }

  protected changePassword(): void {
    const current = this.pwCurrent.value;
    const next = this.pwNext.value;
    if (!current || !next) {
      this.pwError.set('error.field.REQUIRED');
      return;
    }
    this.pwBusy.set(true);
    this.pwError.set('');
    this.http.post(`${this.base}/auth/password`,
      { current_password: current, new_password: next })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.pwBusy.set(false);
          this.pwDone.set(true);
          this.pwCurrent.setValue('');
          this.pwNext.setValue('');
        },
        error: (error: unknown) => {
          this.pwBusy.set(false);
          this.pwError.set(refusalKey(readRefusal(error)));
        },
      });
  }

  // ---- the first password ----------------------------------------------

  /**
   * The setup code, held only long enough to be read off the screen.
   *
   * It is shown ONCE and there is no way to fetch it again - not here, not
   * from the service, not from the database, which stores only a hash. An
   * administrator who loses it issues another, and issuing one cancels the
   * last: two live codes for one account means one of them is a spare
   * somebody kept.
   *
   * It is NOT a password. The person redeems it and chooses their own, and
   * nobody else ever learns what they chose - which is the whole reason
   * this screen has no "set password" field.
   */
  protected readonly setupCode = signal<string | null>(null);
  protected readonly issuing = signal(false);

  protected issueSetupCode(): void {
    const user = this.selectedUser();
    if (!user || this.issuing()) {
      return;
    }
    this.issuing.set(true);
    this.setupCode.set(null);
    this.http.post<{ setup_code: string }>(
      `${this.base}/users/${user.user_id}/password-setup`, {})
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (body) => {
          this.issuing.set(false);
          this.setupCode.set(body.setup_code);
        },
        error: (error: unknown) => {
          this.issuing.set(false);
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error))));
        },
      });
  }

  protected dismissSetupCode(): void {
    this.setupCode.set(null);
  }

  // ---- the personal record ---------------------------------------------

  protected readonly profiles = signal<readonly Row[]>([]);
  protected readonly documents = signal<readonly Row[]>([]);
  protected readonly pii = signal<Record<string, FormControl<string>>>({});
  protected readonly piiDirty = signal(false);
  protected readonly uploadingDoc = signal(false);

  /**
   * Whether the personal record is shown at all.
   *
   * STAFF.PII, or it is your own record - the same two ways the policy
   * admits. It decides nothing: the service returns no row to a caller the
   * policy refuses, so a person who got past this would see an empty card
   * rather than somebody's identity number. This only avoids drawing a
   * section that would always be empty.
   */
  protected readonly canSeePii = computed(() => {
    const user = this.selectedUser();
    const me = this.auth.me();
    return !!user && (this.auth.can('STAFF.PII') || user.user_id === me?.userId);
  });

  protected readonly profile = computed<Row | null>(() => {
    const user = this.selectedUser();
    return user
      ? this.profiles().find((p) => Number(p['user_id']) === user.user_id) ?? null
      : null;
  });

  protected readonly userDocuments = computed(() => {
    const user = this.selectedUser();
    return user
      ? this.documents().filter((d) => Number(d['user_id']) === user.user_id)
      : [];
  });

  private buildPiiForm(): void {
    const row = this.profile();
    const controls: Record<string, FormControl<string>> = {};
    for (const name of ['national_id', 'birth_date', 'address_ar'] as const) {
      const raw = row ? String(row[name] ?? '') : '';
      // A date column arrives as an instant; the input wants a day.
      const value = name === 'birth_date' && raw ? raw.slice(0, 10) : raw;
      controls[name] = new FormControl(value, { nonNullable: true });
      controls[name].valueChanges
        .pipe(takeUntilDestroyed(this.destroyRef))
        .subscribe(() => this.piiDirty.set(true));
    }
    this.pii.set(controls);
    this.piiDirty.set(false);
  }

  protected cancelPii(): void {
    this.buildPiiForm();
  }

  protected savePii(): void {
    const user = this.selectedUser();
    if (!user || this.saving()) {
      return;
    }
    const c = this.pii();
    const body: Record<string, unknown> = {};
    for (const name of ['national_id', 'birth_date', 'address_ar'] as const) {
      const value = c[name]?.value.trim() ?? '';
      // Empty clears the column. On a form with a save button, deleting the
      // text and saving means "remove this" - and a national identity
      // number somebody entered by mistake has to be removable.
      body[name] = value === '' ? null : value;
    }

    const existing = this.profile();
    this.saving.set(true);
    const call = existing
      ? this.http.patch(`${this.base}/staff-profiles/${existing['profile_id']}`, body)
      : this.http.post(`${this.base}/staff-profiles`, { ...body, user_id: user.user_id });

    call.pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: () => {
        this.saving.set(false);
        this.piiDirty.set(false);
        this.toast.show(this.i18n.translate('crud.updated'));
        this.load();
      },
      error: (error: unknown) => {
        this.saving.set(false);
        this.toast.error(this.i18n.translate(refusalKey(readRefusal(error))));
      },
    });
  }

  /**
   * Uploads one document against this person.
   *
   * The file and the row are written together by the service, so a refused
   * write leaves no orphaned scan on the disk. Nothing here decides who may
   * do it - the INSERT is subject to the policy.
   */
  protected onPickDocument(event: Event, kind: string): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    const user = this.selectedUser();
    if (!file || !user) {
      return;
    }
    const form = new FormData();
    form.append('file', file);
    form.append('kind', kind);
    this.uploadingDoc.set(true);
    this.http.post(`${this.base}/users/${user.user_id}/documents`, form)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.uploadingDoc.set(false);
          this.toast.show(this.i18n.translate('access.docStored'));
          this.load();
        },
        error: (error: unknown) => {
          this.uploadingDoc.set(false);
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error))));
        },
      });
  }

  protected archiveDocument(doc: Row): void {
    this.http.delete(`${this.base}/staff-documents/${doc['document_id']}`)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.toast.show(this.i18n.translate('crud.archived'));
          this.load();
        },
        error: (error: unknown) =>
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error)))),
      });
  }

  /**
   * Opens a document, by FETCHING it rather than by linking to it.
   *
   * This was a plain <a href> and it could never have worked. The service
   * authenticates with a bearer token in a header; a link followed by the
   * browser sends no headers, so the new tab got a 401 page. Every other
   * authenticated file in this console has the same constraint - it is why
   * the site's public media is a separate, open route and this one is not.
   *
   * So the request goes through the HTTP client, which the interceptor
   * puts the token on, and the blob is opened from a temporary object URL.
   * The read is audited server-side either way.
   */
  protected openDocument(doc: Row): void {
    this.http.get(`${this.base}/staff-documents/${doc['document_id']}/file`,
      { responseType: 'blob' })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (blob) => {
          const url = URL.createObjectURL(blob);
          window.open(url, '_blank', 'noopener');
          // Revoked on a timer, not immediately: the new tab has to have
          // started loading it first. A minute is far longer than that and
          // still bounded - these are personal documents and the reference
          // should not outlive the click.
          setTimeout(() => URL.revokeObjectURL(url), 60_000);
        },
        error: (error: unknown) =>
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error)))),
      });
  }

  /**
   * The photograph, fetched the same way and for the same reason.
   *
   * Held per user so switching between people does not show the previous
   * person's face while the next one loads - which on a screen full of
   * identity numbers would be worse than showing nothing.
   */
  protected readonly photoUrl = signal<string | null>(null);
  private photoObjectUrl: string | null = null;
  protected readonly loadingPhoto = signal(false);

  private loadPhoto(): void {
    this.releasePhoto();
    const user = this.selectedUser();
    if (!user || !this.canSeePii()) {
      return;
    }
    this.loadingPhoto.set(true);
    this.http.get(`${this.base}/users/${user.user_id}/photo`, { responseType: 'blob' })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (blob) => {
          this.loadingPhoto.set(false);
          this.photoObjectUrl = URL.createObjectURL(blob);
          this.photoUrl.set(this.photoObjectUrl);
        },
        // 404 is the ordinary answer for somebody with no photograph, and
        // for somebody whose photograph this caller may not see. Neither is
        // an error worth a message.
        error: () => this.loadingPhoto.set(false),
      });
  }

  private releasePhoto(): void {
    if (this.photoObjectUrl) {
      URL.revokeObjectURL(this.photoObjectUrl);
      this.photoObjectUrl = null;
    }
    this.photoUrl.set(null);
  }

  protected onPickStaffPhoto(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    const user = this.selectedUser();
    if (!file || !user) {
      return;
    }
    const form = new FormData();
    form.append('file', file);
    this.loadingPhoto.set(true);
    this.http.post(`${this.base}/users/${user.user_id}/photo`, form)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.toast.show(this.i18n.translate('access.photoSaved'));
          this.loadPhoto();
        },
        error: (error: unknown) => {
          this.loadingPhoto.set(false);
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error))));
        },
      });
  }

  protected removeStaffPhoto(): void {
    const existing = this.profile();
    if (!existing) {
      return;
    }
    // The FILE stays. Nothing else points at it, but reaping unreferenced
    // files is its own job with its own decision - and a delete that runs
    // from a screen is the one that eventually deletes the wrong thing.
    this.http.patch(`${this.base}/staff-profiles/${existing['profile_id']}`,
      { photo_path: null })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.releasePhoto();
          this.toast.show(this.i18n.translate('team.removed'));
          this.load();
        },
        error: (error: unknown) =>
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error)))),
      });
  }

  protected docKind(doc: Row): string {
    return `access.doc.${String(doc['kind'] ?? 'OTHER')}`;
  }

  /** Reads a column as text. These rows are untyped by design. */
  protected cell(row: Row, column: string): string {
    const value = row[column];
    return value === null || value === undefined ? '' : String(value);
  }

  // ---- opening, suspending and archiving an account --------------------

  protected readonly addingUser = signal(false);
  protected readonly newUser = signal<Record<string, FormControl<string>>>({});
  protected readonly formError = signal('');

  protected startAddUser(): void {
    const controls: Record<string, FormControl<string>> = {
      username: new FormControl('', { nonNullable: true }),
      full_name_ar: new FormControl('', { nonNullable: true }),
      user_type: new FormControl('STAFF', { nonNullable: true }),
      mobile: new FormControl('', { nonNullable: true }),
    };
    this.newUser.set(controls);
    this.formError.set('');
    this.addingUser.set(true);
  }

  protected cancelAddUser(): void {
    this.addingUser.set(false);
  }

  /**
   * Opens an account that cannot yet be signed into.
   *
   * NO PASSWORD FIELD, and its absence is the service's decision rather
   * than an omission here: there is no endpoint that accepts a password
   * for somebody else, on any path. A password typed into a creation
   * screen is a password said out loud and written on paper, and the
   * account it belongs to is one somebody else has seen the key to.
   *
   * So the screen says what it has actually done - the account exists and
   * has no way in yet - instead of leaving a new member of staff waiting
   * for a sign-in that was never going to work.
   */
  protected saveUser(event?: Event): void {
    event?.preventDefault();
    const c = this.newUser();
    const username = c['username']?.value.trim() ?? '';
    const name = c['full_name_ar']?.value.trim() ?? '';
    if (!username || !name) {
      this.formError.set('error.field.REQUIRED');
      return;
    }
    this.saving.set(true);
    this.formError.set('');
    this.http.post<{ user_id: number }>(`${this.base}/users`, {
      username,
      full_name_ar: name,
      user_type: c['user_type']?.value ?? 'STAFF',
      mobile: c['mobile']?.value.trim() ?? '',
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (created) => {
          this.saving.set(false);
          this.addingUser.set(false);
          this.selectedUserId.set(created.user_id);
          this.toast.show(this.i18n.translate('access.userCreated'));
          this.load();
        },
        error: (error: unknown) => {
          this.saving.set(false);
          this.formError.set(refusalKey(readRefusal(error)));
        },
      });
  }

  /**
   * A standing, not a deletion. SUSPENDED keeps the account and its whole
   * history and closes the door; the person comes back by being set ACTIVE
   * again, with nothing to rebuild.
   *
   * The database refuses this on the last administrator - see migration
   * 0066 - because suspending them locks the same door as stripping the
   * role, and the guard was watching only two of the three ways in.
   */
  protected setStatus(user: UserRow, status: string): void {
    this.http.patch(`${this.base}/users/${user.user_id}`, { status })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.toast.show(this.i18n.translate('access.statusChanged'));
          this.load();
        },
        error: (error: unknown) =>
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error)))),
      });
  }

  /** Archive, and its other half. No hard delete exists anywhere here. */
  protected archiveUser(user: UserRow, restore: boolean): void {
    const url = `${this.base}/users/${user.user_id}${restore ? '?restore=true' : ''}`;
    this.http.delete(url)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.toast.show(this.i18n.translate(restore ? 'crud.restored' : 'crud.archived'));
          this.load();
        },
        error: (error: unknown) =>
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error)))),
      });
  }

  // ---- editing what a role may do -------------------------------------

  protected readonly editingRole = signal<string | null>(null);
  protected readonly draftPerms = signal<readonly string[]>([]);
  protected readonly allPermissions = signal<readonly string[]>([]);

  /** How many active people this edit would change at once. */
  protected readonly affected = computed(() => {
    const code = this.editingRole();
    return code === null
      ? 0
      : this.users().filter((u) => u.active_flg && u.roles.some((r) => r.code === code)).length;
  });

  protected readonly roleDirty = computed(() => {
    const code = this.editingRole();
    if (code === null) {
      return false;
    }
    const role = this.roles().find((r) => r.code === code);
    const now = [...(role?.permissions ?? [])].sort().join('|');
    return [...this.draftPerms()].sort().join('|') !== now;
  });

  /**
   * Whether this edit removes the permission that grants permissions from
   * the only role that carries it.
   *
   * The database refuses it - a deferred constraint trigger, at commit -
   * so this is not the guard. It exists so the refusal is not a surprise:
   * the tick box goes red before the save rather than after it.
   */
  protected readonly wouldLockOut = computed(() => {
    const code = this.editingRole();
    if (code === null || this.draftPerms().includes('USER.MANAGE')) {
      return false;
    }
    // Any OTHER role still carrying it means somebody can still grant.
    return !this.roles().some(
      (r) => r.code !== code && r.permissions.includes('USER.MANAGE'));
  });

  protected startEditRole(role: RoleRow): void {
    this.editingRole.set(role.code);
    this.draftPerms.set([...role.permissions]);
  }

  protected cancelEditRole(): void {
    this.editingRole.set(null);
  }

  protected hasPerm(code: string): boolean {
    return this.draftPerms().includes(code);
  }

  protected togglePerm(code: string): void {
    this.draftPerms.update((current) =>
      current.includes(code)
        ? current.filter((c) => c !== code)
        : [...current, code]);
  }

  protected saveRolePerms(): void {
    const code = this.editingRole();
    if (code === null || this.saving()) {
      return;
    }
    this.saving.set(true);
    this.http.put(`${this.base}/roles/${encodeURIComponent(code)}/permissions`,
      { permission_codes: [...this.draftPerms()] })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: () => {
          this.saving.set(false);
          this.editingRole.set(null);
          this.toast.show(this.i18n.translate('access.roleSaved'));
          this.load();
        },
        error: (error: unknown) => {
          this.saving.set(false);
          this.toast.error(this.i18n.translate(refusalKey(readRefusal(error))));
        },
      });
  }

  /** Every permission, split into the ones that open a screen and the rest. */
  protected readonly screenPermissions = computed(
    () => OPS_NAV.map((entry) => ({ code: entry.permission, labelKey: entry.labelKey })));

  protected readonly actionPermissions = computed(() => {
    const onScreens = new Set(OPS_NAV.map((entry) => entry.permission));
    return this.allPermissions().filter((code) => !onScreens.has(code));
  });

  /** The screens one role opens, for the roles tab. */
  protected roleScreens(role: RoleRow): readonly { key: string; labelKey: string }[] {
    const held = new Set(role.permissions);
    return OPS_NAV.filter((entry) => held.has(entry.permission));
  }

  /** Permissions in a role that open no screen - actions inside one. */
  protected roleActions(role: RoleRow): readonly string[] {
    const onScreens = new Set(OPS_NAV.map((entry) => entry.permission));
    return role.permissions.filter((code) => !onScreens.has(code));
  }

  protected roleNames(user: UserRow): string {
    return user.roles.length
      ? this.i18n.list(user.roles.map((r) => r.name_ar))
      : this.i18n.translate('access.noRoles');
  }

  protected count(value: number): string {
    return this.format.count(value);
  }
}
