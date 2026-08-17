# Events

## Purpose

Help parents and families discover — and eventually create — events and meetups relevant to early parenthood.

Unlike Resources, Events is a community/product feature, not primarily trusted external content. Events will have two valid origins, living in the same Event domain/model:

1. **User-created community events** — registered Vilvia users creating and hosting their own events.
2. **Vilvia/admin-curated official events** — real events happening in Sweden, curated by the Vilvia team.

Both origins are first-class; neither is a fallback for the other. Issue #63 established the Events list/API/UI foundation, and Issue #65 added an optional ownership column at the domain/DB layer. Neither implements event creation, attendance, or either content pipeline end to end.

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
- A database-level ownership foundation: `Event.created_by`, an optional (nullable) foreign key to `profiles.id` with `ON DELETE SET NULL`, reusing the existing Profile/user architecture rather than a parallel creator model. This is **domain/DB scaffolding only** — `created_by` is not currently exposed via `GET /events`, and there is no way yet to actually create an event with one set (see Out of Scope). It exists so a later Create-Event issue has somewhere to attach ownership without a migration that reshapes the table.

This is a **list/API/UI foundation only**. No event content pipeline (user-created or admin-curated) exists yet — see Seed / Development Data below for what actually populates the list today.

## Out of Scope (Not Yet Implemented)

- Event Details screen
- Creating events (user-created events) — from Flutter or otherwise
- Editing or deleting events
- Attendance / "Going", attendee counts or attendee lists
- Maps
- Favorites
- Notifications
- Authentication
- Filtering or search
- External event-provider integrations

## Seed / Development Data

`backend/scripts/seed_events.py` inserts a small set of clearly-labeled sample events for **local development and testing only**. It is not run automatically as part of the application. Seeded events are **not production content** and must never be presented or treated as real, verified, official, or user-created events — the same convention already used by `backend/scripts/seed_resources.py`.

Real production content will come from two places once they're built: Vilvia/admin-curated official events, and user-created community events. Approved external event feeds/APIs may supplement official events later, but only once a suitable, legitimate source is identified — no external provider is implemented in Issue #63.

## Planned Future Schema (documentation only — not implemented)

`Event.created_by` (Issue #65) is implemented as **optional ownership information only**. It intentionally does **not** distinguish official/Vilvia-curated events from user-created ones — a community event's `created_by` can also become `null` if its creator's profile is later deleted (`ON DELETE SET NULL`), so `null` would be an unreliable, misleading signal for "this is official." If an explicit official-vs-user-created distinction is ever needed, it should be modeled as its own field, added later against a real product requirement — not inferred from `created_by` being unset.

The rest of the `Event` model is still expected to grow, additively, in later issues:

- A new `EventAttendance` table is expected to represent attendance ("Going"): `event_id`, `user_id`, plus standard timestamps. Attendee counts and (subject to future privacy decisions) visible attendee lists would be derived from this table.
- Moderation of user-created events is expected to reuse the existing `reports` table (adding `event` to `ReportTargetType`), the same pattern already used for `posts`/`comments`, rather than a new status field on `Event`.

None of this is implemented now. These are documented here so the current `Event` model can be evaluated against where it's headed, and so a later issue doesn't need to rediscover this shape from scratch.

## Future Considerations

Future versions may include:

- Event creation by registered users (the `created_by` ownership column already exists as of Issue #65; the creation flow, auth wiring, and exposing ownership via the API do not)
- Attendance / "Going", with attendee counts
- Visible attendee lists, subject to future privacy/product decisions
- Vilvia/admin curation workflows for official events
- Approved external event feeds/APIs, once a suitable source is identified
- Event Details screen
- Maps and location details
- Filtering and search
- Personalized event recommendations
