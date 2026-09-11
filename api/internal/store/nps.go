package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/handbyhand/hbh/api/internal/domain"
	"github.com/jackc/pgx/v5"
)

// The satisfaction survey.
//
// Everything about WHEN a question appears - which audience, after how many
// days, after which action, and how long before it may be asked again - is a
// row in hbh.nps_surveys, not a condition in this file and not a condition in
// Angular. That is rule 2 applied to something that looks too small to need
// it: a cooldown written in the client is a cooldown that differs per browser
// and cannot be changed by the person who owns the question.

// NPSDue returns the question to ask this caller now, or nil.
//
// nil is the ordinary answer and not an error. hbh.nps_due() returns zero rows
// for a caller with no identity, for one whose cooldown has not elapsed, and
// for a centre with no live survey - and a screen that treats "nothing to ask"
// as a failure would show an error box on every page load.
func (d *DB) NPSDue(ctx context.Context, ident string) (*domain.NPSPrompt, error) {
	var p domain.NPSPrompt
	var kind *string

	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT survey_id, code, question_ar, followup_question_ar, context_kind, context_id
			FROM   hbh.nps_due()`).
			Scan(&p.SurveyID, &p.Code, &p.QuestionAr, &p.FollowupQuestionAr, &kind, &p.ContextID)
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, fmt.Errorf("nps due: %w", err)
	}
	p.ContextKind = deref(kind)
	return &p, nil
}

// NPSAnswer is what the family said.
//
// Comment is optional and Score is not: a survey answered with prose and no
// number cannot be counted, and the point of this instrument is the number.
// Context must be echoed back exactly as nps_due gave it, or the cooldown is
// recorded against the wrong thing and the question returns tomorrow.
type NPSAnswer struct {
	Score       *int   `json:"score"`
	CommentAr   string `json:"comment_ar"`
	ContextKind string `json:"context_kind"`
	ContextID   *int   `json:"context_id"`
}

// SubmitNPS records a score. HB093 if the score is outside 0..10.
func (d *DB) SubmitNPS(ctx context.Context, ident string, surveyID int, a NPSAnswer, clientIP *string) (int64, error) {
	var id int64
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT hbh.submit_nps($1, $2::smallint, nullif($3, ''), nullif($4, ''), $5, $6::inet)`,
			surveyID, a.Score, a.CommentAr, a.ContextKind, a.ContextID, clientIP).Scan(&id)
	})
	if err != nil {
		return 0, fmt.Errorf("submit nps: %w", err)
	}
	return id, nil
}

// SkipNPS records a dismissal.
//
// A dismissal is an ANSWER, which is why it is stored rather than ignored.
// Without it the cooldown never starts and the same question reappears on
// every page load - so the client that shows the prompt must call this when
// the family closes it, and a screen that quietly drops the dismissal turns a
// polite question into a nag.
func (d *DB) SkipNPS(ctx context.Context, ident string, surveyID int, kind string, contextID *int) (int64, error) {
	var id int64
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT hbh.skip_nps($1, nullif($2, ''), $3)`, surveyID, kind, contextID).Scan(&id)
	})
	if err != nil {
		return 0, fmt.Errorf("skip nps: %w", err)
	}
	return id, nil
}

// NPSSummary returns hbh.v_nps_summary, one row per survey.
//
// The view carries BOTH nps and mean_score, and they are different numbers
// that look like the same one: in the database's own acceptance run nps is 25
// while the mean is 7.25. The screen shows nps. The mean is here because
// hiding it invites somebody to compute their own from the counts, which is
// how the two quietly become three.
func (d *DB) NPSSummary(ctx context.Context, ident string) ([]json.RawMessage, error) {
	return d.viewRows(ctx, ident, `hbh.v_nps_summary`, `survey_id`)
}

// viewRows reads a whole reporting view as JSON.
//
// to_jsonb renders each type the way Postgres already knows how - a date as
// "2020-03-15", a numeric as an exact value - and a reporting view has no
// field a screen must be protected from, unlike a table row. The view name and
// the ordering come from THIS FILE and never from a request.
func (d *DB) viewRows(ctx context.Context, ident, view, order string) ([]json.RawMessage, error) {
	out := []json.RawMessage{}
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, fmt.Sprintf(`SELECT to_jsonb(v) FROM %s v ORDER BY %s`, view, order))
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
		return nil, fmt.Errorf("read %s: %w", view, err)
	}
	return out, nil
}

// NPSMonthly aggregates authorized responses by calendar month in Cairo.
func (d *DB) NPSMonthly(ctx context.Context, ident string) ([]json.RawMessage, error) {
	return d.viewRows(ctx, ident, `(SELECT to_char(date_trunc('month', r.responded_at AT TIME ZONE 'Africa/Cairo'), 'YYYY-MM') AS month, round(avg(r.score),2) AS mean_score, count(*) AS answered_cnt FROM hbh.nps_responses r JOIN hbh.nps_surveys s ON s.survey_id = r.survey_id WHERE r.active_flg AND NOT r.skipped_flg AND r.score IS NOT NULL AND r.responded_at >= date_trunc('month', now()) - interval '6 months' GROUP BY 1)`, `month`)
}

func (d *DB) DashboardMetrics(ctx context.Context, ident string) ([]json.RawMessage, error) {
	return d.viewRows(ctx, ident, `(SELECT
(SELECT jsonb_build_object('attended',count(*) FILTER(WHERE status IN ('CHECKED_IN','COMPLETED')), 'absent',count(*) FILTER(WHERE status='NO_SHOW'), 'total',count(*)) FROM hbh.appointments WHERE active_flg AND status IN ('CHECKED_IN','COMPLETED','NO_SHOW') AND starts_at >= date_trunc('month',now()) AND starts_at <= now() AND hbh.has_permission('APPOINTMENT.BOOK')) AS attendance,
(SELECT CASE WHEN hbh.has_permission('ENROLMENT.MANAGE') THEN count(*) ELSE NULL END FROM hbh.enrolment_applications WHERE active_flg AND created_at >= date_trunc('month',now())) AS leads,
(SELECT jsonb_build_object('mean',avg(score)/2.0,'count',count(*)) FROM hbh.nps_responses WHERE active_flg AND NOT skipped_flg AND hbh.has_permission('NPS.MANAGE')) AS satisfaction,
(SELECT coalesce(jsonb_agg(b),'[]'::jsonb) FROM (SELECT currency_code, sum(outstanding_amt)::text AS amount,sum(open_invoice_cnt) AS invoices FROM hbh.v_child_balance WHERE hbh.has_permission('BILLING.VIEW') GROUP BY currency_code) b) AS outstanding
)`, `1`)
}
