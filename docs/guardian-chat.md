# Guardian conversations

Applied to local development on 2026-09-14 (migration 0147).

The guardian portal offers reception, therapist and centre manager recipient
pickers. The conversation list contains only eligible contacts with actual
message history. Other guardians and the legacy family directory are omitted.
Searching history does not narrow the new-recipient picker.

The database enforces the same recipient scope on discovery, reading and sending
through `can_chat` and the existing direct-message RLS policies. Reception and
manager accounts require active RECEPTION/CENTER_ADMIN roles in the same centre.
Therapists require an active caseload assignment to an active child linked to the
guardian; assignment dates use the centre's timezone. An ended assignment removes
that therapist's conversation access in both directions. Existing messages are
retained. Staff-to-staff messaging is unchanged.

Selecting several recipients sends independent private messages, not a shared
group. Per-recipient request UUIDs preserve idempotence. A partial failure retries
only failed recipients. Guardians cannot use the staff-wide broadcast endpoint.

Validation: transactional `tests/db/guardian_chat_scope.sql` covers discovery,
direct insertion denial, private reads, reply direction, expired assignments and
unknown identity. Seven shared chat unit tests pass, including bulk retry and
role/history separation; the API Docker build runs Go vet and all unit tests.
The development portal was checked with dev_parent: all three role buttons,
history-only list and the assigned specialist chooser render correctly. Test
messages were either HTTP mocks or rolled-back SQL; none were sent to real users.
