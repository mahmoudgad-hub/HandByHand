-- Hand By Hand (new) - migration 0140 down: the three bodies as they were
-- on the live database immediately before 0140 (pg_get_functiondef).
-- The API maps the new codes by name, so going down leaves it mapping
-- codes nothing raises - harmless, and code-drift will say so.

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
      RAISE EXCEPTION 'an override needs a service to override the price of' USING ERRCODE = 'HB258';
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
    RAISE EXCEPTION 'service % is not this centre''s', p_service_id USING ERRCODE = 'HB260';
  END IF;

  IF p_kind NOT IN ('PACKAGE', 'SINGLE') THEN
    RAISE EXCEPTION 'unknown price kind %', p_kind USING ERRCODE = 'HB260';
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

  UPDATE hbh.guardians g SET user_id = l_uid WHERE g.guardian_id = p_guardian_id;

  RETURN QUERY SELECT l_uid, lower(l_g.mobile), l_new;
END
$function$

;

DELETE FROM hbh.schema_migrations WHERE version = '0140';
