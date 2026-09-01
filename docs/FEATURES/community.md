# Community

## Purpose

The community is the heart of Vilvia.

Its purpose is to connect parents who are going through similar experiences, allowing them to ask questions, share personal experiences, support one another, and build meaningful connections during early parenthood.

Reliable information supports the community, while the community brings that information to life through real experiences.

---

## MVP Requirements

### Community Access

- Public community discussions can be viewed without an account.
- An account is required to create posts, comments, reactions, and reports.
- Creating posts, comments, and reactions requires an account.

### Feed and Post Creation

The Community screen displays published posts from the public `GET /posts`
endpoint, newest first. It handles loading, empty, and error states and allows
a failed request to be retried. Browsing does not require authentication.

Authenticated users can create posts with a title, body, and supported
category. `POST /posts` derives ownership and author display data from the
verified user's server-side Profile; clients cannot set ownership, publication
state, counters, or other internal fields. A user without a matching Profile
receives `409 Conflict` and can retry without losing their form content.

Posts are published immediately (`is_published = true`) in the current MVP.
After creation the client refreshes the Community feed so the post is visible
right away. Moderation or a review-before-publication workflow may be introduced
later as a separate feature.

### Comments

Anyone can read the oldest-first comments for a published post through
`GET /posts/{post_id}/comments`. The Community feed opens comments in a modal
bottom sheet; no post-detail route is required. Missing and unpublished posts
both return `404 Not Found`, so unpublished content is not disclosed.

Signed-in users with a server-side Profile can add a plain-text comment through
`POST /posts/{post_id}/comments`. Ownership and author display data come only
from the verified identity and matching Profile. The body is limited to
1-2000 characters, and all internal fields are rejected. Comment creation and
the Post's denormalized `comment_count` increment occur in one transaction
while the published Post row is locked, preventing lost increments from
concurrent submissions. The response includes the new comment and authoritative
count so the sheet and feed remain consistent immediately.

### Reactions

Anyone can see each published Post's reaction count. `GET /posts` reports
`has_reacted = false` to anonymous callers and, when a valid bearer token is
supplied, the verified caller's actual reaction state. Supplied invalid
credentials are rejected rather than treated as anonymous.

Signed-in users with a server-side Profile add or remove their one reaction
through idempotent `PUT /posts/{post_id}/reaction` and
`DELETE /posts/{post_id}/reaction`. Ownership comes only from the verified
identity. A composite primary key on `(post_id, profile_id)` prevents duplicate
reactions. Every mutation locks the published Post, changes the normalized
`post_reactions` row, recounts those rows, stores the exact denormalized
`reaction_count`, and commits once. The response returns the authoritative
reaction state and count used by the client.

### Reporting

Signed-in users with a server-side Profile can report a published Post through
`PUT /posts/{post_id}/report` or a Comment belonging to a published Post through
`PUT /posts/{post_id}/comments/{comment_id}/report`. The client supplies only a
trimmed reason of 1-500 characters; reporter identity, pending status, target
ownership, and internal counters are assigned server-side. Signed-out users can
continue browsing but are not shown reporting controls.

Reports reference either a Post or Comment with explicit foreign keys, and a
database check requires exactly one target. A Profile may report a given target
only once. Repeating the same `PUT` updates that Report's reason without creating
a duplicate or changing its status. Each mutation locks the target, recounts
the normalized Report rows, and stores the exact internal `report_count` in one
transaction. Report counts are not exposed in public feed or comment schemas.

Issue #104 adds an administrator-only triage queue. `GET /reports` defaults to
pending reports, supports any defined Report status as a filter, uses bounded
`limit` (1-100) and `offset` (0-10,000) pagination, and orders by
`created_at DESC, id DESC`. Responses
contain the reason, state, timestamps, API-derived target kind/ID, and live safe
content context. Post context is ID/title/body; Comment context is ID/body plus
its parent Post ID/title. Reporter identity, email, private Profile fields, and
internal report counters are never returned.
Reports whose target relationships are internally inconsistent are logged and
omitted from list responses rather than exposing malformed data or failing the
entire queue. A status update with unavailable target context returns `409`
before any status mutation is attempted.

`PUT /reports/{report_id}/status` accepts only a resulting `reviewed` or
`dismissed` decision for a pending report. Repeating the same terminal decision
is idempotent; every other transition returns `409`. Status decisions lock the
target hierarchy before the Report row where supported by the database.

`PUT /reports/{report_id}/target-visibility` accepts a strict Boolean
`is_hidden` value and lets an administrator reversibly hide or restore the live
Post or Comment target. Admin responses expose that one visibility flag while
retaining the existing safe context, including for hidden targets. Moderation
visibility, Report status, and Post publication remain independent. Hiding a
Comment atomically recounts only visible Comments into its parent Post's
`comment_count`; repeating the requested visibility is idempotent. Public feeds,
comment lists, comment creation, reactions, and reporting use the same 404
non-disclosure behavior for hidden targets, and public schemas never expose the
visibility field. Both mutations consistently lock `Post -> Report` for a Post
target or `Post -> Comment -> Report` for a Comment target, revalidate the
Report after locking, and roll back visibility and counters together on failure.

All Report endpoints use `require_admin` and separate report-specific admin
read/write rate-limit scopes. Flutter shows Hide/Restore per Report and uses the
authoritative response while preserving its stale-request protections. It shows the Reports
entry point only after a fresh server-backed Profile check and fails closed on
sign-out, account changes, missing Profiles, stale requests, and request errors.
Event reporting remains intentionally unimplemented.

Editing or deleting posts/comments, reactions on comments, replies, moderation
notifications, post details, and public-feed pagination are not part of this
implementation.

### User Interactions

Users can:

- Create posts
- Comment on posts
- React to posts
- Report inappropriate content
- Save posts

### Community Guidelines

The community is intended for parenting-related discussions only.

Posts should focus on topics such as:

- Parenting experiences
- Questions and advice
- Child development
- Family life
- Local recommendations
- Parent meetups and activities

Content unrelated to parenting is outside the scope of the community.

### Medical Discussions

Parents are welcome to share their own experiences.

However, personal experiences should not be treated as professional medical advice.

When discussions involve health or medical topics, users should be encouraged to refer to the Information section, which is based on trusted official sources.

---

## Future Considerations

Future versions may include:

- Private messaging
- Groups
- Events
- AI-assisted moderation
- AI suggestions linking discussions to trusted information
- Reputation system
- Personalized community content based on the user's parenting stage
