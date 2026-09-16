-- =====================================================================
-- Hand By Hand (new) - migration 0140: one code, one meaning - the
-- owner's split of HB258 and HB260, and the shared phone refused by name
--
-- THE API WENT FIRST. Every SQLSTATE this file starts raising was mapped
-- by name in the running service before the file was placed here
-- (image 613bec8a, 2026-09-12): HB261 409 MOBILE_HELD_BY_GUARDIAN,
-- HB262 422 VALIDATION, HB264 400 VALIDATION. HB258 and HB260 keep their
-- codes and lose their second meanings.
--
-- ---------------------------------------------------------------------
-- THE OWNER'S DECISION (2026-09-12)
--
-- HB258 was raised for a missing BILLING.PRICE_OVERRIDE AND for an
-- override on a line with no service. HB260 was raised for a missing
-- BILLING.PRICE_EDIT, for another centre's service, AND for an unknown
-- price kind. A screen acts on those differently - ask for a grant, pick
-- a service, fix the input - so one code for several answers drops all
-- but one of them silently.
--
--   add_invoice_line   override on a free-text line      HB258 -> HB262
--   set_service_price  unknown price kind                HB260 -> HB264
--   set_service_price  another centre's service          HB260 -> HB051
--
-- The last one is NOT a new code, on purpose. A distinct answer for "this
-- service exists, in another centre" confirms the id is real. HB051 with
-- the words add_invoice_line already uses ('no such service %') makes a
-- foreign id and an id that never existed indistinguishable - measured,
-- in a rolled-back transaction with a second centre, before this file
-- was written. HB263 was proposed for it and is withdrawn; nothing
-- raises it and nothing maps it.
--
-- ---------------------------------------------------------------------
-- OD-26 / EN-09 - the branch 0137 deliberately did not carry
--
-- Two guardians may share a phone. grant_portal_access on the second one
-- found the first one's account by mobile, skipped the HB204 check (which
-- only runs when NO guardian account exists), and tried to link a second
-- guardian to it - dying on uix_guardians_user as a raw 23505 at the
-- UPDATE, rendered by the API as "this value is already in use". It is
-- now refused by name before the UPDATE, as HB261.
--
-- ALL THREE BODIES were taken from pg_get_functiondef on the live
-- database, and checked unchanged against it immediately before this
-- file was written - never rebuilt from the migration that first created
-- them, which would drop what later migrations added.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0140') THEN
    RAISE EXCEPTION 'migration 0140 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0139') THEN
    RAISE EXCEPTION 'migration 0139 must be applied first';
  END IF;
  -- The collision guard every migration since 0130 carries: a code this
  -- file introduces must not already mean something else.
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'hbh' AND p.prosrc ~ 'HB26[1-4]') THEN
    RAISE EXCEPTION 'a live function already raises HB261-HB264 - renumber before applying';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION hbh.add_invoice_line(p_invoice_id integer, p_description_ar text, p_qty numeric DEFAULT 1, p_unit_amt numeric DEFAULT 0, p_service_id integer DEFAULT NULL::integer, p_sort_order integer DEFAULT NULL::integer, p_override_reason text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'hbh', 'pg_catalog'
AS $function$
DECLARE
  l_inv    hbh.invoices%ROWTYPE;
  l_id     integer;
  l_list   numeric;
  l_unit   numeric;
  l_reason text := nullif(btrim(coalesce(p_override_reason, '')), '');
  l_strict boolean;
BEGIN
  -- Everything the old body did, in the order it did it.
  IF NOT hbh.has_permission('BILLING.MANAGE') THEN
    RAISE EXCEPTION 'changing an invoice needs BILLING.MANAGE' USING ERRCODE = 'HB052';
  END IF;

  SELECT * INTO l_inv FROM hbh.invoices
   WHERE invoice_id = p_invoice_id
     AND center_id = hbh.current_center_id()
     AND active_flg
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such invoice %', p_invoice_id USING ERRCODE = 'HB051';
  END IF;

  IF l_inv.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'invoice % is % - its amounts can no longer change', p_invoice_id, l_inv.status
      USING ERRCODE = 'HB050';
  END IF;

  -- NEW: the service is this centre's, before a price is read from it.
  IF p_service_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM hbh.services s
                     WHERE s.service_id = p_service_id AND s.center_id = l_inv.center_id) THEN
    RAISE EXCEPTION 'no such service %', p_service_id USING ERRCODE = 'HB051';
  END IF;

  IF p_service_id IS NOT NULL THEN
    l_list := hbh.current_price(p_service_id, 'SINGLE');
  END IF;

  IF l_reason IS NOT NULL THEN
    -- An explicit override. New capability; nothing calls it yet.
    IF NOT hbh.has_permission('BILLING.PRICE_OVERRIDE') THEN
      RAISE EXCEPTION 'overriding a price needs BILLING.PRICE_OVERRIDE' USING ERRCODE = 'HB258';
    END IF;
    IF p_service_id IS NULL THEN
      -- A free-text line has no catalogue price to override; its amount
      -- is already whatever the caller says.
      RAISE EXCEPTION 'an override needs a service to override the price of' USING ERRCODE = 'HB262';
    END IF;
    l_unit := p_unit_amt;
  ELSIF p_service_id IS NOT NULL THEN
    l_strict := hbh.param(l_inv.center_id, 'INVOICE_REQUIRE_CATALOGUE_PRICE', 'false')::boolean;
    IF l_strict THEN
      IF l_list IS NULL THEN
        RAISE EXCEPTION 'service % has no current price', p_service_id USING ERRCODE = 'HB257';
      END IF;
      l_unit := l_list;
    ELSE
      -- Today's behaviour, unchanged - with the catalogue price now
      -- written beside it.
      l_unit := p_unit_amt;
    END IF;
  ELSE
    l_unit := p_unit_amt;   -- a free-text line, as always
  END IF;

  INSERT INTO hbh.invoice_lines (center_id, invoice_id, description_ar, service_id,
                                 qty, unit_amt, line_amt, sort_order,
                                 list_amt, override_reason_ar)
  VALUES (l_inv.center_id, p_invoice_id, p_description_ar, p_service_id,
          p_qty, l_unit, round(p_qty * l_unit, 2),
          coalesce(p_sort_order,
                   (SELECT coalesce(max(sort_order), 0) + 10 FROM hbh.invoice_lines
                     WHERE invoice_id = p_invoice_id)),
          l_list, l_reason)
  RETURNING line_id INTO l_id;

  PERFORM hbh.recalc_invoice(p_invoice_id);
  RETURN l_id;
END
$function$

;

CREATE OR REPLACE FUNCTION hbh.set_service_price(p_service_id integer, p_kind text, p_amount numeric, p_effective_from timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'hbh', 'pg_catalog'
AS $function$
DECLARE
  l_center   integer := hbh.current_center_id();
  l_svc      hbh.services%ROWTYPE;
  l_currency text;
  l_next     timestamptz;
  l_id       integer;
BEGIN
  IF l_center IS NULL OR NOT hbh.has_permission('BILLING.PRICE_EDIT') THEN
    RAISE EXCEPTION 'editing a price needs BILLING.PRICE_EDIT' USING ERRCODE = 'HB260';
  END IF;

  -- Read the row, is it mine, then act.
  SELECT * INTO l_svc FROM hbh.services s
  WHERE s.service_id = p_service_id AND s.center_id = l_center AND s.active_flg;
  IF NOT FOUND THEN
    -- Another centre's service is answered exactly like one that does not
    -- exist: same code, same words. HB051 is what add_invoice_line gives a
    -- foreign service too; a distinct code here would confirm the id is real.
    RAISE EXCEPTION 'no such service %', p_service_id USING ERRCODE = 'HB051';
  END IF;

  IF p_kind NOT IN ('PACKAGE', 'SINGLE') THEN
    RAISE EXCEPTION 'unknown price kind %', p_kind USING ERRCODE = 'HB264';
  END IF;

  SELECT c.currency_code INTO l_currency FROM hbh.centers c WHERE c.center_id = l_center;

  -- A price already scheduled AFTER this one bounds it, so setting a
  -- price between two others does not overlap the later one.
  SELECT min(sp.effective_from) INTO l_next
  FROM   hbh.service_prices sp
  WHERE  sp.service_id = p_service_id AND sp.price_kind = p_kind AND sp.active_flg
    AND  sp.effective_from > p_effective_from;

  -- And the price in force at that instant ends where this one begins.
  -- History is kept - the old row is closed, not rewritten, so an
  -- invoice issued under it still reads back the price it was issued at.
  UPDATE hbh.service_prices sp
     SET effective_to = p_effective_from
   WHERE sp.service_id = p_service_id AND sp.price_kind = p_kind AND sp.active_flg
     AND sp.effective_from < p_effective_from
     AND (sp.effective_to IS NULL OR sp.effective_to > p_effective_from);

  INSERT INTO hbh.service_prices (center_id, service_id, price_kind, amount, currency_code,
                                  effective_from, effective_to)
  VALUES (l_center, p_service_id, p_kind, p_amount, l_currency, p_effective_from, l_next)
  RETURNING price_id INTO l_id;

  RETURN l_id;
END
$function$

;

CREATE OR REPLACE FUNCTION hbh.grant_portal_access(p_guardian_id integer)
 RETURNS TABLE(user_id integer, username text, created boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'hbh', 'pg_catalog'
AS $function$
DECLARE
  l_center integer := hbh.current_center_id();
  l_g      hbh.guardians%ROWTYPE;
  l_uid    integer;
  l_new    boolean := false;
  l_other  text;
BEGIN
  IF l_center IS NULL OR NOT hbh.has_permission('GUARDIAN.MANAGE') THEN
    RAISE EXCEPTION 'granting portal access needs GUARDIAN.MANAGE' USING ERRCODE = 'HB200';
  END IF;

  -- FOR UPDATE: two receptionists clicking the same button on the same
  -- family must not produce two accounts. The partial unique index on
  -- guardians.user_id is the backstop; this is the lock that means the
  -- backstop is never reached.
  SELECT * INTO l_g FROM hbh.guardians g
  WHERE  g.guardian_id = p_guardian_id AND g.center_id = l_center AND g.active_flg
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such guardian % in this centre', p_guardian_id USING ERRCODE = 'HB201';
  END IF;

  -- Already has one. Calling again is not an error - reception cannot
  -- tell from the screen whether the last click landed, and a function
  -- that punishes the second click teaches people to avoid the first.
  IF l_g.user_id IS NOT NULL THEN
    RETURN QUERY
      SELECT u.user_id, u.username, false FROM hbh.users u WHERE u.user_id = l_g.user_id;
    RETURN;
  END IF;

  -- No mobile check. guardians.mobile is NOT NULL and must match
  -- '^[0-9+]{6,20}$', so there is no such guardian to guard against.
  -- (0085 raised HB202 here; a later migration removed it with that
  -- reason written in. The first draft of THIS file restored it from
  -- 0085's text, which would have put back a guard its author had
  -- deliberately taken out. Rebuild from pg_get_functiondef, never
  -- from the migration that first created a function.)

  -- An account on this mobile may already exist - the same person can
  -- have been a guardian in another capacity, or a previous record was
  -- linked and unlinked. request_otp looks families up BY MOBILE and
  -- takes the lowest user_id, so minting a second account on the same
  -- number creates a login that silently resolves to the wrong one.
  -- Link the existing account rather than add a rival to it.
  SELECT u.user_id INTO l_uid
  FROM   hbh.users u
  WHERE  u.mobile = l_g.mobile AND u.center_id = l_center AND u.active_flg
    AND  u.user_type = 'GUARDIAN'
  ORDER  BY u.user_id
  LIMIT  1;

  IF l_uid IS NULL THEN
    -- NEW IN 0126. The lookup above is narrowed to GUARDIAN, so an
    -- account of any other type on this number falls through it and
    -- into the insert, where the index refuses with a bare 23505.
    -- Asked here instead, the answer can say what is in the way.
    --
    -- The type is named and the username is NOT: the caller already
    -- knows the mobile they typed, and which member of staff owns it
    -- is not something a refusal needs to disclose to answer the
    -- question "why can this family not be given a login".
    SELECT u.user_type INTO l_other
    FROM   hbh.users u
    WHERE  u.mobile = l_g.mobile AND u.active_flg
    ORDER  BY u.user_id
    LIMIT  1;

    IF l_other IS NOT NULL THEN
      RAISE EXCEPTION
        'the mobile of guardian % already belongs to a % account, not a guardian',
        p_guardian_id, l_other
        USING ERRCODE = 'HB204',
              HINT = 'one person in two capacities needs two numbers - the centre decides the second';
    END IF;

    INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar,
                           user_type, mobile, status)
    VALUES (l_center, l_g.branch_id, lower(l_g.mobile), l_g.full_name_ar,
            'GUARDIAN', l_g.mobile, 'ACTIVE')
    RETURNING hbh.users.user_id INTO l_uid;

    l_new := true;

    -- Without the role the account exists and can sign in and sees
    -- nothing, which reads to the family as a broken portal rather than
    -- a missing grant.
    INSERT INTO hbh.user_roles (user_id, role_id)
    SELECT l_uid, r.role_id FROM hbh.roles r
    WHERE  r.code = 'GUARDIAN' AND r.center_id = l_center
    ON CONFLICT DO NOTHING;
  END IF;

  -- OD-26 / EN-09. A shared phone is legitimate, and the account found
  -- on this number may already belong to ANOTHER guardian - the one who
  -- signs in on it. Linking a second guardian to it died here on
  -- uix_guardians_user as a raw 23505, which the API rendered as
  -- "this value is already in use": the defect 0126 repaired for staff,
  -- reached by a branch 0126 never ran, because the HB204 check only
  -- fires when NO guardian account exists. Refused by name instead.
  IF EXISTS (SELECT 1 FROM hbh.guardians o
             WHERE o.user_id = l_uid AND o.guardian_id <> p_guardian_id
               AND o.active_flg) THEN
    RAISE EXCEPTION 'the mobile of guardian % is the portal account of another guardian', p_guardian_id
      USING ERRCODE = 'HB261',
            HINT = 'a guardian sharing a phone signs in through the account holder, or is given a mobile of their own';
  END IF;

  UPDATE hbh.guardians g SET user_id = l_uid WHERE g.guardian_id = p_guardian_id;

  RETURN QUERY SELECT l_uid, lower(l_g.mobile), l_new;
END
$function$

;

-- =====================================================================
-- THE PROOF - on the bodies, by name. The behaviour was proved in
-- rolled-back transactions before this file existed; what can go wrong
-- HERE is a body that did not land as written.
-- =====================================================================
DO $verify$
DECLARE
  l_ail text; l_ssp text; l_gpa text;
BEGIN
  SELECT prosrc INTO l_ail FROM pg_proc WHERE oid = 'hbh.add_invoice_line(integer,text,numeric,numeric,integer,integer,text)'::regprocedure;
  SELECT prosrc INTO l_ssp FROM pg_proc WHERE oid = 'hbh.set_service_price(integer,text,numeric,timestamptz)'::regprocedure;
  SELECT prosrc INTO l_gpa FROM pg_proc WHERE oid = 'hbh.grant_portal_access(integer)'::regprocedure;

  IF (SELECT count(*) FROM regexp_matches(l_ail, 'HB258', 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(l_ail, 'HB262', 'g')) <> 1 THEN
    RAISE EXCEPTION 'add_invoice_line: HB258 must be the permission refusal alone, and HB262 the override without a service';
  END IF;

  IF (SELECT count(*) FROM regexp_matches(l_ssp, 'HB260', 'g')) <> 1
     OR l_ssp !~ 'HB264' OR l_ssp !~ 'HB051' THEN
    RAISE EXCEPTION 'set_service_price: HB260 must be the permission refusal alone, with HB051 and HB264 beside it';
  END IF;
  IF l_ssp ~ 'not this centre' THEN
    RAISE EXCEPTION 'set_service_price still words a foreign service differently from a missing one';
  END IF;

  IF l_gpa !~ 'HB261' OR l_gpa !~ 'HB204' THEN
    RAISE EXCEPTION 'grant_portal_access: HB261 must land beside HB204, not instead of it';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'hbh' AND p.prosrc ~ 'HB263') THEN
    RAISE EXCEPTION 'HB263 is withdrawn - nothing may raise it';
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0140');
