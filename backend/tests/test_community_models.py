from sqlalchemy import ForeignKey

from app.models.comment import Comment
from app.models.post import Post
from app.models.post_reaction import PostReaction


def assert_foreign_key(column, target: str, ondelete: str) -> None:
    assert column.nullable is False
    assert len(column.foreign_keys) == 1

    foreign_key: ForeignKey = next(iter(column.foreign_keys))
    assert foreign_key.target_fullname == target
    assert foreign_key.ondelete == ondelete


def test_post_author_references_profile_with_restricted_deletion():
    assert_foreign_key(Post.__table__.c.author_id, "profiles.id", "RESTRICT")


def test_comment_author_references_profile_with_restricted_deletion():
    assert_foreign_key(Comment.__table__.c.author_id, "profiles.id", "RESTRICT")


def test_comment_post_references_post_with_cascading_deletion():
    assert_foreign_key(Comment.__table__.c.post_id, "posts.id", "CASCADE")


def test_post_reaction_uses_ownership_pair_as_primary_key():
    primary_key = PostReaction.__table__.primary_key
    assert [column.name for column in primary_key.columns] == [
        "post_id",
        "profile_id",
    ]


def test_post_reaction_references_post_and_profile_with_cascading_deletion():
    assert_foreign_key(PostReaction.__table__.c.post_id, "posts.id", "CASCADE")
    assert_foreign_key(
        PostReaction.__table__.c.profile_id, "profiles.id", "CASCADE"
    )
