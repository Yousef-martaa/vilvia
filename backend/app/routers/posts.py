import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.api.deps import AuthenticatedUser, get_current_user, get_db
from app.core.rate_limit import rate_limit_public, rate_limit_user
from app.core.settings import settings
from app.models.comment import Comment
from app.models.post import Post
from app.models.profile import Profile
from app.schemas.comment import CommentCreate, CommentCreateResponse, CommentResponse
from app.schemas.post import PostCreate, PostResponse

router = APIRouter(prefix="/posts", tags=["posts"])


@router.get(
    "",
    response_model=list[PostResponse],
    dependencies=[
        Depends(rate_limit_public("posts:list", settings.rate_limit_public_per_minute))
    ],
)
def get_posts(db: Session = Depends(get_db)) -> list[PostResponse]:
    result = db.execute(
        select(Post)
        .where(Post.is_published.is_(True))
        .order_by(Post.created_at.desc())
    )
    return result.scalars().all()


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
    return select(Post).where(Post.id == post_id, Post.is_published.is_(True))


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
        .where(Comment.post_id == post_id)
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
