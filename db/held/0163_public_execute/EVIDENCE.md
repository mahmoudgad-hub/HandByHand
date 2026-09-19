# HBH-100 evidence — the p00 check, seen failing before the fix

## BEFORE (live schema 162|0162, 2026-09-18 00:30 UTC)

```
           offenders           
-------------------------------
 archive_user
 can_edit_therapist
 center_today
 check_installments_total
 create_invoice
 create_user
 current_user_is_staff
 issue_invoice
 mark_installment_dues
 override_installment_schedule
 payment_plan_problem
 publish_therapist_profile
 record_therapist_consent
 remove_invoice_line
 set_user_roles
 settle_installments
 update_therapist_profile
 update_user
 withdraw_therapist_consent
(19 rows)

```

The check is `chk_empty`, so a non-empty list is a failure. It names nineteen.

## AFTER (live schema 163|0163, 2026-09-19, image sha256:18cfe3ef6815…)

Same query, same database, after `db.sh migrate` applied 0163:

```
 offenders 
-----------
(0 rows)
```

And the rule as the suite runs it, not as an ad-hoc query:

- **Before**, on `162|0162`, `p00_verify.sql` carrying this check printed
  `40 checks, 1 failed` / `PHASE 00 NOT ACCEPTED`, and the one failure was
  `shape | no callable SECURITY DEFINER function is executable by PUBLIC`
  with all nineteen names in its `offenders:` detail. **The check was seen
  failing before the fix**; it is not green from its first run.
- **After**: `40 checks, 0 failed` / `PHASE 00 ACCEPTED`, `schema: 163|0163`.

## hbh_app's reach, measured rather than reasoned about

| function | `has_function_privilege('hbh_app', …, 'EXECUTE')` |
|---|---|
| `mark_installment_dues()` | `false` — lost, intended |
| `center_today(integer)` | `false` — lost, intended |
| `create_user(text,text,text,text,integer)` | `true` — kept |
| `issue_invoice(integer,integer)` | `true` — kept |

## Nothing calls the five from a non-definer context

Every caller of the five internal helpers is itself `SECURITY DEFINER`, so it
runs as the owner and keeps its reach (`pg_proc.prosecdef`, measured):

| helper | callers (all `prosecdef = t`) |
|---|---|
| `center_today` | `issue_invoice`, `mark_installment_dues`, `override_installment_schedule`, `settle_installments` |
| `check_installments_total` | `trg_installments_total` |
| `mark_installment_dues` | `run_maintenance` |
| `payment_plan_problem` | `issue_invoice`, `trg_payment_plan_rules` |
| `settle_installments` | `override_installment_schedule`, `trg_payment_recalc` |

No view in `hbh` or `hbh_test` references any of them (`pg_get_viewdef`), which
matters because every view here is `security_invoker` and would have run as
`hbh_app`.

**Correction to the README's grep.** It reported "zero references in `api/`,
`web/`, `scripts/`, `deploy/`" — true, but it omits the one directory that does
contain callers: `tests/db/p17_verify.sql` calls `hbh.center_today` (345, 472)
and `hbh.mark_installment_dues()` (485, 491, 492). Those lines run as the owner
— the nearest preceding statement is `RESET ROLE` in both cases (342 and 447) —
so the revoke does not reach them. Confirmed by running the suite rather than by
reading it: **p17 after 0163 = 91 checks, 0 failed.**
