import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, aliased

from app.api.deps import ensure_user_id_active, get_db, require_admin
from app.core.rate_limit import rate_limit_admin
from app.core.settings import settings
from app.models.comment import Comment
from app.models.enums import ReportStatus
from app.models.post import Post
from app.models.profile import Profile
from app.models.report import Report
from app.schemas.report import (
    AdminReportResponse,
    ReportCommentContext,
    ReportPostContext,
    ReportStatusUpdate,
    ReportTargetVisibilityUpdate,
)

router = APIRouter(prefix="/reports", tags=["reports"])
log = logging.getLogger(__name__)

MAX_REPORT_OFFSET = 10_000


def _report_query():
    parent_post = aliased(Post)
    return (
        select(Report, Post, Comment, parent_post)
        .outerjoin(Post, Report.post_id == Post.id)
        .outerjoin(Comment, Report.comment_id == Comment.id)
        .outerjoin(parent_post, Comment.post_id == parent_post.id)
    )


def _serialize_report(row) -> AdminReportResponse | None:
    report, post, comment, parent_post = row
    has_post_target = report.post_id is not None
    has_comment_target = report.comment_id is not None
    if has_post_target == has_comment_target:
        return None

    if has_post_target:
        if post is None or post.id != report.post_id:
            return None
        return AdminReportResponse(
            id=report.id,
            reason=report.reason,
            status=report.status,
            created_at=report.created_at,
            updated_at=report.updated_at,
            target_kind="post",
            target_id=report.post_id,
            target_is_hidden=post.is_hidden,
            post=ReportPostContext(id=post.id, title=post.title, body=post.body),
        )
    if (
        comment is None
        or parent_post is None
        or comment.id != report.comment_id
        or comment.post_id != parent_post.id
    ):
        return None
    return AdminReportResponse(
        id=report.id,
        reason=report.reason,
        status=report.status,
        created_at=report.created_at,
        updated_at=report.updated_at,
        target_kind="comment",
        target_id=report.comment_id,
        target_is_hidden=comment.is_hidden,
        comment=ReportCommentContext(
            id=comment.id,
            body=comment.body,
            post_id=parent_post.id,
            post_title=parent_post.title,
        ),
    )


@router.get(
    "",
    response_model=list[AdminReportResponse],
    dependencies=[
        Depends(
            rate_limit_admin(
                "reports:list", settings.rate_limit_admin_read_per_minute
            )
        )
    ],
)
def get_reports(
    report_status: ReportStatus = Query(ReportStatus.pending, alias="status"),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0, le=MAX_REPORT_OFFSET),
    admin_profile: Profile = Depends(require_admin),
    db: Session = Depends(get_db),
) -> list[AdminReportResponse]:
    rows = db.execute(
        _report_query()
        .where(Report.status == report_status)
        .order_by(Report.created_at.desc(), Report.id.desc())
        .limit(limit)
        .offset(offset)
    ).all()
    reports = []
    for row in rows:
        serialized = _serialize_report(row)
        if serialized is None:
            log.error("skipping report with invalid target context id=%s", row[0].id)
            continue
        reports.append(serialized)
    return reports


@router.put(
    "/{report_id}/status",
    response_model=AdminReportResponse,
    dependencies=[
        Depends(
            rate_limit_admin(
                "reports:status", settings.rate_limit_admin_write_per_minute
            )
        )
    ],
)
def update_report_status(
    report_id: uuid.UUID,
    body: ReportStatusUpdate,
    admin_profile: Profile = Depends(require_admin),
    db: Session = Depends(get_db),
) -> AdminReportResponse:
    ensure_user_id_active(admin_profile.id, db, serialize_mutation=True)
    report, _, _ = _lock_report_context(report_id, db)
    serialized = _locked_serialized_report(report_id, db)

    if report.status == body.status and report.status in {
        ReportStatus.reviewed,
        ReportStatus.dismissed,
    }:
        return serialized

    if report.status != ReportStatus.pending or body.status not in {
        ReportStatus.reviewed,
        ReportStatus.dismissed,
    }:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Cannot transition report from {report.status.value} to {body.status.value}.",
        )

    report.status = body.status
    try:
        db.flush()
        serialized = _locked_serialized_report(report_id, db)
        db.commit()
    except (SQLAlchemyError, HTTPException):
        db.rollback()
        raise
    return serialized


def _unavailable_target() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail="Report target context is unavailable.",
    )


def _locked_serialized_report(
    report_id: uuid.UUID, db: Session
) -> AdminReportResponse:
    row = db.execute(_report_query().where(Report.id == report_id)).one_or_none()
    if row is None:
        raise _unavailable_target()
    serialized = _serialize_report(row)
    if serialized is None:
        raise _unavailable_target()
    return serialized


def _lock_report_context(
    report_id: uuid.UUID, db: Session
) -> tuple[Report, Post | Comment, Post | None]:
    """Lock a report through its target in one deterministic hierarchy.

    The first Report read is deliberately unlocked and used only to discover
    target IDs. The locked Report is revalidated after acquiring Post, or
    Post then Comment, so a concurrent target change cannot be acted upon.
    """
    preliminary = db.execute(
        select(Report).where(Report.id == report_id)
    ).scalar_one_or_none()
    if preliminary is None:
        raise HTTPException(status_code=404, detail="Report not found")

    has_post_target = preliminary.post_id is not None
    has_comment_target = preliminary.comment_id is not None
    if has_post_target == has_comment_target:
        raise _unavailable_target()

    parent_post: Post | None = None
    target: Post | Comment
    if has_post_target:
        discovered_target_id = preliminary.post_id
        target = db.execute(
            select(Post).where(Post.id == discovered_target_id).with_for_update()
        ).scalar_one_or_none()
        if target is None:
            raise _unavailable_target()
    else:
        discovered_target_id = preliminary.comment_id
        discovered_comment = db.execute(
            select(Comment).where(Comment.id == discovered_target_id)
        ).scalar_one_or_none()
        if discovered_comment is None:
            raise _unavailable_target()
        parent_post = db.execute(
            select(Post)
            .where(Post.id == discovered_comment.post_id)
            .with_for_update()
        ).scalar_one_or_none()
        if parent_post is None:
            raise _unavailable_target()
        target = db.execute(
            select(Comment)
            .where(
                Comment.id == discovered_target_id,
                Comment.post_id == parent_post.id,
            )
            .with_for_update()
        ).scalar_one_or_none()
        if target is None:
            raise _unavailable_target()

    report = db.execute(
        select(Report).where(Report.id == report_id).with_for_update()
    ).scalar_one_or_none()
    if report is None:
        raise HTTPException(status_code=404, detail="Report not found")
    if has_post_target:
        if report.post_id != target.id or report.comment_id is not None:
            raise _unavailable_target()
    elif (
        report.comment_id != target.id
        or report.post_id is not None
        or parent_post is None
        or target.post_id != parent_post.id
    ):
        raise _unavailable_target()
    return report, target, parent_post


@router.put(
    "/{report_id}/target-visibility",
    response_model=AdminReportResponse,
    dependencies=[
        Depends(
            rate_limit_admin(
                "reports:target-visibility",
                settings.rate_limit_admin_write_per_minute,
            )
        )
    ],
)
def update_report_target_visibility(
    report_id: uuid.UUID,
    body: ReportTargetVisibilityUpdate,
    admin_profile: Profile = Depends(require_admin),
    db: Session = Depends(get_db),
) -> AdminReportResponse:
    """Hide or restore a Report target using target-first row locking."""
    ensure_user_id_active(admin_profile.id, db, serialize_mutation=True)
    _, target, parent_post = _lock_report_context(report_id, db)

    if target.is_hidden == body.is_hidden:
        return _locked_serialized_report(report_id, db)

    target.is_hidden = body.is_hidden
    try:
        db.flush()
        if parent_post is not None:
            parent_post.comment_count = db.scalar(
                select(func.count()).select_from(Comment).where(
                    Comment.post_id == parent_post.id,
                    Comment.is_hidden.is_(False),
                )
            )
            db.flush()
        serialized = _locked_serialized_report(report_id, db)
        db.commit()
    except (SQLAlchemyError, HTTPException):
        db.rollback()
        raise
    return serialized
