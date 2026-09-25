# 0164: HBH-099 — a family can be given to a child who already exists (HELD, not approved yet)

**Needs the owner's approval, and `0163` applied first** (the ledger has no gaps). No API change, no new SQLSTATE.

## What was missing

Everything that writes `hbh.guardian_children` writes it at **creation** time — `submit_enrolment` and `convert_enrolment`, the enrolment path. So a child already in the system could only be given a family by an `INSERT` as the database owner. Two live children show it today; the first child added from the console hits the same wall. Same shape as HBH-049's caseload: policies, indexes, no door.

## The owner's rules, answered 2026-09-18

| | |
|---|---|
| A child may exist with **no** guardian | So linking is a later step, not a condition of creating a child. |
| **More than one** guardian may be linked, without ending the first | A father and a mother; shared custody. |
| **One primary and no more** | «واحد أساسي بس، والتاني يفضل مربوط عادي» — the second stays linked with their own rights. |

**Answered the same day: one primary and no more** — the one the invoice and the report go to — and the second guardian stays linked with their own rights. **Linking does not move the trait.**

Built three ways at once, each of which matters:

- **`link_guardian_to_child` does not take `is_primary` at all.** A new link is never primary, so the trait cannot be acquired as a side effect of an unrelated call, and there is no argument to get wrong.
- **Moving it is a named act:** `set_primary_guardian`. Whoever wants to change who receives the invoice says so.
- **The database enforces the number, not the function.** `uix_gc_one_primary` (`child_id WHERE is_primary_flg AND active_flg`) predates the question and already says "at most one live primary". A condition inside a function would be a second copy of a rule, and the weaker copy decides (rule 4). The probe proves the limit by writing **directly against the index** and asserting `23505 uix_gc_one_primary` through `CONSTRAINT_NAME` (D-40) — asking the index itself, not the function's opinion of it.

**A child with no primary is legal.** The owner allowed a child with no guardian at all, so the index forbids **two** and does not demand **one**. Measured before writing: no child has two live primaries, and none with a live link has none.

**Nothing new was added to the schema for this.** The index PM asked for already existed; reading first turned a migration into a line in the header.

## The two functions

| | |
|---|---|
| `link_guardian_to_child(guardian, child, relationship, can_view_reports default true)` → `boolean` | true when the call changed something. A new link is NEVER primary. |
| `set_primary_guardian(guardian, child)` → `boolean` | Moves the primary contact to a guardian already linked to this child. |
| `unlink_guardian_from_child(guardian, child)` → `boolean` | Soft: `active_flg` false, `deleted_at` stamped. |

- **`HB092` → 403** without `GUARDIAN.MANAGE`, asked before any id is read. **`HB051` → 404** for a child, guardian or link missing *or another centre's*. **`HB021` → 400** for a relationship the `RELATIONSHIP` lookup does not carry (`FATHER`, `MOTHER`, `GUARDIAN` today). No default relationship: "who is this person to the child" is a fact, and a default invents it.
- **`can_view_live_flg` is never raised here.** `trg_live_flag_needs_consent` refuses it without a recorded consent (`HB081`), and consent is `grant_consent`'s job. A link is not a consent.
- **Re-linking revives** the same row — the primary key is the pair — so an ended link comes back instead of colliding, and an unchanged one answers false.
- **Unlink keeps `is_primary_flg`** on the ended row: the index counts only live rows, and who used to be the primary contact is history.

## Proof

`probe_0164.sql`, rolled back on `162|0162` (with `0163` recorded inside it): **23 ok, 0 failed** — the gate for three callers, one answer for foreign and missing ids, the lookup refusal, both of the owner's link rules, a new link never primary, the named transfer moving it and demoting the previous holder while leaving them linked, the index refusing a second primary by name, the soft unlink and its idempotence, relink reviving one row, grants and pinned `search_path`, down and up.

Nothing persisted: one centre, no functions, ledger `162|0162`.

**One mistake worth keeping:** the first draft asserted "the mother is linked, and now there are two links" in a **single statement**. The count read the snapshot from before the call and answered `true 1`. Two statements. It is the CLAUDE.md lesson about data-modifying CTEs, and it applies to any count sitting beside the write it means to observe.
