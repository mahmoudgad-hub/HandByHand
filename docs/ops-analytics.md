# Operations analytics

The first tab in `/ops-log` is **لوحة المتابعة**. Its inclusive calendar date
filter defaults to today in the centre's time zone. Every chart and metric
opens a modal with server-paginated details (50 rows per page), using the
applied date range even if the date fields have subsequently been edited.

## What is counted

- Request success: HTTP status below 400; errors: 400–599. Both use the same
  denominator. Only requests attributed to the current centre are counted.
  Anonymous requests without a centre and analytics/telemetry requests are
  excluded. Empty periods show no percentage, rather than 100% success.
- Performance: P50/P95 API response duration in milliseconds, plus the eight
  routes with the highest P95. The performance card opens all request details.
  This measures server response duration, not browser rendering time.
- Registration applications: distinct parent mobile numbers submitting WEB
  enrolment applications in the period. Multiple children/applications from
  the same mobile count as one parent.
- New guardian accounts: users of type GUARDIAN created in the period,
  including accounts provisioned by staff.
- First portal login: earliest stored auth-session issue time per guardian.
- Staff logins: distinct STAFF/THERAPIST users with an auth session issued in
  the period. Staff activity counts distinct visitors even when their session
  was established before the selected period.
- Portal features and staff pages: actual navigation events, not API polling.
  Each feature reports distinct users separately from repeat visits. Portal
  actions count successful POST/PUT/PATCH/DELETE requests initiated from that
  feature; they are not a count of button clicks or failed attempts.

The portal catalogue includes zero-use features. Reports, notes, goals,
requests and messages are distinguished by allowlisted tab identifiers.
No route IDs, arbitrary query strings, submitted form values or message
content are sent as usage metadata. Telemetry failures do not change the
original request outcome or sign the user out; no telemetry retries occur.

## API and storage

- `GET /api/v1/ops/analytics?from=YYYY-MM-DD&to=YYYY-MM-DD`
- Detail query: additionally `kind`, optional `feature`, and `offset`.
- `POST /api/v1/usage-events` with `app`, `feature`, `kind`, `action`.
- Migration `0145_ops_analytics` creates the event table and two functions.
  It derives identity and centre server-side. Reads require `OPS.VIEW` and
  are explicitly centre-scoped. A guardian cannot emit staff events.
- Maximum reporting range is 366 inclusive calendar days. Date bounds are
  converted by PostgreSQL from the centre's time zone to UTC, including DST.

Historical visits cannot be reconstructed. Usage tracking starts with this
release; older request statistics remain limited by request-log retention.
First-login reporting relies on retained authentication-session history.
The usage table is append-only for the application role; this release does
not introduce a scheduled retention job for these product events.

## Validation and release

Local checks:

- Ops analytics and shell browser tests: 14 passed.
- Shared usage tracker browser tests: 3 passed.
- Ops and portal production builds pass (existing size warnings remain).
- All Go tests and `go vet ./...` passed in the local Docker API build.

`tests/db/ops_analytics.sql` exercises distinct counts, date boundaries,
centre isolation, permission refusal, pagination and detail shapes. It uses
synthetic fixtures inside a rolled-back transaction. It passed against the
local development PostgreSQL both before and after applying migration 0145.

## Development activation — 2026-09-14

The user selected the local development version, not a remote release.

- Ops: `http://localhost:4310/ops-log`; portal: `http://localhost:4210`.
- Containers: `hbh-web-ops`, `hbh-web-portal`, `hbh-api`, `hbh-db`.
- The dev servers mount this workspace and pick up the frontend changes.
- Applied missing avatar migration 0144 and analytics migration 0145 to the
  local development database. Rebuilt/recreated only the API service, with
  matching environment settings. Health check passed.
- Live authenticated summary and all ten detail kinds passed; unauthenticated
  access returned 401. The temporary verification session was revoked.
- Browser verification showed the first dashboard tab, today's date filter,
  live metrics, and the errors chart opening its real detail table. Staff
  navigation events are recorded.
- Database dump and previous API binary are retained locally in
  `C:/Users/mgad8/AppData/Local/Temp/hbh-dev-analytics-backup-20260914-202755`.
  The old image's layers were unavailable to Docker, so the running binary
  was copied before replacement as the API rollback artifact.
- No analytics files were transferred to `gad`; its deployment was unchanged.

The existing shell CSS was split into `shell.css` and `shell-controls.css`
in the original order, without changing its content, to resolve its existing
per-stylesheet production size error. No budget thresholds were increased.
