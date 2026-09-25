# Public website content — DEV

The homepage reads **published database content through `site/content.js`**.
It does not connect the browser to PostgreSQL or expose the API.

## Sources

| Content | Database source |
| --- | --- |
| Contact, opening hours, address and map coordinates | `hbh.site_contact` |
| Services | `hbh.site_services` joined to `hbh.services` |
| Additional programmes | `hbh.site_programs` |
| Team names, roles, profile links and qualifications | `hbh.site_team`, `hbh.site_team_facts` |
| Published team gallery media and certificates | `hbh.site_team_media`, `hbh.site_team_certificates` |
| Reviews | `hbh.site_reviews` |
| FAQ | `hbh.site_faq` |
| Hero copy, packages, family cards, navigation, other copy and image paths | `hbh.site_texts`; new keys start with `page.` |
| Section visibility | `hbh.site_sections` |

`data-i18n` identifies text keys, while `data-content-src` and
`data-content-alt` identify image fields. Rendered managed text and assets
are marked `data-src="db"`. Dynamic lists use their own database records.
Team cards carry `data-member-id`; opening a profile uses that record's
published links/media, not a hard-coded name-to-file mapping.

`editorial.js` and `team-media.js` are no longer loaded by the page.
Schema-protected text rows remain protected and were not reworded.

## Local refresh

Run `scripts/site-export-local.py` using the bundled Python runtime for a
one-time export, or pass `--watch` for checks every ten seconds. It uses
the exact SQL query in `scripts/site-export.sh`, reads only the `hbh-db`
development container and writes content atomically only when it changes.
Published content is retained if a database read fails.

The active watch process writes its PID, last check and result to
`backups/site-export-local-status.json`. The process must be restarted
after a machine restart. Reload the browser after the next export to see
published changes; an already-open page is not live-updated.

Linux deployments retain `site-export.sh` / `site-export-watch.sh`.
No production deployment or database update was performed by this change.

Environment URLs, CSS/layout, decorative icons, map attribution and
generic control labels remain application configuration/UI, not business
content. Local portal links still resolve to `localhost:4210`.

## Recovery

`backups/site-db-migration_20260914_164035/` contains the previous site,
published JSON, original rows, executed migration SQL and new key manifest.
`scripts/migrate-site-content.py` is a one-time migration and rejects a
second run against already-bound markup.
