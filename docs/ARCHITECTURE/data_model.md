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
childStage: enum | null
pregnancyWeek: number | null
createdAt: timestamp
updatedAt: timestamp
```

Notes:

- Authentication is handled by Supabase Auth.
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
- Resources should be reviewed before publication.
- Community discussions may later link to related resources.
- AI-assisted features should rely on trusted resources rather than user-generated content.

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

- `authorId` links the post to the user who created it.
- `authorName` and `authorAvatarUrl` are intentionally duplicated to improve feed performance.
- Community posts are user-generated content and should not be treated as trusted official information.
- This duplication is intentional to reduce joins when displaying the community feed.
- Posts may later link to trusted resources through `relatedResourceId`.

---

## `comments`

The `comments` table stores comments made on community posts.

Comments are stored as a separate table to simplify moderation, reporting, and future features while keeping queries efficient.

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

- `postId` links the comment to its parent post.
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
- Keeping reports in a separate table makes future moderation tools easier to build.

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