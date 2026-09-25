import { HttpClient } from '@angular/common/http';
import { Injectable, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { Observable, map, tap } from 'rxjs';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { UserAvatars } from '@hbh/shared/ui/user-avatar';

const TOKEN_KEY = 'hbh.ops.session';

/** POST /api/v1/auth/staff/login, verbatim. */
interface LoginResponse {
  readonly token_type: string;
  readonly token: string;
  readonly expires_at: string;
}

/** GET /api/v1/me, verbatim. */
interface MeResponse {
  readonly user: {
    readonly user_id: number;
    readonly center_id: number;
    readonly username: string;
    readonly full_name_ar: string;
    readonly user_type: string;
    readonly status: string;
    /** The caller's row in hbh.therapists, absent when they have none. */
    readonly therapist_id?: number;
  };
  readonly center: {
    readonly center_id: number;
    readonly code: string;
    readonly name_ar: string;
    readonly country_code: string;
    readonly currency_code: string;
    readonly time_zone: string;
    readonly weekend_days: readonly number[];
  };
  readonly permissions: readonly string[];
}

export interface Identity {
  readonly userId: number;
  readonly username: string;
  readonly fullName: string;
  readonly userType: string;
  /**
   * Which therapist this account IS, when it is one.
   *
   * Undefined for reception and for an administrator - and undefined
   * rather than zero, because "not a therapist" and "therapist zero" must
   * not read alike in a filter.
   *
   * NOT a permission. What a therapist may see is decided by a policy; this
   * answers "which of these rows are MINE", which is a screen's default
   * filter. /my-day had no way to ask it and so showed the whole centre.
   */
  readonly therapistId?: number;
  readonly centerCode: string;
  readonly centerName: string;
  readonly countryCode: string;
  readonly currency: string;
  readonly timeZone: string;
  /** ISO weekday numbers the centre is closed. Egypt is [5,6]. */
  readonly weekendDays: readonly number[];
  readonly permissions: readonly string[];
}

/**
 * Who is signed in to the console, and what the server says they may do.
 *
 * The permissions list is used for ONE thing: deciding which menu entries and
 * buttons to draw. It is not a control. Every refusal that matters happens in
 * a row level security policy underneath the query, and it happens whether or
 * not this list was ever read - a user who types a URL reaches the same
 * server that would have refused them. See CLAUDE.md, rule 4.
 *
 * sessionStorage, not localStorage: a console on a shared reception desk must
 * not still be signed in tomorrow morning because a tab was left open.
 */
@Injectable({ providedIn: 'root' })
export class OpsAuthService {
  private readonly avatars = inject(UserAvatars);
  private readonly http = inject(HttpClient);
  private readonly router = inject(Router);
  private readonly base = `${inject(HBH_CONFIG).apiBaseUrl}/api/v1`;

  private readonly session = signal<{ token: string; expiresAt: string } | null>(
    this.restore());
  private readonly identity = signal<Identity | null>(null);

  readonly isSignedIn = computed(() => this.session() !== null);
  readonly me = this.identity.asReadonly();

  get token(): string | null {
    return this.session()?.token ?? null;
  }

  signIn(username: string, password: string): Observable<void> {
    return this.http
      .post<LoginResponse>(`${this.base}/auth/staff/login`, { username, password })
      .pipe(
        tap((body) => this.adopt(body.token, body.expires_at)),
        map(() => undefined),
      );
  }

  /** Loads the identity and permissions. Called after sign-in and on reload. */
  loadIdentity(): Observable<Identity> {
    return this.http.get<MeResponse>(`${this.base}/me`).pipe(
      map((body) => ({
        userId: body.user.user_id,
        therapistId: body.user.therapist_id,
        username: body.user.username,
        fullName: body.user.full_name_ar,
        userType: body.user.user_type,
        centerCode: body.center.code,
        centerName: body.center.name_ar,
        countryCode: body.center.country_code,
        currency: body.center.currency_code,
        timeZone: body.center.time_zone,
        weekendDays: body.center.weekend_days ?? [],
        permissions: body.permissions ?? [],
      })),
      tap((identity) => { this.avatars.reset(identity.userId); this.identity.set(identity); }),
    );
  }

  /** True when the server granted this permission. Used to draw, not to guard. */
  can(permission: string): boolean {
    return this.identity()?.permissions.includes(permission) ?? false;
  }

  /**
   * Role label key used by the console header and profile screens.
   *
   * `user_type` is not enough to distinguish manager from reception for STAFF
   * accounts, because both share it in the database. We infer the role label
   * from the assigned permissions; center admin accounts hold at least one
   * admin-level permission.
   */
  roleLabelKey(identity: Identity | null = this.identity()): string {
    if (!identity) {
      return '';
    }
    const permissions = identity.permissions ?? [];
    if (identity.userType === 'THERAPIST') {
      return 'role.THERAPIST';
    }
    if (identity.userType === 'GUARDIAN') {
      return 'role.GUARDIAN';
    }
    if (identity.userType === 'STAFF') {
      if (permissions.includes('USER.MANAGE')
        || permissions.includes('STAFF.MANAGE')
        || permissions.includes('SITE.EDIT')) {
        return 'role.CENTER_ADMIN';
      }
      return 'role.RECEPTION';
    }
    if (identity.userType === 'ADMIN') {
      return 'role.ADMIN';
    }
    return `access.type.${identity.userType}`;
  }

  /**
   * Clears this device first, then tells the server. If the network call
   * fails the console is still signed out here, which is the safe direction.
   * The server revoke is what actually ends the session - closing a tab does
   * not.
   */
  signOut(): void {
    this.avatars.reset(null);
    this.session.set(null);
    this.identity.set(null);
    try {
      sessionStorage.removeItem(TOKEN_KEY);
    } catch {
      // Storage blocked; nothing was stored to clear.
    }
    this.http.post(`${this.base}/auth/logout`, {}).subscribe({
      error: () => undefined,
    });
    void this.router.navigate(['/login']);
  }

  /** Called by the interceptor when the server rejects the token. */
  sessionExpired(): void {
    this.avatars.reset(null);
    this.session.set(null);
    this.identity.set(null);
    try {
      sessionStorage.removeItem(TOKEN_KEY);
    } catch {
      // As above.
    }
    void this.router.navigate(['/login'], { queryParams: { reason: 'expired' } });
  }

  private adopt(token: string, expiresAt: string): void {
    this.session.set({ token, expiresAt });
    try {
      sessionStorage.setItem(TOKEN_KEY, JSON.stringify({ token, expiresAt }));
    } catch {
      // The session simply does not survive a reload. Safe direction.
    }
  }

  private restore(): { token: string; expiresAt: string } | null {
    try {
      const raw = sessionStorage.getItem(TOKEN_KEY);
      if (!raw) {
        return null;
      }
      const stored = JSON.parse(raw) as { token: string; expiresAt: string };
      // Reading the expiry here saves a round trip on an obviously dead
      // token. It is a courtesy, not a check - the server decides.
      if (!stored.token || new Date(stored.expiresAt).getTime() <= Date.now()) {
        sessionStorage.removeItem(TOKEN_KEY);
        return null;
      }
      return stored;
    } catch {
      return null;
    }
  }
}
