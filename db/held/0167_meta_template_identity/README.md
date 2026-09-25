# 0167 — a template is named by Meta, not by a reseller (HELD)

**Not in `db/migrations/` on purpose.** Any `db.sh migrate` applies every file there on every run, and this one replaces the lookups the running API image calls.

Written 2026-09-18, the day the owner moved the centre onto Meta's WhatsApp Cloud API and asked for Twilio to stop. Numbered 0160 first; 0160–0162 were taken by other sessions while it was being written, so it is **0167**.

## What is in this folder

| File | Goes to | |
|---|---|---|
| `0167_meta_template_identity.up.sql` · `.down.sql` | `db/migrations/` | the two columns, the three lookups, the approval |
| `p19_verify.sql` | `tests/db/` | **replaces** the live `tests/db/p19_verify.sql` |

**They move together.** The live p19 asserts the Twilio shape and fails the moment this migration lands; this copy asserts the Meta shape and fails until it does.

## What changes

- `hbh.message_templates` gains `template_name` and `language_code`, and loses `content_sid`. Meta issues no id for a template: it takes the **name it was approved under** and the **language it was approved in**, and answers a name in a language it does not have exactly as it answers a name it has never seen.
- `message_template_sid` / `sms_template_sid` / `centres_without_template_sid` become **`message_template_ref` / `sms_template_ref` / `centres_without_approved_template`**, returning the name, the language and `is_auth` as one row. `is_auth` is there because Meta builds authentication templates with a copy-the-code button and refuses the message unless the button's value is sent with the body — the same code, twice.
- `set_message_template_status` takes the name and language where it took the sid. **HB306 keeps its number** and changes its subject; its client code moves from `CONTENT_SID_REQUIRED` to `TEMPLATE_NAME_REQUIRED` in the image this waits for.

**Dropping `content_sid` costs nothing.** Checked on the live database before it was written: 6 templates, 0 with a sid, 0 APPROVED. Nothing was ever approved under a Twilio id, and the append-only events table keeps every row it has.

## The conditions, in order

1. **0153 applied.** The guard refuses otherwise.
2. **An API image carrying `TemplateRef` is running.** The image that names HB300–HB306 also has this: the Go half went in the same change. An older image calls `hbh.message_template_sid`, which this migration drops — and would then send every message with no template at all.
3. **Then** move all three files as the table above says, and run `db.sh migrate`.

**The image may go first.** Its lookups treat a missing function as "no approved template", so between the image and the migration a WhatsApp send is refused as CONFIG rather than sent wrong. In development nothing changes: the `dev` sender needs no approval.

## Proven

2026-09-18, on `162|0162`, in a rolled-back transaction: up, then down, then up again — the probe inside the migration approves a template, reads it back through all three lookups, and **rolls itself back through an exception handler** so the append-only history never records an approval that did not happen. Its own asserts caught two real faults while it was being written: a `DRAFT → APPROVED` jump the state machine refuses (HB303), and `{0,511}` in a CHECK, which Postgres rejects as an invalid repetition count — written that way, the constraint would not have rejected a long name, it would have failed **every** update of the table.

`p19_verify.sql` on the same transaction: **49 checks, 0 failed**. Seen failing on two one-line mutants — dropping the language from `message_template_ref` fails the two "which template is this sent under" checks, and dropping the name pattern from the approval lets an uppercase key through to the CHECK constraint instead of HB306.
