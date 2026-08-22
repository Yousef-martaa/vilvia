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

Editing or deleting posts/comments, reactions, replies, reporting, moderation
UI, notifications, post details, and pagination are not part of this
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
