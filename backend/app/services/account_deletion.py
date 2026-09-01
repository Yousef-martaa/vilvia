import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, func, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.settings import minimum_account_deletion_retention_seconds
from app.models.account_deletion_request import AccountDeletionRequest
from app.models.comment import Comment
from app.models.enums import AccountDeletionStatus
from app.models.post import Post
from app.models.post_reaction import PostReaction
from app.models.profile import Profile
from app.models.report import Report


class AccountDeletionNotFound(Exception):
    pass


@dataclass(frozen=True)
class AccountDeletionResult:
    user_id: uuid.UUID
    status: AccountDeletionStatus


def _locked_request(db: Session, user_id: uuid.UUID) -> AccountDeletionRequest:
    deletion_request = db.execute(
        select(AccountDeletionRequest)
        .where(AccountDeletionRequest.user_id == user_id)
        .with_for_update()
    ).scalar_one_or_none()
    if deletion_request is None:
        raise AccountDeletionNotFound(str(user_id))
    return deletion_request


def _preliminary_ids(db: Session, user_id: uuid.UUID) -> tuple[set[uuid.UUID], ...]:
    authored_posts = set(
        db.scalars(select(Post.id).where(Post.author_id == user_id)).all()
    )
    authored_comments = set(
        db.scalars(select(Comment.id).where(Comment.author_id == user_id)).all()
    )
    reaction_posts = set(
        db.scalars(
            select(PostReaction.post_id).where(
                PostReaction.profile_id == user_id
            )
        ).all()
    )
    created_reports = db.execute(
        select(Report.post_id, Report.comment_id).where(
            Report.reported_by == user_id
        )
    ).all()
    reported_posts = {row.post_id for row in created_reports if row.post_id}
    reported_comments = {
        row.comment_id for row in created_reports if row.comment_id
    }
    return (
        authored_posts,
        authored_comments,
        reaction_posts,
        reported_posts,
        reported_comments,
    )


def _cleanup_postgres(db: Session, user_id: uuid.UUID) -> None:
    """Delete application data with Community's Post→Comment→Report order."""
    (
        authored_post_ids,
        authored_comment_ids,
        reaction_post_ids,
        reported_post_ids,
        reported_comment_ids,
    ) = _preliminary_ids(db, user_id)

    preliminary_comment_ids = authored_comment_ids | reported_comment_ids
    preliminary_comment_parents = set()
    if preliminary_comment_ids:
        preliminary_comment_parents = set(
            db.scalars(
                select(Comment.post_id).where(
                    Comment.id.in_(preliminary_comment_ids)
                )
            ).all()
        )

    post_ids = (
        authored_post_ids
        | reaction_post_ids
        | reported_post_ids
        | preliminary_comment_parents
    )
    locked_posts = []
    if post_ids:
        locked_posts = db.scalars(
            select(Post)
            .where(Post.id.in_(post_ids))
            .order_by(Post.id)
            .with_for_update()
        ).all()
    locked_post_ids = {post.id for post in locked_posts}
    authored_post_ids &= locked_post_ids

    # Query after locking Posts so Comments committed before the parent lock
    # are included and later Comment creation is serialized behind it.
    comments_to_delete = set(authored_comment_ids)
    if authored_post_ids:
        comments_to_delete.update(
            db.scalars(
                select(Comment.id).where(Comment.post_id.in_(authored_post_ids))
            ).all()
        )
    comment_ids = comments_to_delete | reported_comment_ids
    locked_comments = []
    if comment_ids:
        locked_comments = db.scalars(
            select(Comment)
            .where(Comment.id.in_(comment_ids))
            .order_by(Comment.id)
            .with_for_update()
        ).all()
    locked_comment_ids = {comment.id for comment in locked_comments}
    comments_to_delete &= locked_comment_ids

    report_ids = set(
        db.scalars(
            select(Report.id).where(
                (Report.reported_by == user_id)
                | (Report.post_id.in_(authored_post_ids))
                | (Report.comment_id.in_(comments_to_delete))
            )
        ).all()
    )
    if report_ids:
        db.scalars(
            select(Report)
            .where(Report.id.in_(report_ids))
            .order_by(Report.id)
            .with_for_update()
        ).all()

    # Created Reports must be removed before Profile because reported_by is
    # RESTRICT. Target Reports disappear via existing target cascades.
    db.execute(delete(Report).where(Report.reported_by == user_id))
    if comments_to_delete:
        db.execute(delete(Comment).where(Comment.id.in_(comments_to_delete)))
    if authored_post_ids:
        db.execute(delete(Post).where(Post.id.in_(authored_post_ids)))
    db.execute(
        delete(PostReaction).where(PostReaction.profile_id == user_id)
    )
    db.execute(delete(Profile).where(Profile.id == user_id))
    db.flush()

    surviving_posts = locked_post_ids - authored_post_ids
    for post_id in sorted(surviving_posts):
        post = next(post for post in locked_posts if post.id == post_id)
        post.reaction_count = db.scalar(
            select(func.count()).select_from(PostReaction).where(
                PostReaction.post_id == post_id
            )
        )
        post.comment_count = db.scalar(
            select(func.count()).select_from(Comment).where(
                Comment.post_id == post_id,
                Comment.is_hidden.is_(False),
            )
        )
        post.report_count = db.scalar(
            select(func.count()).select_from(Report).where(
                Report.post_id == post_id
            )
        )

    surviving_comments = locked_comment_ids - comments_to_delete
    for comment_id in sorted(surviving_comments):
        comment = next(
            comment for comment in locked_comments if comment.id == comment_id
        )
        comment.report_count = db.scalar(
            select(func.count()).select_from(Report).where(
                Report.comment_id == comment_id
            )
        )
    db.flush()


def fulfill_account_deletion(
    db: Session,
    user_id: uuid.UUID,
    delete_auth_identity: Callable[[uuid.UUID], None],
) -> AccountDeletionResult:
    """Advance one deletion request; safe to call repeatedly after failure."""
    try:
        deletion_request = _locked_request(db, user_id)
        if deletion_request.status == AccountDeletionStatus.completed:
            db.rollback()
            return AccountDeletionResult(user_id, deletion_request.status)

        if deletion_request.status == AccountDeletionStatus.requested:
            delete_auth_identity(user_id)
            deletion_request.status = AccountDeletionStatus.auth_deleted
            deletion_request.auth_deleted_at = datetime.now(timezone.utc)
            db.commit()

        deletion_request = _locked_request(db, user_id)
        if deletion_request.status == AccountDeletionStatus.completed:
            db.rollback()
            return AccountDeletionResult(user_id, deletion_request.status)
        if deletion_request.status != AccountDeletionStatus.auth_deleted:
            raise RuntimeError("Invalid account deletion lifecycle state")
        _cleanup_postgres(db, user_id)
        deletion_request.status = AccountDeletionStatus.completed
        deletion_request.completed_at = datetime.now(timezone.utc)
        db.commit()
        return AccountDeletionResult(user_id, AccountDeletionStatus.completed)
    except Exception:
        db.rollback()
        raise


def purge_completed_requests(
    db: Session,
    retention_days: int,
    *,
    max_access_token_lifetime_seconds: int,
    jwt_clock_skew_seconds: int,
) -> int:
    """Remove completed recovery records after their minimal retention."""
    if retention_days < 1:
        raise ValueError("retention_days must be at least 1")
    if max_access_token_lifetime_seconds < 1 or jwt_clock_skew_seconds < 0:
        raise ValueError(
            "JWT lifetime must be positive and clock skew non-negative"
        )
    minimum_seconds = minimum_account_deletion_retention_seconds(
        max_access_token_lifetime_seconds, jwt_clock_skew_seconds
    )
    if retention_days * 24 * 60 * 60 < minimum_seconds:
        raise ValueError(
            "completed-request retention is shorter than JWT validity"
        )
    cutoff = datetime.now(timezone.utc) - timedelta(days=retention_days)
    try:
        result = db.execute(
            delete(AccountDeletionRequest).where(
                AccountDeletionRequest.status == AccountDeletionStatus.completed,
                AccountDeletionRequest.completed_at < cutoff,
            )
        )
        db.commit()
        return result.rowcount or 0
    except SQLAlchemyError:
        db.rollback()
        raise
