/**
 * When a report draft saves itself (backlog #13).
 *
 * Built on #14, and only possible because of it: the service refuses a save
 * over a version a colleague has since replaced (migration 0141). Autosave
 * without that check would make the defect it fixes worse - a draft saving
 * every few seconds would quietly overwrite a colleague every few seconds.
 *
 * Nothing here decides whether a draft is VALID. A blank title or a period
 * that runs backwards is sent like anything else and refused by
 * hbh.update_report, which is where that rule lives (rule 2). This file
 * decides only whether to TRY.
 */

/** Why the draft is not being saved automatically right now, or null to save. */
export type AutosaveHold =
  /**
   * Never saved. Autosave does not create a report: creating one gives it a
   * report number and puts a record on a child's file, and that is a
   * decision the therapist makes with the button.
   */
  | 'NEW'
  | 'PUBLISHED'
  /** A save or a publish is already on its way; the next one waits for it. */
  | 'BUSY'
  /**
   * A colleague saved since this editor opened. Retrying would be refused
   * identically forever - the newer text has to be loaded first.
   */
  | 'CHANGED'
  /** Nothing typed since the last save. */
  | 'CLEAN';

export interface AutosaveState {
  readonly hasReport: boolean;
  readonly published: boolean;
  readonly saving: boolean;
  readonly publishing: boolean;
  readonly changed: boolean;
  readonly dirty: boolean;
}

export function autosaveHold(s: AutosaveState): AutosaveHold | null {
  if (!s.hasReport) { return 'NEW'; }
  if (s.published) { return 'PUBLISHED'; }
  if (s.changed) { return 'CHANGED'; }
  if (s.saving || s.publishing) { return 'BUSY'; }
  if (!s.dirty) { return 'CLEAN'; }
  return null;
}

/**
 * Fires once typing pauses for `quietMs` - and, for someone who never
 * pauses, no later than `maxMs` after the first unsaved keystroke. Without
 * the ceiling a therapist writing steadily for twenty minutes has saved
 * nothing when the laptop lid closes.
 */
export class AutosaveTimer {
  private quiet: ReturnType<typeof setTimeout> | null = null;
  private ceiling: ReturnType<typeof setTimeout> | null = null;

  constructor(
    private readonly fire: () => void,
    private readonly quietMs: number,
    private readonly maxMs: number,
  ) {}

  /** Something changed. */
  poke(): void {
    if (this.quiet !== null) { clearTimeout(this.quiet); }
    this.quiet = setTimeout(() => this.run(), this.quietMs);
    if (this.ceiling === null) {
      this.ceiling = setTimeout(() => this.run(), this.maxMs);
    }
  }

  /** Stop both clocks - a save started some other way, or the screen closed. */
  cancel(): void {
    if (this.quiet !== null) { clearTimeout(this.quiet); }
    if (this.ceiling !== null) { clearTimeout(this.ceiling); }
    this.quiet = null;
    this.ceiling = null;
  }

  private run(): void {
    this.cancel();
    this.fire();
  }
}
