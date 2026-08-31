import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, aliased

from app.api.deps import get_db, require_admin
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
    report = db.execute(
        select(Report).where(Report.id == report_id).with_for_update()
    ).scalar_one_or_none()
    if report is None:
        raise HTTPException(status_code=404, detail="Report not found")

    row = db.execute(_report_query().where(Report.id == report_id)).one()
    serialized = _serialize_report(row)
    if serialized is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Report target context is unavailable.",
        )

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
        serialized = _serialize_report(row)
        db.commit()
    except SQLAlchemyError:
        db.rollback()
        raise
    return serialized
