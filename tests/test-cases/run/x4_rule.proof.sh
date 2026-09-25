#!/usr/bin/env bash
# Does Z-31 bite?
#
#   bash tests/test-cases/run/x4_rule.proof.sh
#
# Z-31 is the whole point of X4: it reads the audit trail and fails if
# hbh_owner wrote any row of the family path. It was green on its first
# run - and a guard that has only ever been seen to pass has not been
# seen. Worse, THIS one is green when it is broken: a query that errors,
# a table that stopped being audited, a changed_by that starts saying
# 'hbh_app' - each of those makes the count zero, which reads as "no
# owner wrote anything".
#
# So both directions, on a row made and rolled back inside one
# transaction. Nothing here is left behind, and nothing product-owned is
# touched: the probe writes its own child row as the owner - exactly the
# shortcut Z-31 exists to catch - asks the question Z-31 asks, and rolls
# back.
set -uo pipefail
cd "$(dirname "$0")/../../.."
. tests/api/lib.sh

TMP_SQL="$TMP/x4_rule_probe.sql"
cat > "$TMP_SQL" <<'PROBE'
\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('hbh.user_id', 'hbh_owner', false);

-- The shortcut: a child written straight in, as the owner, the way every
-- other fixture in this project makes one.
INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
SELECT c.center_id, b.branch_id, 'X4-PROOF', 'طفل الإثبات', DATE '2020-01-01', 'M'
FROM   hbh.centers c JOIN hbh.branches b ON b.center_id = c.center_id
WHERE  c.code = 'HBH' AND b.code = 'MAIN';

-- The question Z-31 asks, on that row, with row_pk compared AS TEXT.
SELECT 'OWNER_INSERTS=' || count(*)
FROM   hbh.v_audit_trail
WHERE  changed_by = 'hbh_owner' AND action = 'INSERT' AND table_name = 'children'
  AND  row_pk = (SELECT child_id::text FROM hbh.children WHERE child_no = 'X4-PROOF');

-- And the other half: the trail saw the row at all. If this is zero the
-- count above is zero for a reason that has nothing to do with the rule.
SELECT 'ANY_INSERTS=' || count(*)
FROM   hbh.v_audit_trail
WHERE  action = 'INSERT' AND table_name = 'children'
  AND  row_pk = (SELECT child_id::text FROM hbh.children WHERE child_no = 'X4-PROOF');

ROLLBACK;
PROBE

OUT="$(psqlf "$TMP_SQL" 2>&1)"
OWNER="$(printf '%s' "$OUT" | sed -n 's/.*OWNER_INSERTS=\([0-9]*\).*/\1/p' | head -1)"
ANY="$(printf '%s' "$OUT" | sed -n 's/.*ANY_INSERTS=\([0-9]*\).*/\1/p' | head -1)"

chk proof 'the probe ran'                    "$([ -n "$OWNER" ] && echo 0 || echo 1)" "$(printf '%s' "$OUT" | tail -3)"
chk proof 'the trail recorded the owner row' "$([ "${ANY:-0}"   -ge 1 ] && echo 0 || echo 1)" "audited inserts: ${ANY:-0}"
chk proof 'and Z-31 SEES it as the owner'    "$([ "${OWNER:-0}" -ge 1 ] && echo 0 || echo 1)" \
   "owner inserts seen: ${OWNER:-0} - Z-31 would have passed over an owner-written row"

# Nothing was kept: the probe rolled back, and this asks the database
# rather than trusting the ROLLBACK to have been reached.
eq proof 'and nothing was left behind' '0' \
   "$(psqlq "SELECT count(*) FROM hbh.children WHERE child_no = 'X4-PROOF'")"

verdict 'X4 RULE PROOF'
