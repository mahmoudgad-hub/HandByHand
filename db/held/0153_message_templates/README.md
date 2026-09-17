# 0153 — WhatsApp message templates in the database (HELD)

**Not in `db/migrations/` on purpose.** Any `db.sh migrate` applies every file there, and every file in `db/seed/` on every run.

Written as `0150` on 2026-09-17. Moved here as `0152` the same day at the database developer's request (0149–0151 were reserved for other work), then swapped to `0153` so the database developer's conventions fix for 0145/0146, ready now, could take `0152`.

## What is in this folder

| File | Goes to | |
|---|---|---|
| `0153_message_templates.up.sql` · `.down.sql` | `db/migrations/` | the tables, functions, HB300–HB306 |
| `0005_message_templates.sql` | `db/seed/` | the permission and the six templates per centre |

**They move together.** The seed reads `hbh.message_templates`; placed in `db/seed/` before the migration is applied, it fails every `migrate` for everyone.

## The conditions, in order

1. **0152 applied.** The guard refuses otherwise.
2. **An API image that names HB300–HB306 in `businessRefusal` is built and running.** Until then `scripts/api.sh code-drift` fails on those codes. No route calls the functions that raise them yet, so nothing reaches a screen as 500 in the meantime - but the lint is part of the build, and it would be red.
3. **Then** move both files as the table above says, and run `db.sh migrate`.

**The image does not have to wait for the migration.** Its lookups (`hbh.message_template_sid`, `hbh.sms_template_sid`) treat a missing function as "no approved template", which is the truth of a database without this table. In development that changes nothing; in production the image refuses to start with `SMS_PROVIDER=twilio_whatsapp` until this migration is applied and `OTP_LOGIN` is approved in every active centre.

## Proven

Applied with the seed in a rolled-back transaction on `148|0148` (as 0150, identical apart from the number and guard): six rows for the HBH centre, every seeded text passes the placeholder contract, six events written on insert, `PORTAL_UPDATE` resolved for `REQUEST_DECIDED`, no ContentSid before approval, the down migration clean.

Acceptance suite: `p19_verify.sql` in this folder — held with it, because `db.sh verify` runs every `tests/db/p*_verify.sql` and this one needs the table. **It moves to `tests/db/` in the same step as the migration.**

2026-09-17, on `152|0152`, as `BEGIN; 0153 up; 0005 seed; p19; ROLLBACK;` against the shared database: **45 checks, 0 failed — PHASE 19 ACCEPTED.** Covered: HB300 (no permission, before the row is read), HB301 (another centre's template and a nonexistent id, one answer), HB302 ×3, HB304, HB303 (DRAFT→APPROVED, status call to DRAFT, and direct UPDATEs by the owner), HB305, HB306 ×2, RLS visibility by centre and permission, an edit of an APPROVED template keeping its ContentSid, the key map (`REQUEST_DECIDED`/`APPOINTMENT_CANCELLED` → `PORTAL_UPDATE`), the history append-only (HB001), `sms_template_sid` refusing a user session (HB230) and answering the worker, and a cleanup that leaves nothing.

**Seen failing before trusted**, on one-line mutants of the migration: removing the permission check in `edit_message_template` fails "the clerk may not edit - HB300" (the call succeeded) and the history check; clearing `content_sid` on edit fails the three checks that the approved template is still the one sent.
