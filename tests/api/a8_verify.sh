#!/usr/bin/env bash
# =====================================================================
# Hand By Hand (new) - API PHASE 8 acceptance suite
#
# Must print:  API PHASE 8 ACCEPTED
#
#   bash scripts/api.sh verify 8
#
# The centre's own settings: the parameters everything runs on, and the
# centre row itself.
#
# These endpoints shipped without a suite. The feature was built, driven
# from the browser, and proved by hand - and none of that leaves anything
# behind that fails when somebody changes it. This file is that.
#
# FIVE THINGS IT EXISTS TO HOLD DOWN, each one a decision that cannot be
# made again cheaply once it has been broken:
#
#   1. A WRITE LANDS ON THE CENTRE, NEVER ON THE GLOBAL ROW. sys_params
#      holds a global default (center_id IS NULL) and, beside it, the
#      centre's override. A write that reached the global row would move
#      the default for every centre that has not overridden it - and
#      nothing on the screen would look different.
#
#   2. A RESET IS A SOFT DELETE, and the value that comes back is the
#      global one. Rule 3 of this project: nothing is deleted. The
#      override survives, deactivated, and hbh.param() steps over it.
#
#   3. AND THE DEACTIVATED ROW MUST NOT BE READ. This is the check the
#      suite was written for. Two people - one of them the author of the
#      soft-delete rule - read a two-row result, saw "5 global, 8 for the
#      centre", concluded the centre's ceiling was 8, and never looked at
#      active_flg. It was false: the 8 had been reset hours earlier. A
#      real refusal was then documented as unreachable on the strength of
#      it. The answer is now written down here instead of being inferred
#      from the table each time somebody asks.
#
#   4. RECORDING CANNOT BE TURNED ON FROM A SCREEN. "No recording, ever"
#      is a permanent rule of this system, not a configuration, and
#      RECORDING_ENABLED exists to be documented rather than changed. It
#      answers NOT_EDITABLE and not FORBIDDEN, because no permission
#      grants it and telling an administrator otherwise sends them to ask
#      for one that would not help. STREAM_TOKEN_TTL_MIN is locked for
#      the same reason: it is a security ceiling.
#
#   5. THE PERMISSION IS ASKED FOR INSIDE THE DATABASE. The read is open
#      to anybody signed in; the write asks for SETTINGS.MANAGE inside
#      hbh.set_center_param and inside the policy on hbh.centers - never
#      in a handler. So the receptionist in the fixture is refused by the
#      schema, and the suite proves the refusal survives the API being
#      rebuilt.
#
# The harness and the five rules it enforces are in tests/api/lib.sh.
# =====================================================================

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "============== api phase 8 - the centre's settings =============="
echo "base: $API_BASE"
echo

# =====================================================================
# FIXTURE - asserted by name, before any test runs
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a8_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'previous fixture removed' 1 "$OUT"; else chk fixture 'previous fixture removed' 0; fi

OUT="$(psqlf "$ROOT/tests/fixtures/a8_fixture.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk fixture 'fixture applied' 1 "$OUT"; else chk fixture 'fixture applied' 0; fi

eq fixture 'service answers /healthz' '200' "$(req GET /healthz)"
for m in 0058 0059 0060; do
  eq fixture "migration $m is applied" 't' "$(psqlq "SELECT hbh.migration_applied('$m')")"
done

ADMIN="$(staff_login a8_admin a8-admin-pw-123456)"
RECEPTION="$(staff_login a8_reception a8-reception-pw-123456)"
ok_if fixture 'the administrator signed in' "$([ -n "$ADMIN" ] && echo 0 || echo 1)" 'no token for a8_admin'
ok_if fixture 'the receptionist signed in'  "$([ -n "$RECEPTION" ] && echo 0 || echo 1)" 'no token for a8_reception'

# The two accounts differ in exactly one thing, and the fixture asserts
# it in SQL. Restated here so a reader of the results sees what the
# refusals below are actually separating.
eq fixture 'the administrator holds SETTINGS.MANAGE' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.users u JOIN hbh.user_roles ur ON ur.user_id=u.user_id JOIN hbh.role_permissions rp ON rp.role_id=ur.role_id JOIN hbh.permissions p ON p.permission_id=rp.permission_id WHERE u.username='a8_admin' AND p.code='SETTINGS.MANAGE'")"
eq fixture 'and the receptionist does not' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.users u JOIN hbh.user_roles ur ON ur.user_id=u.user_id JOIN hbh.role_permissions rp ON rp.role_id=ur.role_id JOIN hbh.permissions p ON p.permission_id=rp.permission_id WHERE u.username='a8_reception' AND p.code='SETTINGS.MANAGE'")"

GLOBAL_FMT="$(psqlq "SELECT param_value FROM hbh.sys_params WHERE center_id IS NULL AND param_code='DATE_DISPLAY_FORMAT'")"
ok_if fixture 'the global default is known' "$([ -n "$GLOBAL_FMT" ] && echo 0 || echo 1)" 'DATE_DISPLAY_FORMAT has no global row'

# =====================================================================
# READING
#
# Open to any signed-in caller and to nobody else. A screen listing its
# own centre's values confirms nothing a person could not infer from the
# application working - but an ANONYMOUS reader is a different question,
# and the answer is the one the identity rule demands: no identity, no
# rows. Not "the public ones".
# =====================================================================
eq read 'an anonymous caller reads nothing' '401' "$(req GET /api/v1/settings/params)"
eq read 'and is told why' 'UNAUTHENTICATED' "$(jstr "$BODY" code)"

eq read 'the administrator reads the list' '200' "$(req GET /api/v1/settings/params '' "$ADMIN")"
ok_if read 'and it is not empty' "$([ "$(jnum "$BODY" total)" -gt 20 ] && echo 0 || echo 1)" \
  "only $(jnum "$BODY" total) parameters"
eq read 'every row carries its default'  "$(jnum "$BODY" total)" "$(jcount "$BODY" defaultValue)"
eq read 'and whether it was overridden'  "$(jnum "$BODY" total)" "$(jcount "$BODY" overridden)"

# The receptionist may READ. The two halves of this endpoint pair are
# not the same gate, and a suite that only ever reads as an
# administrator would not notice the day the read started asking for
# SETTINGS.MANAGE too.
eq read 'a caller without SETTINGS.MANAGE may still read' '200' \
  "$(req GET /api/v1/settings/params '' "$RECEPTION")"

# =====================================================================
# WRITING
#
# DATE_DISPLAY_FORMAT is the parameter that moves here, and the choice
# is deliberate: nothing in the schema computes with it. Moving an OTP
# window or an attachment ceiling would change what a suite running
# beside this one in the same database is being refused for.
# =====================================================================
eq write 'a caller without the permission is refused' '403' \
  "$(req PATCH /api/v1/settings/params/DATE_DISPLAY_FORMAT '{"value":"YYYY-MM-DD"}' "$RECEPTION")"
eq write 'and told it is a permission' 'FORBIDDEN' "$(jstr "$BODY" code)"
eq write 'nothing was written' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.sys_params WHERE center_id IS NOT NULL AND param_code='DATE_DISPLAY_FORMAT'")"

eq write 'the administrator writes it' '200' \
  "$(req PATCH /api/v1/settings/params/DATE_DISPLAY_FORMAT '{"value":"YYYY-MM-DD"}' "$ADMIN")"
eq write 'and the reply is the value now in force' 'YYYY-MM-DD' "$(jstr "$BODY" value)"

# THE POINT OF THE ENDPOINT. One row was created, for this centre, and
# the global row did not move.
eq write 'a CENTRE override was created' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.sys_params WHERE center_id=(SELECT center_id FROM hbh.centers WHERE code='HBH') AND param_code='DATE_DISPLAY_FORMAT' AND active_flg")"
eq write 'and the global default did NOT move' "$GLOBAL_FMT" \
  "$(psqlq "SELECT param_value FROM hbh.sys_params WHERE center_id IS NULL AND param_code='DATE_DISPLAY_FORMAT'")"
eq write 'the resolver now answers the override' 'YYYY-MM-DD' \
  "$(psqlq "SELECT hbh.param((SELECT center_id FROM hbh.centers WHERE code='HBH'),'DATE_DISPLAY_FORMAT','x')")"
eq write 'and the screen is told it is overridden' 'true' \
  "$(req GET /api/v1/settings/params '' "$ADMIN" >/dev/null; sed -n 's/.*"code":"DATE_DISPLAY_FORMAT"[^}]*"overridden":\(true\|false\).*/\1/p' "$BODY" | head -1)"

# A second write moves the same row rather than making another. The
# unique key is (center_id, param_code) with NULLS NOT DISTINCT, and a
# duplicate override is a value that depends on which row is read first.
eq write 'writing again moves the same row' '200' \
  "$(req PATCH /api/v1/settings/params/DATE_DISPLAY_FORMAT '{"value":"DD-MM-YYYY"}' "$ADMIN")"
eq write 'still exactly one override' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.sys_params WHERE center_id IS NOT NULL AND param_code='DATE_DISPLAY_FORMAT'")"

# The audit trigger on the table wrote the change. Nothing is recorded
# by the handler on purpose - a second line would have to file a write
# under LOGIN, DENY or READ, which are the only headings audit_attempt
# accepts.
ok_if write 'the change is in the audit trail' \
  "$([ "$(psqlq "SELECT count(*) FROM hbh.v_audit_trail WHERE table_name='sys_params' AND changed_at > now() - interval '5 minutes'")" -gt 0 ] && echo 0 || echo 1)" \
  'no audit row for the parameter write'

# =====================================================================
# WHAT MAY NOT BE WRITTEN
# =====================================================================
eq locked 'an unknown parameter is not there' '404' \
  "$(req PATCH /api/v1/settings/params/NO_SUCH_PARAM '{"value":"1"}' "$ADMIN")"
eq locked 'and says so' 'NOT_FOUND' "$(jstr "$BODY" code)"

# RECORDING IS THE ONE THAT MATTERS. "Live only, never recorded" is a
# permanent rule of this system; the parameter exists so the answer is
# written down, not so it can be changed.
eq locked 'recording cannot be switched on' '409' \
  "$(req PATCH /api/v1/settings/params/RECORDING_ENABLED '{"value":"true"}' "$ADMIN")"
eq locked 'and it is NOT called a permission problem' 'NOT_EDITABLE' "$(jstr "$BODY" code)"
eq locked 'recording is still off' 'false' \
  "$(psqlq "SELECT hbh.param((SELECT center_id FROM hbh.centers WHERE code='HBH'),'RECORDING_ENABLED','MISSING')")"

eq locked 'the stream token ceiling is locked too' '409' \
  "$(req PATCH /api/v1/settings/params/STREAM_TOKEN_TTL_MIN '{"value":"600"}' "$ADMIN")"
eq locked 'and it did not move' '15' \
  "$(psqlq "SELECT hbh.param((SELECT center_id FROM hbh.centers WHERE code='HBH'),'STREAM_TOKEN_TTL_MIN','MISSING')")"

# The declared type is enforced by the database, not by the screen.
eq locked 'a NUMBER will not take a word' '400' \
  "$(req PATCH /api/v1/settings/params/INVOICE_DUE_DAYS '{"value":"lots"}' "$ADMIN")"
eq locked 'and nothing was written for it' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.sys_params WHERE center_id IS NOT NULL AND param_code='INVOICE_DUE_DAYS' AND active_flg")"

# =====================================================================
# RESETTING - and the deactivated row
#
# THIS GROUP IS WHY THE SUITE EXISTS. See the header, point 3.
# =====================================================================
eq reset 'a caller without the permission may not reset' '403' \
  "$(req DELETE /api/v1/settings/params/DATE_DISPLAY_FORMAT '' "$RECEPTION")"
eq reset 'and the override is still in force' 'DD-MM-YYYY' \
  "$(psqlq "SELECT hbh.param((SELECT center_id FROM hbh.centers WHERE code='HBH'),'DATE_DISPLAY_FORMAT','x')")"

eq reset 'the administrator resets it' '200' \
  "$(req DELETE /api/v1/settings/params/DATE_DISPLAY_FORMAT '' "$ADMIN")"

# The reply is the number, not an empty 204. The screen has just told
# somebody a value is about to change and the answer is what it changed
# to - which is the whole reason this route answers with a body.
eq reset 'and answers with the value now in force' "$GLOBAL_FMT" "$(jstr "$BODY" value)"

# RULE 3. The row is not gone.
eq reset 'the override row SURVIVES' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.sys_params WHERE center_id IS NOT NULL AND param_code='DATE_DISPLAY_FORMAT'")"
eq reset 'deactivated, not deleted' 'f' \
  "$(psqlq "SELECT active_flg FROM hbh.sys_params WHERE center_id IS NOT NULL AND param_code='DATE_DISPLAY_FORMAT'")"
eq reset 'and stamped with when' 't' \
  "$(psqlq "SELECT deleted_at IS NOT NULL FROM hbh.sys_params WHERE center_id IS NOT NULL AND param_code='DATE_DISPLAY_FORMAT'")"
eq reset 'it even keeps the value it held' 'DD-MM-YYYY' \
  "$(psqlq "SELECT param_value FROM hbh.sys_params WHERE center_id IS NOT NULL AND param_code='DATE_DISPLAY_FORMAT'")"

# AND THE DEACTIVATED ROW IS NOT READ. The row above still says
# DD-MM-YYYY. Anybody reading the table without looking at active_flg
# would conclude that is the centre's format. It is not, and these two
# checks are the written answer.
eq reset 'the resolver steps over it' "$GLOBAL_FMT" \
  "$(psqlq "SELECT hbh.param((SELECT center_id FROM hbh.centers WHERE code='HBH'),'DATE_DISPLAY_FORMAT','x')")"
eq reset 'and the screen shows it as no longer overridden' 'false' \
  "$(req GET /api/v1/settings/params '' "$ADMIN" >/dev/null; sed -n 's/.*"code":"DATE_DISPLAY_FORMAT"[^}]*"overridden":\(true\|false\).*/\1/p' "$BODY" | head -1)"
eq reset 'the list shows the global value' "$GLOBAL_FMT" \
  "$(req GET /api/v1/settings/params '' "$ADMIN" >/dev/null; sed -n 's/.*"code":"DATE_DISPLAY_FORMAT","value":"\([^"]*\)".*/\1/p' "$BODY" | head -1)"

# Resetting what is already reset is not an error. The person asked for
# the default and the default is what they have.
eq reset 'resetting twice is not an error' '200' \
  "$(req DELETE /api/v1/settings/params/DATE_DISPLAY_FORMAT '' "$ADMIN")"
eq reset 'and still answers the default' "$GLOBAL_FMT" "$(jstr "$BODY" value)"
eq reset 'resetting an unknown parameter is a 404' '404' \
  "$(req DELETE /api/v1/settings/params/NO_SUCH_PARAM '' "$ADMIN")"

# =====================================================================
# THE CENTRE'S OWN ROW
#
# Three gates in three places, and the handler asks none of them: a
# column GRANT, the RLS policy, and a BEFORE trigger. The refusals below
# arrive in three different shapes for that reason.
# =====================================================================
eq center 'the currency is frozen once money exists' '409' \
  "$(req PATCH /api/v1/settings/center '{"currency_code":"USD"}' "$ADMIN")"
eq center 'and says which rule' 'CURRENCY_LOCKED' "$(jstr "$BODY" code)"
eq center 'the currency did not move' 'EGP' \
  "$(psqlq "SELECT currency_code FROM hbh.centers WHERE code='HBH'")"

# The code is the centre's identity outside this database - the seeds
# and the site exporter match on it - and it has no grant at all, so it
# is not even a field the request may carry.
eq center 'the centre code is not a field' '400' \
  "$(req PATCH /api/v1/settings/center '{"code":"OTHER"}' "$ADMIN")"
eq center 'and the code did not move' '1' \
  "$(psqlq "SELECT count(*) FROM hbh.centers WHERE code='HBH'")"

# 0059 ADDED THIS ONE AFTER A REAL 500. time.LoadLocation resolves the
# centre's zone on every centre-indexed read, so "Cairo" instead of
# "Africa/Cairo" took out the appointments and sessions screens - a
# typo in a settings field, and two screens down with a server error.
eq center 'a zone the engine does not know is refused' '400' \
  "$(req PATCH /api/v1/settings/center '{"time_zone":"Cairo"}' "$ADMIN")"
eq center 'and names the field' 'time_zone' "$(jstr "$BODY" field)"
eq center 'the zone did not move' 'Africa/Cairo' \
  "$(psqlq "SELECT time_zone FROM hbh.centers WHERE code='HBH'")"
eq center 'a zone it does know is accepted' '204' \
  "$(req PATCH /api/v1/settings/center '{"time_zone":"Africa/Cairo"}' "$ADMIN")"

# character(2): the TYPE refuses this before any CHECK does, so there is
# no constraint name to translate. It reached the client as a 500 until
# 22001 was added to the schema-refusal family.
eq center 'an over-long country code is a refusal, not a crash' '400' \
  "$(req PATCH /api/v1/settings/center '{"country_code":"EGY"}' "$ADMIN")"
eq center 'and names that field'   'country_code' "$(jstr "$BODY" field)"

eq center 'a request that changes nothing is refused' '400' \
  "$(req PATCH /api/v1/settings/center '{}' "$ADMIN")"

# The policy asks for SETTINGS.MANAGE inside itself, so a caller without
# it matches NO ROW rather than raising - which arrives as 404. The
# check counts the row afterwards rather than trusting the status: a
# zero-row UPDATE reports success at the SQL level, and that is the
# shape a refusal takes once a write grant exists.
eq center 'a caller without the permission is refused' '404' \
  "$(req PATCH /api/v1/settings/center '{"name_ar":"اسم من الاستقبال"}' "$RECEPTION")"
eq center 'and the name did not move' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.centers WHERE code='HBH' AND name_ar LIKE '%الاستقبال%'")"
eq center 'an anonymous caller gets no further' '401' \
  "$(req PATCH /api/v1/settings/center '{"name_ar":"مجهول"}')"

# =====================================================================
# THE TIME ZONE LIST
# =====================================================================
eq zones 'the picker has a list' '200' "$(req GET /api/v1/settings/time-zones '' "$ADMIN")"
ok_if zones 'and it is the engine tzdata, not a hand-written handful' \
  "$([ "$(jnum "$BODY" total)" -gt 400 ] && echo 0 || echo 1)" \
  "only $(jnum "$BODY" total) zones"
eq zones 'the one this centre runs on is in it' 'yes' \
  "$(grep -q '"Africa/Cairo"' "$BODY" && echo yes || echo no)"
eq zones 'every zone carries its offset' "$(jnum "$BODY" total)" "$(jcount "$BODY" offsetMinutes)"
eq zones 'an anonymous caller reads nothing' '401' "$(req GET /api/v1/settings/time-zones)"

# =====================================================================
# THE DOOR ITSELF
#
# Every rule above is in the database, and these two checks are what
# makes that statement mean something: the role the API connects as
# cannot write the table at all, so there is no second path in that
# skips set_center_param and its three questions.
# =====================================================================
eq door 'the app role has no write grant on sys_params' '0' \
  "$(psqlq "SELECT count(*) FROM information_schema.role_table_grants WHERE grantee='hbh_app' AND table_schema='hbh' AND table_name='sys_params' AND privilege_type IN ('INSERT','UPDATE','DELETE')")"
eq door 'and no DELETE grant on the centre either' '0' \
  "$(psqlq "SELECT count(*) FROM information_schema.role_table_grants WHERE grantee='hbh_app' AND table_schema='hbh' AND table_name='centers' AND privilege_type='DELETE'")"
eq door 'an anonymous connection reads no parameter' '0' \
  "$(psqlapp "SELECT count(*) FROM hbh.sys_params")"

# =====================================================================
# CLEANUP - a recorded check like any other
# =====================================================================
OUT="$(psqlf "$ROOT/tests/fixtures/a8_teardown.sql")"
RC=$?
if [ "$RC" != "0" ]; then chk cleanup 'fixture removed' 1 "$OUT"; else chk cleanup 'fixture removed' 0; fi
eq cleanup 'no override survived the run' '0' \
  "$(psqlq "SELECT count(*) FROM hbh.sys_params WHERE center_id IS NOT NULL AND param_code='DATE_DISPLAY_FORMAT'")"
eq cleanup 'and the global default is where it started' "$GLOBAL_FMT" \
  "$(psqlq "SELECT param_value FROM hbh.sys_params WHERE center_id IS NULL AND param_code='DATE_DISPLAY_FORMAT'")"

verdict 'API PHASE 8'
