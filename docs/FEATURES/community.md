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

### Read-only Feed

The Community screen displays published posts from the public `GET /posts`
endpoint, newest first. It handles loading, empty, and error states and allows
a failed request to be retried. Browsing does not require authentication.

The current feed is deliberately read-only. Post creation and editing,
comments, reactions, reporting, moderation, post details, and pagination are
not part of this implementation.

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
