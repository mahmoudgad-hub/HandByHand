#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - export the site's content
#
#   bash scripts/site-export.sh          write site/content.js
#   bash scripts/site-export.sh --check  print it, write nothing
#
# WHY A FILE AND NOT AN ENDPOINT. The public site is deployable today
# precisely because nothing on its origin talks to the service:
# deploy/server/site.native.mjs has no proxy and its nginx block has
# none, both written as decisions. The API still runs with OTP_ECHO on
# and returns the login code in the response body, which is why the
# portal and console stay on loopback. A public read endpoint would put
# a route back from the open internet to the service, and the first
# person to add `location /api/` for it opens /api/v1/auth alongside.
#
# WHY .js AND NOT .json. The site must work when index.html is opened
# straight off disk - it is written that way and site/README.md says so.
# fetch('content.json') fails on file://; a <script> tag does not. So
# the export is an assignment to window.HBH_SITE_CONTENT, loaded the
# same way site/config.js already is.
#
# PUBLISHED ROWS ONLY, and that is the second barrier under the first.
# A draft cannot reach the page even if a screen showed it, because a
# draft is not in the file. The database is the first barrier: a
# published testimonial or photograph without a recorded consent cannot
# be written at all.
#
# WHAT IS DELIBERATELY NOT EXPORTED: guardian_id. It is how a consent
# stays attributable and how a withdrawal finds the row, and it is a
# link between a public sentence and a family's record. It stays in the
# database.
# =====================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/site/content.js"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

: "${DB_PORT:=5434}"
: "${DB_OWNER_PASSWORD:=hbh_dev_only_change_me}"
: "${CENTER_CODE:=HBH}"

# The query runs in the database and returns one JSON document. It is
# built there rather than assembled in shell on purpose: this content is
# Arabic, and Arabic does not survive a Windows shell's command line -
# a row inserted through one arrives as "?????" and stays that way. The
# text never becomes a shell argument here; psql writes it straight out.
read -r -d '' QUERY <<'SQL'
SELECT jsonb_pretty(jsonb_build_object(
  'generatedAt', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
  'contact', (
    SELECT to_jsonb(x) FROM (
      SELECT phone, landline, whatsapp, email,
             address_ar AS "addressAr", address_en AS "addressEn",
             map_url AS "mapUrl",
             -- Newlines survive JSON encoding, and the page splits on them.
             -- Each line is a separate instruction for getting here.
             arrival_ar AS "arrivalAr", arrival_en AS "arrivalEn",
             hours_ar AS "hoursAr", hours_en AS "hoursEn",
             weekend_ar AS "weekendAr", weekend_en AS "weekendEn"
      FROM hbh.site_contact
      WHERE center_id = c.center_id AND active_flg AND status = 'PUBLISHED'
      LIMIT 1
    ) x
  ),
  'faq', coalesce((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x."sortOrder", x.id) FROM (
      SELECT faq_id AS id, sort_order AS "sortOrder",
             question_ar AS "questionAr", question_en AS "questionEn",
             answer_ar AS "answerAr", answer_en AS "answerEn"
      FROM hbh.site_faq
      WHERE center_id = c.center_id AND active_flg AND status = 'PUBLISHED'
    ) x
  ), '[]'::jsonb),
  'team', coalesce((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x."sortOrder", x.id) FROM (
      SELECT t.member_id AS id, t.sort_order AS "sortOrder",
             t.name_ar AS "nameAr", t.name_en AS "nameEn",
             t.role_ar AS "roleAr", t.role_en AS "roleEn",
             t.photo_path AS "photoPath", t.profile_href AS "profileHref",
             t.org_ar AS "orgAr", t.org_en AS "orgEn",
             t.bio_ar AS "bioAr", t.bio_en AS "bioEn",

             -- The areas this person works in, as chips on the card.
             coalesce((
               SELECT jsonb_agg(jsonb_build_object(
                        'nameAr', sp.name_ar, 'nameEn', sp.name_en)
                      ORDER BY sp.sort_order, sp.specialty_id)
               FROM hbh.site_team_specialties sp
               WHERE sp.member_id = t.member_id AND sp.active_flg
             ), '[]'::jsonb) AS specialties,

             -- The gallery. PUBLISHED only, and a published media row is
             -- impossible without its own recorded consent - ck_stm_consent
             -- refuses it - so nothing here needs to test for one. A second
             -- check in this script would be a second definition of the
             -- rule, and the weaker of the two.
             coalesce((
               SELECT jsonb_agg(jsonb_build_object(
                        'path', m.path,
                        'poster', coalesce(m.poster_path, t.photo_path),
                        'durationS', m.duration_s,
                        'captionAr', m.caption_ar,
                        'captionEn', m.caption_en)
                      ORDER BY m.sort_order, m.media_id)
               FROM hbh.site_team_media m
               WHERE m.member_id = t.member_id AND m.active_flg
                 AND m.kind = 'VIDEO' AND m.status = 'PUBLISHED'
             ), '[]'::jsonb) AS videos,

             coalesce((
               SELECT jsonb_agg(jsonb_build_object(
                        'path', m.path,
                        'captionAr', m.caption_ar,
                        'captionEn', m.caption_en)
                      ORDER BY m.sort_order, m.media_id)
               FROM hbh.site_team_media m
               WHERE m.member_id = t.member_id AND m.active_flg
                 AND m.kind = 'PHOTO' AND m.status = 'PUBLISHED'
             ), '[]'::jsonb) AS photos,

             -- introVideo is kept, and it is a COMPATIBILITY SHIM rather
             -- than a second source. site/app.js renders one introduction
             -- film from this key; the gallery above is what the console
             -- now writes, so this is the first published film of that
             -- gallery, falling back to the single film 0055 put on the row
             -- for a member nobody has migrated yet.
             --
             -- It should be deleted once the page reads `videos`. Left in
             -- place because removing it first would blank the film on a
             -- live page to no purpose.
             coalesce(
               (SELECT jsonb_build_object(
                         'path', m.path,
                         'poster', coalesce(m.poster_path, t.photo_path),
                         'captionAr', m.caption_ar,
                         'captionEn', m.caption_en)
                FROM hbh.site_team_media m
                WHERE m.member_id = t.member_id AND m.active_flg
                  AND m.kind = 'VIDEO' AND m.status = 'PUBLISHED'
                ORDER BY m.sort_order, m.media_id
                LIMIT 1),
               CASE WHEN t.intro_video_path IS NOT NULL THEN
                 jsonb_build_object(
                   'path', t.intro_video_path,
                   'poster', coalesce(t.intro_video_poster_path, t.photo_path),
                   'captionAr', t.intro_video_caption_ar,
                   'captionEn', t.intro_video_caption_en)
               END) AS "introVideo",
             -- Qualifications as an ordered array, never one string with
             -- newlines in it. Each is a claim about a named person's
             -- credentials published under the centre's name, and the site
             -- draws them as separate lines.
             --
             -- Until this shipped, the site replaced the name and role and
             -- left the rest of the card alone - so a member added in the
             -- console appeared above the photograph and certificates of
             -- whoever had been in that position.
             coalesce((
               SELECT jsonb_agg(jsonb_build_object(
                        'textAr', f.text_ar, 'textEn', f.text_en)
                      ORDER BY f.sort_order, f.fact_id)
               FROM hbh.site_team_facts f
               WHERE f.member_id = t.member_id AND f.active_flg
             ), '[]'::jsonb) AS facts,
             -- Scanned certificates. PUBLISHED only, and a published row
             -- is impossible without both a recorded consent and a
             -- recorded redaction check - the database refuses it, so
             -- nothing here needs to test for either.
             --
             -- The path is the stored one, never built from member_id: a
             -- certificate appears because a row ties it to this person,
             -- not because a file in assets/ matched a name.
             coalesce((
               SELECT jsonb_agg(jsonb_build_object(
                        'path', cert.path,
                        'captionAr', cert.caption_ar,
                        'captionEn', cert.caption_en)
                      ORDER BY cert.sort_order, cert.certificate_id)
               FROM hbh.site_team_certificates cert
               WHERE cert.member_id = t.member_id AND cert.active_flg
                 AND cert.status = 'PUBLISHED'
             ), '[]'::jsonb) AS certificates
      FROM hbh.site_team t
      WHERE t.center_id = c.center_id AND t.active_flg AND t.status = 'PUBLISHED'
    ) x
  ), '[]'::jsonb),
  'services', coalesce((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x."sortOrder", x.id) FROM (
      -- The NAME comes from the catalogue, not from this table: the page
      -- and the booking screen cannot disagree about what a service is
      -- called, and nothing here can advertise a service that has no row
      -- to book against.
      SELECT s.site_service_id AS id, s.sort_order AS "sortOrder",
             cat.name_ar AS "titleAr", cat.name_en AS "titleEn",
             s.blurb_ar AS "blurbAr", s.blurb_en AS "blurbEn",
             s.icon_key AS "iconKey"
      FROM hbh.site_services s
      JOIN hbh.services cat ON cat.service_id = s.service_id AND cat.active_flg
      WHERE s.center_id = c.center_id AND s.active_flg AND s.status = 'PUBLISHED'
    ) x
  ), '[]'::jsonb),
  'programs', coalesce((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x."sortOrder", x.id) FROM (
      -- Marketing copy only. No price, no duration, no link to a bookable
      -- service: "music therapy" is in hbh.services as well, and until the
      -- owner says which list is the source of truth nothing here may
      -- promise something the booking system cannot keep.
      SELECT program_id AS id, sort_order AS "sortOrder",
             title_ar AS "titleAr", title_en AS "titleEn",
             desc_ar AS "descAr", desc_en AS "descEn",
             detail_ar AS "detailAr", detail_en AS "detailEn",
             icon_key AS "iconKey"
      FROM hbh.site_programs
      WHERE center_id = c.center_id AND active_flg AND status = 'PUBLISHED'
    ) x
  ), '[]'::jsonb),
  'reviews', coalesce((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x."sortOrder", x.id) FROM (
      -- display_name and the words. NOT guardian_id: the link between a
      -- public sentence and a family stays in the database.
      -- rating is null when nobody set one, and the site draws no stars
      -- at all rather than inheriting the five from the written card it
      -- replaced. An invented rating is a number nobody gave.
      SELECT review_id AS id, sort_order AS "sortOrder",
             display_name AS "displayName", rating,
             body_ar AS "bodyAr", body_en AS "bodyEn"
      FROM hbh.site_reviews
      WHERE center_id = c.center_id AND active_flg AND status = 'PUBLISHED'
    ) x
  ), '[]'::jsonb),
  -- The page's own words, keyed by the data-i18n attribute already on
  -- each element. A map rather than a list: there is no order here, the
  -- key IS the position.
  --
  -- ONLY PUBLISHED ROWS, like every other block - and a key with no
  -- published row is simply absent, which the page reads as "leave what
  -- is written". So a half-filled table is a page half-managed rather
  -- than a page with holes in it.
  --
  -- Ninety-seven of the page's keys are answered by the blocks above -
  -- team, programs, faq, reviews, contact - and are not in this table
  -- at all. One sentence, one source.
  'texts', coalesce((
    SELECT jsonb_object_agg(t.text_key,
             jsonb_build_object('ar', t.text_ar, 'en', t.text_en))
    FROM hbh.site_texts t
    WHERE t.center_id = c.center_id AND t.active_flg AND t.status = 'PUBLISHED'
  ), '{}'::jsonb),
  'sections', coalesce((
    SELECT jsonb_object_agg(code, visible_flg)
    FROM hbh.site_sections
    WHERE center_id = c.center_id AND active_flg
  ), '{}'::jsonb)
))
FROM hbh.centers c
WHERE c.code = :'center_code';
SQL

# The query goes in on STDIN, not through -c. psql only substitutes its
# own variables - the :'center_code' below - for input it reads as a
# script; with -c the colon reaches the parser and it is a syntax error.
body="$(printf '%s\n' "$QUERY" | docker exec -e PGPASSWORD="$DB_OWNER_PASSWORD" -i hbh-db \
  psql -v ON_ERROR_STOP=1 -U hbh_owner -d hbh -tA \
       -v center_code="$CENTER_CODE" -f - 2>&1)"
rc=$?

# Not `local out rc=$?` and not a pipeline's status: this project has
# been bitten by both. A failure has to leave with a non-zero code, or a
# deploy step publishes an empty file and reports success.
if [ $rc -ne 0 ] || [ -z "$body" ]; then
  echo "site-export: the query failed" >&2
  echo "$body" >&2
  exit 1
fi

render() {
  cat <<'HEADER'
/* =====================================================================
 * GENERATED FILE - DO NOT EDIT.
 *
 * Written by scripts/site-export.sh from the staff console's content
 * tables. Anything typed here is lost on the next export.
 *
 * It is .js and not .json so the site works when index.html is opened
 * straight off disk: fetch() fails on file://, a <script> tag does not.
 * Load it after config.js and before app.js.
 *
 * It carries PUBLISHED rows only. A draft is not here, whatever a
 * screen shows.
 * ===================================================================== */
window.HBH_SITE_CONTENT =
HEADER
  printf '%s;\n' "$body"
}

if [ $CHECK -eq 1 ]; then
  render
  exit 0
fi

render > "$OUT"
echo "site-export: wrote $OUT"

# The file has a fixed name across deployments, so a cached copy is a
# site serving the previous release's content with no error anywhere.
# config.js is already no-store in both servers; this must be too.
for f in "$ROOT/deploy/server/site.native.mjs" "$ROOT/deploy/server/hbh.nginx.conf"; do
  if ! grep -q 'content\.js' "$f"; then
    echo "site-export: WARNING - $(basename "$f") does not mention content.js." >&2
    echo "  Without a no-store rule a visitor keeps the previous export." >&2
  fi
done
