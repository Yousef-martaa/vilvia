import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import (
    AuthenticatedUser,
    ensure_account_active,
    get_current_user,
    get_db,
    get_optional_current_user,
)
from app.core.rate_limit import rate_limit_public, rate_limit_user
from app.core.settings import settings
from app.models.comment import Comment
from app.models.post import Post
from app.models.post_reaction import PostReaction
from app.models.profile import Profile
from app.models.report import Report
from app.schemas.comment import CommentCreate, CommentCreateResponse, CommentResponse
from app.schemas.post import PostCreate, PostReactionResponse, PostResponse
from app.schemas.report import ReportCreate, ReportResponse

router = APIRouter(prefix="/posts", tags=["posts"])


@router.get(
    "",
    response_model=list[PostResponse],
    dependencies=[
        Depends(rate_limit_public("posts:list", settings.rate_limit_public_per_minute))
    ],
)
def get_posts(
    current_user: AuthenticatedUser | None = Depends(get_optional_current_user),
    db: Session = Depends(get_db),
) -> list[PostResponse]:
    result = db.execute(
        select(Post)
        .where(Post.is_published.is_(True), Post.is_hidden.is_(False))
        .order_by(Post.created_at.desc())
    )
    posts = result.scalars().all()
    reacted_post_ids: set[uuid.UUID] = set()
    if current_user is not None and posts:
        reacted_post_ids = set(
            db.execute(
                select(PostReaction.post_id).where(
                    PostReaction.profile_id == current_user.id,
                    PostReaction.post_id.in_([post.id for post in posts]),
                )
            ).scalars()
        )
    return [
        PostResponse.model_validate(post).model_copy(
            update={"has_reacted": post.id in reacted_post_ids}
        )
        for post in posts
    ]


@router.post(
    "",
    response_model=PostResponse,
    status_code=status.HTTP_201_CREATED,
    dependencies=[
        Depends(
            rate_limit_user(
                "posts:create", settings.rate_limit_community_write_per_minute
            )
        )
    ],
)
def create_post(
    body: PostCreate,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Post:
    """Create an immediately published MVP community post.

    Ownership, display name, publication state, counters, and other internal
    fields are assigned only by the server. ``PostCreate.extra='forbid'``
    rejects attempts to supply any of them instead of silently ignoring them.
    """
    ensure_account_active(current_user, db, serialize_mutation=True)
    profile = db.get(Profile, current_user.id)
    if profile is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A Profile is required before creating a post.",
        )

    post = Post(
        author_id=profile.id,
        author_name=profile.first_name,
        author_avatar_url=None,
        title=body.title,
        body=body.body,
        category=body.category,
        is_published=True,
    )
    db.add(post)
    try:
        db.commit()
        db.refresh(post)
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="The post could not be created because of a data conflict.",
        ) from None
    return post


def _published_post_query(post_id: uuid.UUID):
    return select(Post).where(
        Post.id == post_id,
        Post.is_published.is_(True),
        Post.is_hidden.is_(False),
    )


def _set_reaction(
    *,
    post_id: uuid.UUID,
    reacted: bool,
    current_user: AuthenticatedUser,
    db: Session,
) -> PostReactionResponse:
    ensure_account_active(current_user, db, serialize_mutation=True)
    post = db.execute(
        _published_post_query(post_id).with_for_update()
    ).scalar_one_or_none()
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")

    profile = db.get(Profile, current_user.id)
    if profile is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A Profile is required before reacting to a post.",
        )

    reaction = db.get(PostReaction, (post.id, profile.id))
    if reacted and reaction is None:
        db.add(PostReaction(post_id=post.id, profile_id=profile.id))
    elif not reacted and reaction is not None:
        db.delete(reaction)

    try:
        db.flush()
        post.reaction_count = db.scalar(
            select(func.count()).select_from(PostReaction).where(
                PostReaction.post_id == post.id
            )
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="The reaction could not be updated because of a data conflict.",
        ) from None

    return PostReactionResponse(
        reacted=reacted, reaction_count=post.reaction_count
    )


@router.put(
    "/{post_id}/reaction",
    response_model=PostReactionResponse,
    dependencies=[
        Depends(
            rate_limit_user(
                "reactions:update", settings.rate_limit_community_write_per_minute
            )
        )
    ],
)
def add_reaction(
    post_id: uuid.UUID,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> PostReactionResponse:
    return _set_reaction(
        post_id=post_id, reacted=True, current_user=current_user, db=db
    )


@router.delete(
    "/{post_id}/reaction",
    response_model=PostReactionResponse,
    dependencies=[
        Depends(
            rate_limit_user(
                "reactions:update", settings.rate_limit_community_write_per_minute
            )
        )
    ],
)
def remove_reaction(
    post_id: uuid.UUID,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> PostReactionResponse:
    return _set_reaction(
        post_id=post_id, reacted=False, current_user=current_user, db=db
    )


def _save_report(
    *,
    target: Post | Comment,
    target_column,
    target_values: dict,
    body: ReportCreate,
    profile: Profile,
    db: Session,
) -> ReportResponse:
    report = db.execute(
        select(Report).where(
            target_column == target.id,
            Report.reported_by == profile.id,
        )
    ).scalar_one_or_none()
    if report is None:
        report = Report(
            **target_values,
            reported_by=profile.id,
            reason=body.reason,
        )
        db.add(report)
    else:
        report.reason = body.reason

    try:
        db.flush()
        target.report_count = db.scalar(
            select(func.count()).select_from(Report).where(
                target_column == target.id
            )
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="The report could not be submitted because of a data conflict.",
        ) from None

    return ReportResponse(reported=True, report_count=target.report_count)


def _reporter_profile(
    current_user: AuthenticatedUser, db: Session
) -> Profile:
    profile = db.get(Profile, current_user.id)
    if profile is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A Profile is required before reporting community content.",
        )
    return profile


@router.put(
    "/{post_id}/report",
    response_model=ReportResponse,
    dependencies=[
        Depends(
            rate_limit_user(
                "reports:create", settings.rate_limit_community_write_per_minute
            )
        )
    ],
)
def report_post(
    post_id: uuid.UUID,
    body: ReportCreate,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ReportResponse:
    ensure_account_active(current_user, db, serialize_mutation=True)
    post = db.execute(
        _published_post_query(post_id).with_for_update()
    ).scalar_one_or_none()
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")

    profile = _reporter_profile(current_user, db)
    return _save_report(
        target=post,
        target_column=Report.post_id,
        target_values={"post_id": post.id},
        body=body,
        profile=profile,
        db=db,
    )


@router.put(
    "/{post_id}/comments/{comment_id}/report",
    response_model=ReportResponse,
    dependencies=[
        Depends(
            rate_limit_user(
                "reports:create", settings.rate_limit_community_write_per_minute
            )
        )
    ],
)
def report_comment(
    post_id: uuid.UUID,
    comment_id: uuid.UUID,
    body: ReportCreate,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ReportResponse:
    ensure_account_active(current_user, db, serialize_mutation=True)
    post = db.execute(
        _published_post_query(post_id).with_for_update()
    ).scalar_one_or_none()
    if post is None:
        raise HTTPException(status_code=404, detail="Comment not found")

    comment = db.execute(
        select(Comment)
        .where(
            Comment.id == comment_id,
            Comment.post_id == post.id,
            Comment.is_hidden.is_(False),
        )
        .with_for_update()
    ).scalar_one_or_none()
    if comment is None:
        raise HTTPException(status_code=404, detail="Comment not found")

    profile = _reporter_profile(current_user, db)
    return _save_report(
        target=comment,
        target_column=Report.comment_id,
        target_values={"comment_id": comment.id},
        body=body,
        profile=profile,
        db=db,
    )


@router.get(
    "/{post_id}/comments",
    response_model=list[CommentResponse],
    dependencies=[
        Depends(
            rate_limit_public(
                "comments:list", settings.rate_limit_public_per_minute
            )
        )
    ],
)
def get_comments(
    post_id: uuid.UUID, db: Session = Depends(get_db)
) -> list[CommentResponse]:
    """List comments oldest-first without exposing unpublished posts."""
    post = db.execute(_published_post_query(post_id)).scalar_one_or_none()
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")

    result = db.execute(
        select(Comment)
        .where(Comment.post_id == post_id, Comment.is_hidden.is_(False))
        .order_by(Comment.created_at.asc())
    )
    return result.scalars().all()


@router.post(
    "/{post_id}/comments",
    response_model=CommentCreateResponse,
    status_code=status.HTTP_201_CREATED,
    dependencies=[
        Depends(
            rate_limit_user(
                "comments:create", settings.rate_limit_community_write_per_minute
            )
        )
    ],
)
def create_comment(
    post_id: uuid.UUID,
    body: CommentCreate,
    current_user: AuthenticatedUser = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """Create a comment and update its published Post's count atomically."""
    ensure_account_active(current_user, db, serialize_mutation=True)
    post = db.execute(
        _published_post_query(post_id).with_for_update()
    ).scalar_one_or_none()
    if post is None:
        raise HTTPException(status_code=404, detail="Post not found")

    profile = db.get(Profile, current_user.id)
    if profile is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A Profile is required before creating a comment.",
        )

    comment = Comment(
        post_id=post.id,
        author_id=profile.id,
        author_name=profile.first_name,
        author_avatar_url=None,
        body=body.body,
    )
    db.add(comment)
    post.comment_count += 1
    try:
        db.commit()
        db.refresh(comment)
        db.refresh(post)
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="The comment could not be created because of a data conflict.",
        ) from None

    return {"comment": comment, "comment_count": post.comment_count}
