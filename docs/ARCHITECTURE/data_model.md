# Firestore Data Model

## Purpose

This document describes the initial Firestore data model for Vilvia.

The goal is to design a simple, scalable, and maintainable database structure that supports the MVP while allowing future features to be added without major structural changes.

---

## Top-Level Collections

The initial Firestore structure uses separate top-level collections for the main product areas.

This avoids placing all data under the user document and makes it easier to query shared data such as community posts and trusted resources.

Initial collections:

- `users`
- `resources`
- `posts`
- `comments`
- `reports`

---

## `users`

The `users` collection stores account-related data and personalization settings.

Each user document uses the Firebase Authentication user ID as the document ID.

Example path:

```text
users/{userId}
```

Example fields:

```text
firstName: string
email: string
role: enum
childStage: enum | null
pregnancyWeek: number | null
createdAt: timestamp
updatedAt: timestamp
```

Notes:

- Authentication is handled by Firebase Authentication.
- Firestore stores only the profile and personalization data needed by the app.
- User documents should remain small and focused.
- Shared data such as posts and resources should not be stored under the user document.

---

## `resources`

The `resources` collection stores trusted parenting resources used in the Information section.

Resources are separate from community posts because they are reviewed, structured, and based on trusted official sources.

Example path:

```text
resources/{resourceId}
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
- Resources should be reviewed before publication.
- Community discussions may later link to related resources.
- AI-assisted features should rely on trusted resources rather than user-generated content.

---

## `posts`

The `posts` collection stores community posts created by users.

Posts are stored as a top-level collection so the community feed can be queried efficiently without reading data from each user document.

Example path:

```text
posts/{postId}
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

- `authorId` links the post to the user who created it.
- `authorName` and `authorAvatarUrl` are intentionally duplicated to improve feed performance.
- This duplication follows a common Firestore denormalization pattern.
- Community posts are user-generated content and should not be treated as trusted official information.
- Posts may later link to trusted resources through `relatedResourceId`.

---

## `comments`

The `comments` collection stores comments made on community posts.

Comments are stored as a top-level collection to simplify moderation, reporting, and future features while keeping queries efficient.

Example path:

```text
comments/{commentId}
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

- `postId` links the comment to its parent post.
- `authorName` and `authorAvatarUrl` are intentionally duplicated to improve read performance.
- Comments are user-generated content and should not be treated as trusted information.
- Comments may be reported for moderation.

---

## `reports`

The `reports` collection stores user reports for content that may require moderation.

Reports are stored as a top-level collection so moderators can review all reported items from a single place.

Example path:

```text
reports/{reportId}
```

Example fields:

```text
targetType: enum
targetId: string
reportedBy: string
reason: string
status: enum
createdAt: timestamp
updatedAt: timestamp
```

Notes:

- `targetType` identifies what was reported, such as `post` or `comment`.
- `targetId` stores the ID of the reported item.
- `reportedBy` stores the user ID of the person who submitted the report.
- `status` may include values such as `pending`, `reviewed`, or `dismissed`.
- Keeping reports as a top-level collection makes future moderation tools easier to build.

---

## Design Decisions

- Use top-level collections for shared data.
- Keep user documents focused on profile and personalization.
- Duplicate selected user fields in posts and comments to improve read performance.
- Keep trusted resources separate from user-generated content.
- Store reports separately to support future moderation tools.
- Design the data model to support future features without major structural changes.

---

## Future Considerations

The data model is intentionally simple for the MVP and is expected to evolve as new features are introduced.