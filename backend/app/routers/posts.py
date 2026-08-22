from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_db
from app.core.rate_limit import rate_limit_public
from app.core.settings import settings
from app.models.post import Post
from app.schemas.post import PostResponse

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
