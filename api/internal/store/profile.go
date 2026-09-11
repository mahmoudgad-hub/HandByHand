// The child profile screen, in one transaction instead of six.
//
// WHY THIS EXISTS
// The screen asked for the child, its sessions, its appointments, its home
// activities, its balance and its reports as six separate requests. Measured
// on the server each is 41-144ms, and each opened its OWN transaction: a
// connection from the pool, SET LOCAL for the identity, and a visibility
// check on hbh.children - six times for one screen. Over the network it is
// worse, because six requests are six round trips, and a family on a phone
// pays for every one of them.
//
// WHAT IT DOES NOT DO
// It carries no SQL of its own. Every query below is the same function the
// single-purpose endpoint calls, so the two cannot answer differently. That
// was the whole reason for splitting them out rather than writing a second
// copy here - a copy drifts, and the endpoint that drifts is never the one
// anybody tests.
//
// The old endpoints stay. A screen that wants one thing should ask for one
// thing, and removing them would break the console and every deep link.
package store

import (
	"context"

	"github.com/handbyhand/hbh/api/internal/domain"
	"github.com/jackc/pgx/v5"
)

// ChildProfile is everything the parent's child screen renders.
type ChildProfile struct {
	Child        domain.Child           `json:"child"`
	Sessions     []domain.Session       `json:"sessions"`
	Appointments []domain.Appointment   `json:"appointments"`
	Activities   []domain.Activity      `json:"activities"`
	Balance      domain.Balance         `json:"balance"`
	Reports      []domain.ReportSummary `json:"reports"`
}

// ChildProfile reads the whole screen under one identity and one snapshot.
//
// One transaction is not only cheaper, it is more truthful: the six separate
// calls could each see a different moment, so a session could be completed
// between the sessions call and the balance call and the screen would show a
// visit that the money does not know about. Here every part is read from the
// same snapshot and the screen cannot contradict itself.
func (d *DB) ChildProfile(ctx context.Context, ident string, childID int, w Window) (ChildProfile, error) {
	var p ChildProfile
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		// childTx first, and its ErrNotFound is the whole access check:
		// a child the caller cannot see returns no row, and the handler
		// turns that into the same 404 the single endpoints give. There
		// is no separate visibility query because this one already is it.
		var err error
		if p.Child, err = childTx(ctx, tx, childID); err != nil {
			return err
		}
		if p.Sessions, err = sessionsTx(ctx, tx, childID, w); err != nil {
			return err
		}
		if p.Appointments, err = appointmentsTx(ctx, tx, childID, w); err != nil {
			return err
		}
		if p.Activities, err = activitiesTx(ctx, tx, childID); err != nil {
			return err
		}
		if p.Balance, err = balanceTx(ctx, tx, childID); err != nil {
			return err
		}
		p.Reports, err = reportsTx(ctx, tx, childID)
		return err
	})
	if err != nil {
		return ChildProfile{}, err
	}
	return p, nil
}
