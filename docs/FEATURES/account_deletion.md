# Account deletion backend lifecycle

## Scope and deletion policy

Vilvia persists an authenticated account-deletion request before any destructive
work. PostgreSQL and Supabase Auth cannot share a transaction, so fulfillment is
a trusted, manually invoked operator workflow rather than an API request or a
background worker.

Deletion is destructive. Fulfillment removes:

- the Supabase Auth identity;
- the Profile and all its personal/profile fields;
- every Post authored by the Profile;
- every Comment authored by the Profile;
- every Post reaction created by the Profile; and
- every Report created by the Profile.

Existing database cascades also remove Comments, reactions, and Reports beneath
a deleted Post, plus Reports targeting a deleted Comment. A deleted Post can
therefore remove replies written by other users. Vilvia does not create an
anonymous/tombstone user and does not retain authored Posts or Comments.

Admin-created Events are retained. Their existing `created_by` foreign key uses
`ON DELETE SET NULL`, so Profile deletion severs ownership without invalidating
the Event. Resources are not user-owned and are unchanged. Report status and
target visibility are unchanged for surviving content.

## In-app request flow

Signed-in users can open Account from the home header, review the destructive
deletion policy, and explicitly confirm before the app sends
`POST /me/account-deletion-request`. The app supplies no user ID or policy
fields. After any valid `202` lifecycle response (`requested`, `auth_deleted`,
or `completed`) establishes durable acceptance, the app signs that same user
out locally through `AuthService`. Fulfillment remains asynchronous and may not
complete immediately.

An external HTTPS deletion-request resource remains a separate release
requirement. The resource is available at `/deletion-request` and provides a
standalone web interface for users to verify their identity and request
destructive deletion without opening the app. Play Console configuration and
HTTPS deployment of the API domain are required for this resource to be public.
Play Console configuration is out of scope for this issue, so this
in-app flow alone must not be described as completing Google Play compliance.

## Request API and mutation block

`POST /me/account-deletion-request` requires a verified user token, accepts no
body, and returns `202` with only `status` and `requested_at`. Its PostgreSQL
`INSERT ... ON CONFLICT ... RETURNING` is committed once, so retries return the
existing lifecycle instead of creating duplicate requests. It never returns or
logs the account email.

Once any deletion-request row exists, Profile bootstrap and authenticated
mutations are rejected with generic `409 Account deletion has been requested.`
This covers Community writes and all admin writes through `require_admin`.
Public/authenticated reads remain available while fulfillment is pending.

Request creation and every authenticated mutation also take the same
transaction-scoped PostgreSQL advisory lock derived from the user UUID. This
causes request creation to wait for an earlier in-flight write, while a later
write waits for the request commit and then observes the block. The advisory
lock must always be acquired before domain row locks. The global authenticated
mutation hierarchy is therefore account advisory barrier → Post → Comment →
Report. Any future authenticated mutation must perform the account-state check
and acquire this barrier before locking or changing domain rows.

This database block is important after Supabase deletion: FastAPI verifies JWTs
locally, so an access token issued before deletion can remain cryptographically
valid until its expiry. The retained request prevents that token from recreating
a Profile or writing new owned data.

## Durable lifecycle

`account_deletion_requests.user_id` is the Supabase/Profile UUID but deliberately
has no Profile foreign key, allowing the recovery record to outlive Profile
deletion. It stores no email, name, content, token, or error text.

Valid states are enforced with a database check constraint:

1. `requested`: the request is durable; Supabase deletion is not yet recorded.
2. `auth_deleted`: Supabase returned success or confirmed the identity was
   already absent; PostgreSQL cleanup still needs to complete.
3. `completed`: Supabase deletion was recorded and PostgreSQL cleanup committed.

The two transaction boundaries are intentional:

1. The command locks the request, deletes the Supabase Auth identity, records
   `auth_deleted`, and commits.
2. It locks the request again, performs all PostgreSQL cleanup and counter
   repairs, sets `completed`, and commits them atomically.

If Supabase succeeds but recording `auth_deleted` fails, a retry calls the
idempotent Supabase deletion again; an already-absent identity is success. If
PostgreSQL cleanup fails, its transaction rolls back and the durable state stays
`auth_deleted`. A retry skips Supabase and repeats all idempotent cleanup. A
request already at `completed` performs no destructive work.

## PostgreSQL cleanup and counters

Cleanup discovers all affected targets, then locks rows deterministically in
the existing Community order: Posts by UUID, Comments by UUID, then Reports by
UUID. Comment creation remains serialized by its parent Post lock. It deletes
created Reports before the Profile because `reported_by` is `ON DELETE
RESTRICT`; target cascades handle data below content being deleted.

For surviving locked Posts, the command recounts reactions, visible Comments,
and direct Reports from their source tables. For surviving Comments, it recounts
direct Reports. The recounts and Profile/content deletion commit together, so a
failed PostgreSQL transaction cannot persist partial data or counters.

## Operator procedure

Run from `backend/` in a trusted environment:

```bash
SUPABASE_SERVICE_ROLE_KEY=<secret> python scripts/fulfill_account_deletions.py USER_UUID
```

The service-role key is needed only by this operator command. Never ship it to
Flutter, expose it through an API, print it, or commit it. The command prints no
email, token, deleted value, Supabase response body, or user UUID. A failure
leaves the lifecycle at its last committed retry point and exits non-zero with a
generic message. Inspect the row's state, correct the infrastructure/config
problem, and run the same command with the same UUID again.

After success, confirm the state is `completed`; do not infer completion merely
from the Supabase identity being absent or the Profile being missing.

## Completed-record retention

A completed row temporarily retains only the user UUID and lifecycle timestamps
to block pre-deletion JWTs and support operational recovery. The default
retention is seven days (`ACCOUNT_DELETION_COMPLETED_RETENTION_DAYS`). Configure
`SUPABASE_ACCESS_TOKEN_MAX_LIFETIME_SECONDS` to the maximum access-token
lifetime in the actual Supabase Auth project and
`SUPABASE_JWT_CLOCK_SKEW_SECONDS` to Vilvia's deployment allowance. Backend
startup fails unless completed retention covers the maximum lifetime plus
twice the skew: once because `iat` may be accepted in the future and once
because `exp` may be accepted in the past. The purge operation independently
enforces the same invariant before deleting any row.
JWT verification requires `iat` and `exp`, applies the configured skew, and
rejects tokens whose `exp - iat` exceeds the configured maximum.

Expired completed rows must be purged operationally:

```bash
python scripts/fulfill_account_deletions.py --purge-completed
```

Successful fulfillment also performs this purge. With no worker infrastructure,
the operator/deployment runbook must invoke the purge regularly even during
periods with no new deletion requests; otherwise completed identifiers would be
retained beyond the documented window. Database/Supabase backups and platform
logs have separate deployment retention policies and must be disclosed based on
the real production configuration.
