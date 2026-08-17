# Events

## Purpose

Help parents and families discover — and eventually create — events and meetups relevant to early parenthood.

Unlike Resources, Events is a community/product feature, not primarily trusted external content. Events will have two valid origins, living in the same Event domain/model:

1. **User-created community events** — registered Vilvia users creating and hosting their own events.
2. **Vilvia/admin-curated official events** — real events happening in Sweden, curated by the Vilvia team.

Both origins are first-class; neither is a fallback for the other. Issue #63 establishes the Events list/API/UI foundation only — it does not implement event creation, attendance, or either content pipeline.

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

This is a **list/API/UI foundation only**. No event content pipeline (user-created or admin-curated) exists yet — see Seed / Development Data below for what actually populates the list today.

## Out of Scope for This Issue

- Event Details screen
- Creating events (user-created events)
- Attendance / "Going"
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

To support both event origins without a second event system, the `Event` model is expected to grow, additively, in a later issue:

- `Event` may gain `created_by` (nullable reference to `profiles.id`): populated for user-created events; left unset for Vilvia/admin-curated events, or set to the curating admin's profile. "Official" vs. "user-created" is not expected to need its own column — it falls out of `created_by` together with the existing `Profile.role` (`parent`/`admin`).
- A new `EventAttendance` table is expected to represent attendance ("Going"): `event_id`, `user_id`, plus standard timestamps. Attendee counts and (subject to future privacy decisions) visible attendee lists would be derived from this table.
- Moderation of user-created events is expected to reuse the existing `reports` table (adding `event` to `ReportTargetType`), the same pattern already used for `posts`/`comments`, rather than a new status field on `Event`.

None of this is implemented now. These columns/tables are not being added in Issue #63 — they're documented here so the current, unmodified `Event` model can be evaluated against where it's headed, and so a later issue doesn't need to rediscover this shape from scratch.

## Future Considerations

Future versions may include:

- Event creation by registered users, with authenticated ownership (`created_by`)
- Attendance / "Going", with attendee counts
- Visible attendee lists, subject to future privacy/product decisions
- Vilvia/admin curation workflows for official events
- Approved external event feeds/APIs, once a suitable source is identified
- Event Details screen
- Maps and location details
- Filtering and search
- Personalized event recommendations
