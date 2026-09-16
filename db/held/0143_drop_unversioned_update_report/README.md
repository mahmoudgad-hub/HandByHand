# 0143 — drop the six-argument update_report, backlog #14 (HELD)

**Not in `db/migrations/` on purpose.** Any `db.sh migrate` applies every file there.

Written as `0151`; renumbered 2026-09-13. Where #14 stands:

1. `0141` — applied. `hbh.update_report(id, expected_version, …)` raising HB290.
2. API image `d7c8c40a` — running, calls the seven-argument function; a5 188/0, p4 108/0 on `141|0141`.
3. `0142` — payment plans, applied.
4. **`0143` — this folder**, after the API round on `142|0142`. Until it lands the
   version check is optional: a caller that picks the old signature overwrites a
   colleague's draft unseen.

Its guard refuses unless `0141` is recorded and the seven-argument function
exists. Proven in a rolled-back transaction: alone → refused; after 0141 → one
function left (7 args); down → back to the six-argument one.
