# CI

`run.sh` is the gate. One entry point, five stages, and one rule above them
all: **a stage that ran nothing has failed.**

```bash
bash deploy/ci/run.sh                # every stage
bash deploy/ci/run.sh lint db        # named stages
bash deploy/ci/run.sh --self-test    # prove the counters refuse zero
bash deploy/ci/run.sh --list
```

## Why every stage reports a count

Four separate things in this project have reported success while doing no
work at all — `ng test` exiting 0 with the browser never started, a seed
whose `INSERT ... SELECT` read an empty table, a teardown that deleted zero
rows under the wrong prefix, and a published-surface check that passed on
its first run before it had been shown to read anything.

So each stage prints what it executed, and that number is asserted **before**
the exit code is consulted. `FAIL-EMPTY` in the summary means the stage did
not fail its checks — it never ran any.

## It was shown failing before it was believed

A green first run proves nothing. Three refusals were demonstrated:

| | |
|---|---|
| `surface` with `HBH_CI_ORIGINS` unset | `FAIL-EMPTY`, exit 1 — it did not pass by probing nothing |
| a counter edited to return 99 | `SELF-TEST NOT ACCEPTED`, 3 counters wrong |
| `HBH_CI_LOGDIR` inside the tree | refused before creating anything |

## Three things it will not do

1. **Never `db.sh reset` or `nuke`.** The database is shared between
   concurrent sessions; a reset once pulled the schema out from under another
   process mid-migration. `migrate` only.
2. **Never `npm test` or `ng test`.** `scripts/web.sh test` counts spec files
   on the host and refuses at zero — calling the underlying tool skips the
   only guard there is. (karma's `failOnEmptyTestSuite` does not help:
   `@angular/build:karma` ignores it.) `run.sh` adds the second half that
   `web.sh` cannot make: how many specs the **browser** executed.
3. **Never write logs into the project tree.** The tree is on a redirected
   Desktop syncing to OneDrive. A path inside it, or inside any sync folder,
   stops the run — it does not warn. Default is `~/hbh-ci-logs`.

## What is not here yet

**There is no runner.** `git remote -v` is empty, so nothing triggers this on
a push; today it is a command a person types. That is still worth having —
one command that cannot lie about what it ran beats five that can — but the
card is not closed until something calls it without being asked.

`surface` also needs origins given to it:

```bash
HBH_CI_ORIGINS='https://hbhskills.com https://apply.hbhskills.com' \
  bash deploy/ci/run.sh surface
```

Unset, it fails rather than passing — which is the whole point of the file.
