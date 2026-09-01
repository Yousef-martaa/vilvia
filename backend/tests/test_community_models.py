from sqlalchemy import Boolean, CheckConstraint, ForeignKey

from app.models.account_deletion_request import AccountDeletionRequest
from app.models.comment import Comment
from app.models.event import Event
from app.models.post import Post
from app.models.post_reaction import PostReaction
from app.models.report import Report


def assert_foreign_key(
    column, target: str, ondelete: str, *, nullable: bool = False
) -> None:
    assert column.nullable is nullable
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


def test_community_visibility_is_non_nullable_and_defaults_false():
    for column in (Post.__table__.c.is_hidden, Comment.__table__.c.is_hidden):
        assert isinstance(column.type, Boolean)
        assert column.nullable is False
        assert column.default.arg is False
        assert str(column.server_default.arg).lower() == "false"


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


def test_report_requires_exactly_one_target():
    constraints = {
        constraint.name: str(constraint.sqltext)
        for constraint in Report.__table__.constraints
        if isinstance(constraint, CheckConstraint)
    }
    expression = constraints["reports_exactly_one_target_check"].lower()
    assert "post_id is not null" in expression
    assert "comment_id is not null" in expression


def test_report_foreign_keys_have_deliberate_delete_behavior():
    assert_foreign_key(
        Report.__table__.c.post_id, "posts.id", "CASCADE", nullable=True
    )
    assert_foreign_key(
        Report.__table__.c.comment_id,
        "comments.id",
        "CASCADE",
        nullable=True,
    )
    assert_foreign_key(
        Report.__table__.c.reported_by, "profiles.id", "RESTRICT"
    )


def test_report_prevents_duplicate_reporter_target_pairs():
    unique_columns = {
        tuple(column.name for column in constraint.columns)
        for constraint in Report.__table__.constraints
        if constraint.__class__.__name__ == "UniqueConstraint"
    }
    assert ("reported_by", "post_id") in unique_columns
    assert ("reported_by", "comment_id") in unique_columns


def test_report_target_columns_are_indexed():
    indexes = {
        index.name: tuple(column.name for column in index.columns)
        for index in Report.__table__.indexes
    }
    assert indexes["ix_reports_post_id"] == ("post_id",)
    assert indexes["ix_reports_comment_id"] == ("comment_id",)


def test_account_deletion_request_is_not_tied_to_profile_lifetime():
    column = AccountDeletionRequest.__table__.c.user_id
    assert column.primary_key is True
    assert not column.foreign_keys


def test_event_creator_is_retained_with_null_ownership_on_profile_delete():
    assert_foreign_key(
        Event.__table__.c.created_by,
        "profiles.id",
        "SET NULL",
        nullable=True,
    )
