package store

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

// Notification is one item in a person's feed.
//
// IT CARRIES NO CLINICAL TEXT AND THAT IS ENFORCED UPSTREAM, not here: 0089's
// header states the rule and every notify_* function obeys it - the title says
// a thing happened and the link says where to look. What this struct does is
// refuse to invent anything the database did not say, which is why LinkKind
// and LinkID are pointers rather than empty strings and zeroes.
type Notification struct {
	ID        int64      `json:"notification_id"`
	Kind      string     `json:"kind_code"`
	Title     string     `json:"title_ar"`
	Body      *string    `json:"body_ar"`
	ChildID   *int       `json:"child_id"`
	ChildName *string    `json:"child_name"`
	LinkKind  *string    `json:"link_kind"`
	LinkID    *int       `json:"link_id"`
	CreatedAt time.Time  `json:"created_at"`
	ReadAt    *time.Time `json:"read_at"`
}

// NotificationPage is a page of the feed plus the count the badge needs.
//
// UNREAD IS COUNTED OVER THE WHOLE FEED, not over the page. A badge showing
// "3" because that is how many unread items fitted on the first page is a
// badge that lies as soon as somebody has four.
type NotificationPage struct {
	Rows   []Notification `json:"rows"`
	Unread int            `json:"unread"`
	Total  int            `json:"total"`
}

// Notifications reads the caller's own feed.
//
// THERE IS NO user_id ARGUMENT AND THERE MUST NOT BE. The policy p_ntf_select
// is `user_id = hbh.current_user_id()`, so this query returns the caller's
// rows and nobody else's - including for a member of staff who can see the
// child the notification is about, because a notification is addressed to a
// PERSON. A parameter here would be a second copy of that rule and the weaker
// of the two would decide; worse, it would be a parameter an attacker can
// change. See P9's inbox group, which has been asserting this since 0015.
//
// The child's name is joined rather than stored on the notification: a family
// with two children needs to know which one a report is about, and copying the
// name into the row would leave it stale the day a name is corrected.
func (d *DB) Notifications(ctx context.Context, ident string, limit, offset int) (NotificationPage, error) {
	var page NotificationPage
	page.Rows = []Notification{}

	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		// Two aggregates in one statement, over the same snapshot, so the
		// badge and the list cannot disagree by a row that arrived between
		// two queries.
		if err := tx.QueryRow(ctx,
			`SELECT count(*), count(*) FILTER (WHERE n.read_at IS NULL)
			   FROM hbh.notifications n`).Scan(&page.Total, &page.Unread); err != nil {
			return err
		}

		rows, err := tx.Query(ctx,
			`SELECT n.notification_id, n.kind_code, n.title_ar, n.body_ar,
			        n.child_id, c.full_name_ar,
			        n.link_kind, n.link_id, n.created_at, n.read_at
			   FROM hbh.notifications n
			   LEFT JOIN hbh.children c ON c.child_id = n.child_id
			  ORDER BY n.created_at DESC, n.notification_id DESC
			  LIMIT $1 OFFSET $2`, limit, offset)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var n Notification
			if err := rows.Scan(&n.ID, &n.Kind, &n.Title, &n.Body,
				&n.ChildID, &n.ChildName, &n.LinkKind, &n.LinkID,
				&n.CreatedAt, &n.ReadAt); err != nil {
				return err
			}
			page.Rows = append(page.Rows, n)
		}
		return rows.Err()
	})
	if err != nil {
		return NotificationPage{}, fmt.Errorf("notifications: %w", err)
	}
	return page, nil
}

// MarkNotificationRead marks one of the caller's own notifications read.
//
// A false return means "not yours, or already read, or does not exist", and
// the three are deliberately the same answer - for the reason ErrNotFound
// carries in db.go. hbh.mark_notification_read puts
// `user_id = hbh.current_user_id()` in the WHERE clause, so the enforcement is
// the statement rather than a check this layer could forget.
func (d *DB) MarkNotificationRead(ctx context.Context, ident string, id int64) (bool, error) {
	var ok bool
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `SELECT hbh.mark_notification_read($1)`, id).Scan(&ok)
	})
	if err != nil {
		return false, fmt.Errorf("mark_notification_read: %w", err)
	}
	return ok, nil
}
