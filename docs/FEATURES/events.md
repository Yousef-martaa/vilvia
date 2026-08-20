# Events

## Purpose

Help parents and families discover — and eventually create — events and meetups relevant to early parenthood.

Unlike Resources, Events is a community/product feature, not primarily trusted external content. Events will have two valid origins, living in the same Event domain/model:

1. **User-created community events** — registered Vilvia users creating and hosting their own events.
2. **Vilvia/admin-curated official events** — real events happening in Sweden, curated by the Vilvia team.

Both origins are first-class; neither is a fallback for the other. Issue #63 established the Events list/API/UI foundation, Issue #65 added an optional ownership column at the domain/DB layer, Issue #75 added admin-authored event *creation*, and Issue #77 added the explicit review/publish step. Event attendance and the user-created-event content pipeline are still not implemented end to end.

### Creating an Event and publishing it are separate operations

`POST /events` (admin-only) creates a **draft** Event: `is_published` is always set to `False` server-side and is not accepted from the request body. A created Event does not appear in `GET /events` (which only returns `is_published = True` rows) until an admin explicitly publishes it via `POST /events/{event_id}/publish` (admin-only, no request body). Publishing is:

- **Idempotent** for an already-published, still-upcoming Event — calling it again succeeds (`200`) without further effect, rather than erroring.
- **Rejected with `409`** for an Event whose `starts_at` has already passed (checked with a timezone-aware comparison against the current UTC time), and the Event is left untouched. `GET /events` would never show a past Event anyway (it also filters `starts_at >= now()`), so a "successful" publish that could never become visible would just be a confusing dead end for the admin reviewing drafts.
- **`404`** for a nonexistent Event id.

`GET /events/drafts` (admin-only) lists every unpublished Event, newest-created first, so an admin has somewhere to review drafts before publishing — deliberately unfiltered by `starts_at` (unlike `GET /events`), so a past-dated draft is still visible there even though it can no longer be published.

## MVP Scope

### Content Access

- Upcoming events are available without creating an account.
- Users can browse all upcoming events freely.

## What Is Implemented Now

- An Events screen listing published, upcoming events, soonest first.
- Each event shows its title, date and time, location, and a short description.
- Loading, empty, and error/retry states.
- A `GET /events` endpoint on Vilvia's own API, returning only published events whose start time is still in the future.
- An "Explore Events" entry point on Home, alongside the existing Explore Resources entry point.
- A database-level ownership foundation: `Event.created_by`, an optional (nullable) foreign key to `profiles.id` with `ON DELETE SET NULL`, reusing the existing Profile/user architecture rather than a parallel creator model. `created_by` is still not exposed via `GET /events`'s response.
- A `POST /events` endpoint, gated by the existing `require_admin` dependency (`app/api/deps.py`; 401 unauthenticated, 403 non-admin/no-profile). Accepts only `title`, `description`, `location`, `starts_at`, and an optional `ends_at` (rejects `ends_at <= starts_at` with `422`); the request schema uses `extra="forbid"`, so `id`, `created_by`, `is_published`, `role`, or any other field is rejected with `422` rather than silently dropped. `created_by` is always the calling admin's own Profile id, resolved server-side from the verified identity — never client input. `is_published` is always set to `False` server-side (see "Creating an Event and publishing it are separate operations" above). Returns `201` with the same `EventResponse` shape as `GET /events` (`created_by` and `is_published` are not exposed).
- A `GET /events/drafts` endpoint and a `POST /events/{event_id}/publish` endpoint (both admin-only, `require_admin`) — see "Creating an Event and publishing it are separate operations" above for their exact behavior.
- Admin-only "New Event" and "Drafts" entry points on the Events screen (`lib/features/events/presentation/screens/events_screen.dart`), shown only when the caller's own `Profile` (freshly read from `GET /me` each time, never cached) has `role == UserRole.admin`; hidden for signed-out users, non-admins, and if the Profile fetch fails, and re-evaluated live on every auth-state change. "New Event" opens `CreateEventScreen` (title, description, location, start, optional end), which calls `POST /events` and, on success, explicitly tells the admin the Event was created as a draft and is not yet publicly visible. "Drafts" opens `DraftEventsScreen`, which lists unpublished Events (`GET /events/drafts`) each with a "Publish" button (`POST /events/{event_id}/publish`); a successful publish removes the Event from the draft list and shows a confirmation, and returning to the Events screen refreshes the public list so a newly-published Event appears without a manual pull-to-refresh. Both entry points are a UI convenience only — the underlying endpoints remain independently protected by `require_admin` server-side.

The user-created-event content pipeline still does not exist. Admin-authored events can now be created and published via `POST /events` and `POST /events/{event_id}/publish`, but a created Event starts as an unpublished draft (see above), so the normal database — local, staging, or production — has **no *published* Event rows** until something is both created *and* explicitly published. `GET /events` returning an empty list is the expected, correct state until that happens, not a bug. See Seed / Development Data below for the one, explicitly manual way to populate the list for local development/testing.

## Out of Scope (Not Yet Implemented)

- Event Details screen
- Creating events as a registered user (community/user-created events) — from Flutter or otherwise. Only admin-authored draft creation/publishing exists (see above).
- Editing or deleting events
- Attendance / "Going", attendee counts or attendee lists
- Moderation of events
- External event-provider integrations
- Maps
- Favorites
- Notifications
- Filtering or search

## Seed / Development Data

`backend/scripts/seed_events.py` inserts a small set of clearly-labeled sample events for **local development and testing only**. It is a manual, opt-in developer tool: it is **never run automatically** by the application, a migration, CI, or any deployment step, and must not be wired into any of those. Run it yourself (`python scripts/seed_events.py`) only when you specifically want sample events in your local database to exercise the Events list/UI end to end.

The normal database — local, staging, or production, whenever nobody has deliberately run this script — should contain **no Event rows**, sample or otherwise. Seeded events are **not production content** and must never be presented or treated as real, verified, official, or user-created events. Do not rely on this script's output being present; if you need to test against event data, run it explicitly first.

Real production content will come from two places once they're built: Vilvia/admin-curated official events, and user-created community events. Approved external event feeds/APIs may supplement official events later, but only once a suitable, legitimate source is identified — no external provider is implemented in Issue #63.

## Planned Future Schema (documentation only — not implemented)

`Event.created_by` (Issue #65) is implemented as **optional ownership information only**. It intentionally does **not** distinguish official/Vilvia-curated events from user-created ones — a community event's `created_by` can also become `null` if its creator's profile is later deleted (`ON DELETE SET NULL`), so `null` would be an unreliable, misleading signal for "this is official." If an explicit official-vs-user-created distinction is ever needed, it should be modeled as its own field, added later against a real product requirement — not inferred from `created_by` being unset.

The rest of the `Event` model is still expected to grow, additively, in later issues:

- A new `EventAttendance` table is expected to represent attendance ("Going"): `event_id`, `user_id`, plus standard timestamps. Attendee counts and (subject to future privacy decisions) visible attendee lists would be derived from this table.
- Moderation of user-created events is expected to reuse the existing `reports` table (adding `event` to `ReportTargetType`), the same pattern already used for `posts`/`comments`, rather than a new status field on `Event`.

None of this is implemented now. These are documented here so the current `Event` model can be evaluated against where it's headed, and so a later issue doesn't need to rediscover this shape from scratch.

## Future Considerations

Future versions may include:

- Event creation by registered users (community/user-created events) — the `created_by` ownership column and its creation/auth wiring already exist for admin-authored events as of Issue #75; extending creation to ordinary users, and exposing ownership via the API, do not
- Attendance / "Going", with attendee counts
- Visible attendee lists, subject to future privacy/product decisions
- Richer Vilvia/admin curation workflows for official events (Issues #75/#77 only cover minimal draft creation and publishing)
- Approved external event feeds/APIs, once a suitable source is identified
- Event Details screen
- Maps and location details
- Filtering and search
- Personalized event recommendations
