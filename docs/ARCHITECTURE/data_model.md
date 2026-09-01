# PostgreSQL Data Model

## Purpose

This document describes the initial PostgreSQL data model for Vilvia.

The goal is to design a simple, scalable, and maintainable database structure that supports the MVP while allowing future features to be added without major structural changes.

---

## Tables

The initial PostgreSQL schema uses separate tables for the main product areas.

This keeps shared data separate from profile data and makes it easier to query community posts and trusted resources.

Initial tables:

- `profiles`
- `resources`
- `events`
- `posts`
- `comments`
- `reports`

---

## `profiles`

The `profiles` table stores account-related data and personalization settings.

Each profile row is linked to the authenticated user using the Supabase Auth user ID.

Example path:

```text
profiles
```

Example fields:

```text
firstName: string
email: string
role: enum
gender: enum | null
childStage: enum | null
pregnancyWeek: number | null
createdAt: timestamp
updatedAt: timestamp
```

Notes:

- Authentication is handled by Supabase Auth; the backend verifies Supabase-issued access tokens directly against the project's public JWT signing keys (no service-role key needed) rather than trusting any client-supplied identity.
- A profile row is not created automatically just by authenticating. It is provisioned explicitly via `POST /me/bootstrap` (idempotent, id/email from the verified token, first name and gender from the request body, `role` always `parent`) — see `docs/FEATURES/authentication.md`.
- `role` (`parent`/`admin`, authorization) and `gender` (`male`/`female`, a profile attribute) are deliberately separate columns/enums. `gender` must never be used to gate access, and `role` must never be inferred from it.
- `gender` is nullable at the schema level for migration compatibility (existing rows predate the column and are not backfilled with a fabricated value), but is a *required* field on `POST /me/bootstrap` for new profiles — see `docs/FEATURES/authentication.md` for the full migration-compatibility rationale.
- The profiles table stores only the profile and personalization data needed by the app.
- Profile rows should remain small and focused.
- Shared data such as posts and resources should not be stored in the profiles table.

---

## `resources`

The `resources` table stores trusted parenting resources used in the Information section.

Resources are separate from community posts because they are reviewed, structured, and based on trusted official sources.

Example path:

```text
resources
```

Example fields:

```text
title: string
summary: string
body: string
category: enum
stage: enum
sourceName: string
sourceUrl: string
isPublished: boolean
createdAt: timestamp
updatedAt: timestamp
```

Notes:

- Resources should be available without requiring an account.
- Vilvia-authored/editorial resources should be reviewed before publication.
  Resources synced from an explicitly approved trusted provider (e.g.
  MedlinePlus) may auto-publish (`isPublished: true`) as long as
  `sourceName`/`sourceUrl` attribution is preserved — see
  `docs/FEATURES/parenting_information.md`.
- Community discussions may later link to related resources.
- AI-assisted features should rely on trusted resources rather than user-generated content.

---

## `events`

The `events` table stores upcoming events and meetups relevant to parents and families, shown in the Events section.

Example path:

```text
events
```

Example fields:

```text
title: string
description: string
location: string
startsAt: timestamp (timezone-aware)
endsAt: timestamp (timezone-aware) | null
createdBy: uuid (references profiles.id) | null
isPublished: boolean
createdAt: timestamp
updatedAt: timestamp
```

Notes:

- Events should be available without requiring an account.
- `startsAt` and `endsAt` are timezone-aware timestamps (stored as `timestamptz`), not naive dates or display strings, so filtering and ordering stay correct regardless of server or client timezone.
- The normal events list only returns published events whose `startsAt` is still in the future (`startsAt >= now`), ordered soonest first. Past events are not returned by this endpoint.
- Vilvia-authored/editorial events should be reviewed before publication, the same as resources — see `docs/FEATURES/events.md`.
- `createdBy` is optional ownership information only — a real foreign key to `profiles.id` with `ON DELETE SET NULL`, so a community event survives if its creator's profile is later deleted. `createdBy` being `null` means only "no creator is recorded"; it is **not** an official-vs-user-created discriminator (a community event can legitimately end up with `createdBy: null` this same way). An explicit origin/type distinction, if one becomes necessary, belongs in its own field, added when a real product requirement needs it. `createdBy` is not currently exposed via `GET /events`.
- Creating an Event and publishing it are separate operations: `POST /events` (admin-only, via `require_admin`) sets `createdBy` to the authenticated admin's own profile id server-side and always sets `isPublished` to `false` — a client cannot set either field itself. `POST /events/{event_id}/publish` (admin-only, no request body) sets `isPublished` to `true`; it is idempotent for an already-published, still-upcoming Event, and rejected with `409` (leaving the row untouched) for an Event whose `startsAt` has already passed. No new column or migration was needed for this — `isPublished` already existed. See `docs/FEATURES/events.md`.

---

## `posts`

The `posts` table stores community posts created by users.

Posts are stored as a separate table so the community feed can be queried efficiently without reading data from the profiles table.

Example path:

```text
posts
```

Example fields:

```text
authorId: string
authorName: string
authorAvatarUrl: string | null
title: string
body: string
category: enum
relatedResourceId: string | null
reactionCount: number
commentCount: number
reportCount: number
isPublished: boolean
createdAt: timestamp
updatedAt: timestamp
```

Notes:

- `authorId` is a required foreign key to `profiles.id`, linking the post to the user who created it.
- Normal Profile deletion is restricted while authored Posts exist. The explicit
  account-deletion workflow first deletes every authored Post; its existing
  cascades also delete the Post's Comments, reactions, and Reports.
- `authorName` and `authorAvatarUrl` are intentionally duplicated to improve feed performance.
- Community posts are user-generated content and should not be treated as trusted official information.
- This duplication is intentional to reduce joins when displaying the community feed.
- Posts may later link to trusted resources through `relatedResourceId`.

---

## `post_reactions`

`post_reactions` is the source of truth for reactions on community posts.

Example fields:

```text
postId: string
profileId: string
createdAt: timestamp
```

Notes:

- `(postId, profileId)` is the composite primary key, guaranteeing at most one
  reaction per user per post.
- Both foreign keys use `ON DELETE CASCADE`, because a reaction has no lifecycle
  without its Post or owning Profile.
- `posts.reactionCount` is a denormalized display counter. Supported mutations
  lock the Post row and recalculate it from `post_reactions` in the same
  transaction.

---

## `comments`

The `comments` table stores comments made on community posts.

Comments are stored as a separate table to simplify moderation, reporting, and future features while keeping queries efficient.

Posts and Comments each store a non-nullable `is_hidden` moderation flag with a
database default of `false`, keeping pre-existing content visible during
migration. The flag is independent of Post publication and Report workflow
status. It is internal to public APIs; only the administrator Report response
exposes the current target visibility.

Example path:

```text
comments
```

Example fields:

```text
postId: string
authorId: string
authorName: string
authorAvatarUrl: string | null
body: string
reactionCount: number
reportCount: number
createdAt: timestamp
updatedAt: timestamp
```

Notes:

- `postId` is a required foreign key to `posts.id`. Deleting a post cascades to its comments because comments have no independent lifecycle without their parent post.
- `authorId` is a required foreign key to `profiles.id`. The explicit
  account-deletion workflow deletes authored Comments before deleting the
  Profile; no anonymous author is substituted.
- `authorName` and `authorAvatarUrl` are intentionally duplicated to improve read performance.
- Comments are user-generated content and should not be treated as trusted information.
- Comments may be reported for moderation.

---

## `reports`

The `reports` table stores user reports for content that may require moderation.

Reports are stored as a separate table so moderators can review all reported items from a single place.

Example path:

```text
reports
```

Example fields:

```text
postId: string | null
commentId: string | null
reportedBy: string
reason: string
status: enum
createdAt: timestamp
updatedAt: timestamp
```

Notes:

- Exactly one of `postId` or `commentId` is required by a database check.
- Both targets use explicit foreign keys with `ON DELETE CASCADE`, so reports
  cannot outlive their content.
- `reportedBy` references `profiles.id` with `ON DELETE RESTRICT`.
- Unique reporter/target constraints allow one report per Profile per Post or
  Comment. A repeated API request updates the existing reason idempotently.
- `status` may include values such as `pending`, `reviewed`, or `dismissed`.
- Post and Comment `reportCount` values are internal denormalized caches that
  are recalculated from Report rows transactionally and are not public API
  fields.
- Keeping reports in a separate table makes future moderation tools easier to build.
- Report submission and admin triage are implemented. `targetKind` is derived
  by the API from the existing mutually exclusive Post/Comment foreign keys;
  it is not stored as a polymorphic discriminator. Reviewed and dismissed are
  terminal triage states. Triage changes only the Report status and never the
  target content. No content snapshots or reporter/Profile details are exposed.

---

## `account_deletion_requests`

This table is the minimal durable recovery record for deletion spanning
Supabase Auth and PostgreSQL. `userId` is the Supabase/Profile UUID but is not a
foreign key, because the request must survive Profile deletion temporarily.
The row contains only `status`, `requestedAt`, `authDeletedAt`, `completedAt`,
and `updatedAt`; it never stores email, profile fields, content, tokens, or
error text. A check constraint permits only the timestamp combination valid
for `requested`, `auth_deleted`, or `completed`.

Completed rows are retained only for the configured short JWT/recovery window
and then purged by the operator command. See
`docs/FEATURES/account_deletion.md` for deletion policy, transaction boundaries,
counter repair, and operational recovery.

Developer invariant: every authenticated mutation acquires its user account
advisory barrier before any domain row lock. Community mutations then retain
the global Post → Comment → Report hierarchy. New write endpoints must preserve
that ordering so account-deletion request races cannot introduce reverse lock
paths.

---

## Design Decisions

- Use separate tables for shared data. 
- Keep profile rows focused on profile and personalization.
- Duplicate selected user fields in posts and comments to improve read performance.
- Keep trusted resources separate from user-generated content.
- Store reports separately to support future moderation tools.
- Design the data model to support future features without major structural changes.

---

## Future Considerations

The data model is intentionally simple for the MVP and is expected to evolve as new features are introduced.
