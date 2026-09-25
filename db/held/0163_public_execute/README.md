# 0163: PUBLIC stops running what only hbh_app should run — LANDED 2026-09-19

**Applied** on `163|0163`. The two `.sql` files moved to `db/migrations/` and
`p00_addition.sql` is now inside `tests/db/p00_verify.sql` (section 4, beside
the other privilege rules — the note saying "section 1" was stale). What is
left in this folder is the record: this README, `EVIDENCE.md` with the before
and after, and `probe_0163.sql`.

No API change, no new SQLSTATE.

## Measured, not suspected

238 functions in the schema · **100 executable by PUBLIC** · 59 of those `SECURITY DEFINER` · **19 of those callable** (the rest return `trigger`).

A function is executable by PUBLIC unless told otherwise, and this schema has no default privileges. Every function written with `REVOKE ... FROM PUBLIC` beside its `GRANT` is clean; the ones written with only a `GRANT` carry an entry nobody decided on. I hit this once by hand, in 0154, on a function I was writing that day.

## What it means today — stated plainly, not dramatically

The cluster has two roles. There is no third party today, and fourteen of the nineteen were meant for `hbh_app` anyway. The exposure is of two kinds, neither of which needs one:

- **Five are internal** and reachable by the API role *only* through PUBLIC: `center_today`, `check_installments_total`, `payment_plan_problem`, `settle_installments`, and the one that matters — **`mark_installment_dues`**, the maintenance task that moves instalments to DUE and OVERDUE **across every centre** and notifies the families. Nothing outside the schema calls any of them (grepped: zero references in `api/`, `web/`, `scripts/`, `deploy/` — **and that list omitted `tests/`, which does have callers**; see the correction in `EVIDENCE.md`, they run as the owner and p17 is green after the change). Same shape 0150 closed for `next_number` and `expire_packages`.
- **Fourteen** carry a PUBLIC entry beside an explicit `hbh_app` grant — `create_user`, `set_user_roles`, `archive_user`, `issue_invoice` and the rest. Harmless while two roles exist; a trap the day a third is added, because a read-only reporting login would inherit EXECUTE on all of them without anybody writing a grant.

**Not touched:** trigger functions (calling one directly raises `0A000`, so there is nothing to take away) and non-definer functions (they run with the caller's own rights and RLS — PUBLIC there is the caller's own reach, not a privilege).

## Proof

`probe_0163.sql`, rolled back on `162|0162`: **12 ok, 0 failed.**

The property proved is not "PUBLIC lost something" but **`hbh_app`'s reach is unchanged except the five**: the probe captures every function the role can execute, before and after, and diffs the sets — it lost exactly those five by name and gained nothing. Plus: the owner is untouched and `run_maintenance()` still runs; three of the fourteen spot-checked as still reachable; trigger functions keep PUBLIC; down restores all nineteen and the role's reach exactly.

## To land it

1. Move both `.sql` files to `db/migrations/`, `db.sh migrate` under the lock.
2. Add `p00_addition.sql` — it is red on 19 functions until this migration runs, which is why it cannot land first.
