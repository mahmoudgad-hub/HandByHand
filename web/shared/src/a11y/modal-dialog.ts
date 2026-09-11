import {
  DestroyRef, Directive, ElementRef, HostListener, afterNextRender, inject, output,
} from '@angular/core';

/**
 * Makes a `<dialog>` actually modal.
 *
 * WHY THIS EXISTS
 * The console's overlays were `<div role="dialog" aria-modal="true">`. Both
 * attributes are a PROMISE to a screen reader - nothing outside this element
 * is reachable - and nothing kept it. Measured on the child editor: focus
 * stayed on the button that opened it, Escape did nothing, the page behind
 * was not inert, and seven presses of Tab reached the ARCHIVE button of a
 * row underneath the scrim. An action that changes a child's record, open
 * through a surface drawn as blocked.
 *
 * `showModal()` is the platform answering all four at once: it moves focus
 * in, contains Tab, makes the rest of the document inert, closes on Escape,
 * and returns focus to whatever opened it. None of that is worth
 * reimplementing in TypeScript, and a hand-rolled focus trap is a thing that
 * rots quietly - it keeps passing its own test while a new control type
 * escapes it.
 *
 * ANGULAR STILL OWNS WHETHER THE DIALOG EXISTS. The platform's own close on
 * Escape is refused and re-emitted as `dismissed`, so the component's signal
 * stays the single source of truth. Letting the browser close it directly
 * would leave `editing()` holding a row with no editor on screen - a form
 * that is open as far as the code is concerned and gone as far as the person
 * is.
 *
 * The host must be a real `<dialog>`. Do not add `role="dialog"` or
 * `aria-modal` beside it: a modal `<dialog>` carries both implicitly, and
 * repeating them is how the two get to disagree later.
 */
@Directive({ selector: 'dialog[hbhModal]' })
export class ModalDialog {
  private readonly host = inject<ElementRef<HTMLDialogElement>>(ElementRef);

  /** Escape, or any other dismissal the platform initiates. */
  readonly dismissed = output<void>();

  constructor() {
    const dialog = this.host.nativeElement;

    // After render, not in the constructor: showModal() throws on an element
    // that is not yet in the document, and a directive inside an @if is
    // created before its element is attached.
    afterNextRender(() => {
      if (!dialog.open) {
        dialog.showModal();
      }
      // showModal() focuses the first focusable descendant, and in these
      // panels that is the X in the corner - so a keyboard user is put on
      // "discard" before they have seen the form. Move to the first field
      // that will take a value instead. A dialog with no fields is a
      // confirmation, and there the platform's choice is the right one.
      const first = dialog.querySelector<HTMLElement>(
        'input:not([disabled]),select:not([disabled]),textarea:not([disabled])');
      first?.focus();
    });

    // Closing on the way out matters even though the element is about to go:
    // a dialog left open in the top layer keeps the rest of the document
    // inert, and the screen behind it stops answering the mouse.
    inject(DestroyRef).onDestroy(() => {
      if (dialog.open) {
        dialog.close();
      }
    });
  }

  @HostListener('cancel', ['$event'])
  protected onCancel(event: Event): void {
    event.preventDefault();
    this.dismissed.emit();
  }
}
