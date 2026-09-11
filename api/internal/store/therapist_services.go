package store

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"
)

// Which services a therapist offers.
//
// WHY THIS IS NOT ONE MORE ROW IN THE CRUD TABLE. hbh.therapist_services
// is keyed on the PAIR (therapist_id, service_id) and has no surrogate id,
// so it cannot be addressed by the /api/v1/<thing>/{id} shape every other
// resource uses. Forcing it into that shape would have meant adding a
// column to the schema to satisfy a routing convention.
//
// WHY IT MATTERS AT ALL. hbh.validate_slot answers
// THERAPIST_SERVICE_MISMATCH when the pair is missing, so without a row
// here no appointment can be booked - and this endpoint did not exist,
// which meant a new centre could create its therapists, services, rooms
// and children through the API and then not book a single session. The
// console session found it by trying to.
//
// It is easy to confuse with the caseload and is a different question:
// caseload is therapist-to-CHILD and asks "may this person run this
// session"; this is therapist-to-SERVICE and asks "does this person do
// speech therapy at all". Both are required and neither implies the other.

// TherapistServices lists the services one therapist offers.
func (d *DB) TherapistServices(ctx context.Context, ident string, therapistID int) ([]json.RawMessage, error) {
	out := []json.RawMessage{}
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT jsonb_build_object(
			         'service_id', s.service_id,
			         'code',       s.code,
			         'name_ar',    s.name_ar,
			         'kind_code',  s.kind_code,
			         'color_hex',  s.color_hex,
			         'active_flg', ts.active_flg)
			FROM   hbh.therapist_services ts
			JOIN   hbh.services s ON s.service_id = ts.service_id
			WHERE  ts.therapist_id = $1
			AND    ts.active_flg
			ORDER  BY s.name_ar, s.service_id`, therapistID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var raw []byte
			if err := rows.Scan(&raw); err != nil {
				return err
			}
			out = append(out, json.RawMessage(raw))
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("therapist services: %w", err)
	}
	return out, nil
}

// AddTherapistService links a therapist to a service.
//
// It reactivates a link that was archived rather than refusing it as a
// duplicate. Removing a service from somebody and giving it back is an
// ordinary thing for a centre to do, and the alternative - a unique
// violation the caller cannot act on, because the row they collided with
// is invisible to them - is a dead end on the screen.
func (d *DB) AddTherapistService(ctx context.Context, ident string, therapistID, serviceID int) error {
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		// The therapist must be visible to this caller before anything is
		// written. The policy on hbh.therapist_services cannot check it -
		// the table carries no center_id - so the SELECT that proves it
		// runs in the SAME transaction as the write.
		var ok bool
		if err := tx.QueryRow(ctx,
			`SELECT count(*) > 0 FROM hbh.therapists
			  WHERE therapist_id = $1 AND center_id = hbh.current_center_id() AND active_flg`,
			therapistID).Scan(&ok); err != nil {
			return err
		}
		if !ok {
			return ErrNotFound
		}

		tag, err := tx.Exec(ctx, `
			UPDATE hbh.therapist_services
			   SET active_flg = true, deleted_at = NULL
			 WHERE therapist_id = $1 AND service_id = $2 AND NOT active_flg`,
			therapistID, serviceID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() > 0 {
			return nil
		}

		_, err = tx.Exec(ctx, `
			INSERT INTO hbh.therapist_services (therapist_id, service_id)
			VALUES ($1, $2)
			ON CONFLICT (therapist_id, service_id) DO NOTHING`, therapistID, serviceID)
		return err
	})
	if err != nil {
		return fmt.Errorf("add therapist service: %w", err)
	}
	return nil
}

// RemoveTherapistService archives the link. Soft, like every removal here:
// an appointment already booked refers to a pairing that once existed, and
// a hard delete would make that history unreadable.
func (d *DB) RemoveTherapistService(ctx context.Context, ident string, therapistID, serviceID int) error {
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE hbh.therapist_services ts
			   SET active_flg = false, deleted_at = now()
			 WHERE ts.therapist_id = $1 AND ts.service_id = $2 AND ts.active_flg
			 AND   EXISTS (SELECT 1 FROM hbh.therapists t
			                WHERE t.therapist_id = ts.therapist_id
			                AND   t.center_id = hbh.current_center_id())`,
			therapistID, serviceID)
		if err != nil {
			return err
		}
		// Zero rows is the answer both when there is no such link and when
		// the policy refused the update - the two are one answer here as
		// everywhere, and answering 204 for a change that did not happen
		// would be the worse of the two mistakes.
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("remove therapist service: %w", err)
	}
	return nil
}

// ServiceTherapists lists the therapists who offer one service.
//
// The same pair table read the other way round, and the direction the
// BOOKING screen needs. Without it the therapist dropdown offered everybody
// and hbh.validate_slot answered THERAPIST_SERVICE_MISMATCH afterwards - a
// refusal that arrives after the choice, about a fact the service knew
// before it was made.
//
// ACTIVE ONLY, and not as a tidying-up: validate_slot refuses a therapist
// who is not `active_flg AND status = 'ACTIVE'` with THERAPIST_UNAVAILABLE.
// Listing one here would move the same defect one name to the left.
//
// No SECURITY DEFINER and no centre argument: this runs as hbh_app with the
// caller's identity, so the policies on therapists and therapist_services
// decide what comes back, exactly as they do for every other read here.
func (d *DB) ServiceTherapists(ctx context.Context, ident string, serviceID int) ([]json.RawMessage, error) {
	out := []json.RawMessage{}
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT jsonb_build_object(
			         'therapist_id', t.therapist_id,
			         'full_name_ar', t.full_name_ar,
			         'title_ar',     t.title_ar,
			         'status',       t.status)
			FROM   hbh.therapist_services ts
			JOIN   hbh.therapists t ON t.therapist_id = ts.therapist_id
			WHERE  ts.service_id = $1
			AND    ts.active_flg
			AND    t.active_flg
			AND    t.status = 'ACTIVE'
			ORDER  BY t.full_name_ar, t.therapist_id`, serviceID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var raw []byte
			if err := rows.Scan(&raw); err != nil {
				return err
			}
			out = append(out, json.RawMessage(raw))
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("service therapists: %w", err)
	}
	return out, nil
}

// ServicePairs lists every (service, therapist) combination the centre can
// actually deliver, each with both names.
//
// ONE READ, NOT ONE PER SERVICE. The booking screen needs the whole set at
// once to offer them as a single choice, and asking per service would be a
// request per row of a dropdown - and a race, because the answers would
// arrive in whatever order the network felt like.
//
// It is the same pair table as the two reads above, and the same rules: the
// link must be active, the therapist must be active and ACTIVE, and the
// policies decide which rows this caller sees. A combination absent here is
// one hbh.validate_slot would answer THERAPIST_SERVICE_MISMATCH about.
func (d *DB) ServicePairs(ctx context.Context, ident string) ([]json.RawMessage, error) {
	out := []json.RawMessage{}
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT jsonb_build_object(
			         'service_id',     s.service_id,
			         'service_name_ar', s.name_ar,
			         'therapist_id',   t.therapist_id,
			         'therapist_name_ar', t.full_name_ar,
			         'duration_min',   s.default_duration_min)
			FROM   hbh.therapist_services ts
			JOIN   hbh.services   s ON s.service_id   = ts.service_id
			JOIN   hbh.therapists t ON t.therapist_id = ts.therapist_id
			WHERE  ts.active_flg
			AND    s.active_flg
			AND    t.active_flg
			AND    t.status = 'ACTIVE'
			ORDER  BY s.sort_order, s.name_ar, t.full_name_ar, t.therapist_id`)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var raw []byte
			if err := rows.Scan(&raw); err != nil {
				return err
			}
			out = append(out, json.RawMessage(raw))
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("service pairs: %w", err)
	}
	return out, nil
}
