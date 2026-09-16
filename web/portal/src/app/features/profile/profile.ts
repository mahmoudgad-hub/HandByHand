import {
  ChangeDetectionStrategy,
  Component,
  DestroyRef,
  computed,
  inject,
  signal,
} from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Router, RouterLink } from '@angular/router';
import { catchError, forkJoin, of } from 'rxjs';

import { PortalApi } from '../../core/api/portal-api';
import { loadErrorKey, traceIdFor } from '../../core/api/portal-error';
import { AuthService } from '../../core/auth/auth.service';
import { ChildContextService } from '../../core/auth/child-context.service';
import { HbhAgePipe } from '@hbh/shared/format/format.pipes';
import { I18nService } from '@hbh/shared/i18n/i18n.service';
import { TranslatePipe } from '@hbh/shared/i18n/translate.pipe';
import {
  CentreContact, Child, Consent, Guardian, GuardianContact,
} from '../../core/models/portal.models';
import { Icon, IconName } from '@hbh/shared/icon/icon';
import { PersonAvatar } from '../../shared/ui/person-avatar';
import { ToastService } from '@hbh/shared/toast/toast.service';
import { ErrorNote } from '@hbh/shared/ui/error-note';
import { Skeleton } from '@hbh/shared/ui/skeleton';

/**
 * The guardian's account, children and recorded live-view access.
 *
 * Consent changes are handled by the centre until the portal has a real
 * consent write endpoint. Display recorded access without offering a switch
 * that always fails, and link to the existing family conversation.
 *
 * Nothing here is editable that the centre owns. A phone number, a name or a
 * child's file are changed at reception, where the change is checked against
 * identity documents - not from a phone.
 *
 * THE EXCEPTION IS THE PARENT'S OWN EMAIL AND CITY, and it is an exception
 * to the sentence above rather than a hole in it: neither is checked against
 * a document and neither authenticates anything. The mobile stays out
 * precisely because it IS the identity - the one-time code goes to it - and
 * the service enforces that by taking two arguments and no third.
 */
@Component({
  selector: 'hbh-profile',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, Icon, PersonAvatar, TranslatePipe, HbhAgePipe, Skeleton, ErrorNote],
  templateUrl: './profile.html',
})
export class Profile {
  private readonly api = inject(PortalApi);
  private readonly auth = inject(AuthService);
  private readonly childContext = inject(ChildContextService);
  private readonly destroyRef = inject(DestroyRef);
  private readonly toast = inject(ToastService);
  private readonly i18n = inject(I18nService);
  private readonly router = inject(Router);


  protected readonly guardian = signal<Guardian | null>(null);
  protected readonly children = signal<readonly Child[]>([]);
  protected readonly consents = signal<readonly Consent[]>([]);
  protected readonly loading = signal(true);
  protected readonly failed = signal(false);
  protected readonly failureKey = signal('error.load');
  /** Shown only where nobody can act on the failure. */
  protected readonly traceId = signal<string | null>(null);

  // ---- the two fields a parent owns ----
  //
  // THE SCREEN USED TO SHOW FOUR THINGS AND OFFER NONE. Name, phone,
  // children, consents - and only the consents could be touched. That is
  // right for the name and the phone (the phone IS the login, and the
  // one-time code goes to it) and wrong for an email address, which is
  // theirs and which nothing authenticates with.
  //
  // Null means the signed-in account has no guardian record at all - a
  // member of staff looking at the portal - and the card is absent rather
  // than empty. "No email on file" and "you are not a parent" are
  // different sentences.
  protected readonly contact = signal<GuardianContact | null>(null);
  protected readonly draftEmail = signal('');
  protected readonly draftCity = signal('');
  protected readonly savingContact = signal(false);
  protected readonly contactError = signal('');

  /** Only offer to save when there is something to save. */
  protected readonly contactDirty = computed(() => {
    const saved = this.contact();
    return !!saved
      && (this.draftEmail().trim() !== saved.email
        || this.draftCity().trim() !== saved.city);
  });

  protected saveContact(): void {
    if (!this.contactDirty() || this.savingContact()) {
      return;
    }
    this.savingContact.set(true);
    this.contactError.set('');
    this.api.setContact({
      email: this.draftEmail().trim(),
      city: this.draftCity().trim(),
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        // The SERVER's answer becomes the new truth, not the draft. It
        // trims and it may clear, and a screen that kept the draft would
        // show a value the record does not hold.
        next: (saved) => {
          this.contact.set(saved);
          this.draftEmail.set(saved.email);
          this.draftCity.set(saved.city);
          this.savingContact.set(false);
          this.toast.show(this.i18n.translate('profile.contactSaved'));
        },
        error: () => {
          this.savingContact.set(false);
          this.contactError.set('profile.contactRefused');
        },
      });
  }

  protected cancelContact(): void {
    const saved = this.contact();
    this.draftEmail.set(saved?.email ?? '');
    this.draftCity.set(saved?.city ?? '');
    this.contactError.set('');
  }

  constructor() {
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.failed.set(false);
    // The children come from the welcome summary rather than a second list
    // endpoint, so there is one server-side definition of "this guardian's
    // children" and not two that could disagree.
    forkJoin({
      // family(), not welcome(): the same list of children without each
      // child's day - four requests per child this screen never showed (#16).
      welcome: this.api.family(),
      consents: this.api.consents(),
      // Wrapped, unlike the two above. Those two ARE the screen; this one
      // fills a card on it. A staff account signed into the portal has no
      // guardian record and gets a 404 here, and that must not blank the
      // page they came to read.
      contact: this.api.contact().pipe(
        catchError(() => of<GuardianContact | null>(null))),
      // The centre's own card. Already null-on-failure inside the API,
      // so a centre that has published no contact row and a request that
      // failed both end as an absent card rather than a broken page.
      centre: this.api.centreContact(),
    })
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: ({ welcome, consents, contact, centre }) => {
          this.guardian.set(welcome.guardian);
          this.children.set(welcome.children);
          this.consents.set(consents);
          this.centre.set(centre);
          this.contact.set(contact);
          this.draftEmail.set(contact?.email ?? '');
          this.draftCity.set(contact?.city ?? '');
          this.loading.set(false);
        },
        // The refusal names itself. Showing "could not load" for a wrong
        // filter invites a retry that will be refused identically forever.
        error: (error: unknown) => {
          this.loading.set(false);
          this.failed.set(true);
          this.failureKey.set(loadErrorKey(error));
          this.traceId.set(traceIdFor(error));
        },
      });
  }

  protected consentIcon(consent: Consent): IconName {
    switch (consent.key) {
      case 'live_view': return 'ic-cast';
      case 'sms_notifications': return 'ic-mail';
      case 'activity_photos': return 'ic-camera';
    }
  }

  protected openChild(child: Child): void {
    this.childContext.select(child);
    void this.router.navigate(['/home']);
  }

  // ---- how to reach the centre ----
  //
  // This replaced a "help" button whose entire behaviour was a toast. A
  // parent with a question had no number, no address and no route in -
  // on the one screen where they would look for all three.
  protected readonly centre = signal<CentreContact | null>(null);

  /**
   * A link to the centre on a map, from whichever shape the column holds.
   *
   * `site_contact.map_url` carries BOTH in practice: a real link on some
   * centres and a bare "lat, lng" pair on this one. Treating the second
   * as a URL puts "30.001, 31.481" in an href and the link goes nowhere -
   * silently, because a browser will happily navigate to a relative path
   * of that name.
   *
   * Anything else returns '' and the button is not drawn at all. A map
   * button that opens nothing is worse than no map button.
   */
  protected readonly mapHref = computed(() => {
    const raw = (this.centre()?.mapUrl ?? '').trim();
    if (!raw) {
      return '';
    }
    if (/^https?:\/\//i.test(raw)) {
      return raw;
    }
    const pair = raw.match(/^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/);
    return pair
      ? `https://www.google.com/maps/search/?api=1&query=${pair[1]},${pair[2]}`
      : '';
  });

  protected signOut(): void {
    this.childContext.clear();
    this.auth.signOut();
  }

}
