import uuid
from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.exc import IntegrityError

from app.api.deps import AuthenticatedUser, get_current_user, get_db
from app.main import app
from app.models.comment import Comment

client = TestClient(app)


def make_post(*, published=True, comment_count=2):
    post = MagicMock()
    post.id = uuid.uuid4()
    post.is_published = published
    post.comment_count = comment_count
    return post


def make_comment(**kwargs):
    comment = MagicMock()
    comment.id = kwargs.get("id", uuid.uuid4())
    comment.post_id = kwargs.get("post_id", uuid.uuid4())
    comment.author_id = kwargs.get("author_id", uuid.uuid4())
    comment.author_name = kwargs.get("author_name", "Rowan")
    comment.author_avatar_url = kwargs.get("author_avatar_url")
    comment.body = kwargs.get("body", "A helpful comment.")
    comment.reaction_count = kwargs.get("reaction_count", 0)
    comment.report_count = kwargs.get("report_count", 0)
    comment.created_at = kwargs.get(
        "created_at", datetime(2026, 8, 22, tzinfo=timezone.utc)
    )
    comment.updated_at = kwargs.get("updated_at", comment.created_at)
    return comment


@pytest.fixture(autouse=True)
def clear_overrides():
    yield
    app.dependency_overrides.clear()


def override_user_and_db(*, profile=True, post=None):
    user = AuthenticatedUser(id=uuid.uuid4(), email="parent@example.com")
    app.dependency_overrides[get_current_user] = lambda: user
    db = MagicMock()
    if profile:
        stored_profile = MagicMock()
        stored_profile.id = user.id
        stored_profile.first_name = "Rowan"
        db.get.return_value = stored_profile
    else:
        db.get.return_value = None
    db.execute.return_value.scalar_one_or_none.return_value = post
    app.dependency_overrides[get_db] = lambda: db
    return user, db


def test_get_comments_is_public_and_returns_oldest_first():
    post = make_post()
    comments = [make_comment(post_id=post.id), make_comment(post_id=post.id)]
    db = MagicMock()
    db.execute.side_effect = [
        MagicMock(scalar_one_or_none=MagicMock(return_value=post)),
        MagicMock(
            scalars=MagicMock(
                return_value=MagicMock(all=MagicMock(return_value=comments))
            )
        ),
    ]
    app.dependency_overrides[get_db] = lambda: db

    response = client.get(f"/posts/{post.id}/comments")

    assert response.status_code == 200
    assert [item["id"] for item in response.json()] == [str(c.id) for c in comments]
    comments_sql = str(db.execute.call_args_list[1].args[0]).lower()
    assert "comments.is_hidden is false" in comments_sql
    assert "order by comments.created_at asc" in comments_sql


def test_get_comments_returns_empty_list_for_published_post():
    post = make_post()
    db = MagicMock()
    db.execute.side_effect = [
        MagicMock(scalar_one_or_none=MagicMock(return_value=post)),
        MagicMock(
            scalars=MagicMock(
                return_value=MagicMock(all=MagicMock(return_value=[]))
            )
        ),
    ]
    app.dependency_overrides[get_db] = lambda: db

    response = client.get(f"/posts/{post.id}/comments")

    assert response.status_code == 200
    assert response.json() == []


def test_get_comments_returns_404_for_missing_or_unpublished_post():
    post_id = uuid.uuid4()
    db = MagicMock()
    db.execute.return_value.scalar_one_or_none.return_value = None
    app.dependency_overrides[get_db] = lambda: db

    response = client.get(f"/posts/{post_id}/comments")

    assert response.status_code == 404
    sql = str(db.execute.call_args.args[0]).lower()
    assert "is_published is true" in sql
    assert "is_hidden is false" in sql


def test_get_comments_hidden_parent_uses_generic_not_found_response():
    post_id = uuid.uuid4()
    db = MagicMock()
    db.execute.return_value.scalar_one_or_none.return_value = None
    app.dependency_overrides[get_db] = lambda: db

    response = client.get(f"/posts/{post_id}/comments")

    assert response.status_code == 404
    assert response.json() == {"detail": "Post not found"}
    assert "is_hidden is false" in str(db.execute.call_args.args[0]).lower()
    db.commit.assert_not_called()


def test_get_comments_omits_hidden_comments():
    post = make_post()
    visible = make_comment(post_id=post.id)
    hidden = make_comment(post_id=post.id)
    hidden.is_hidden = True
    db = MagicMock()
    db.execute.side_effect = [
        MagicMock(scalar_one_or_none=MagicMock(return_value=post)),
        MagicMock(
            scalars=MagicMock(
                return_value=MagicMock(all=MagicMock(return_value=[visible]))
            )
        ),
    ]
    app.dependency_overrides[get_db] = lambda: db

    response = client.get(f"/posts/{post.id}/comments")

    assert response.status_code == 200
    assert [item["id"] for item in response.json()] == [str(visible.id)]
    assert str(hidden.id) not in {item["id"] for item in response.json()}
    assert "comments.is_hidden is false" in str(
        db.execute.call_args_list[1].args[0]
    ).lower()


def test_comment_response_excludes_internal_fields():
    post = make_post()
    comment = make_comment(post_id=post.id)
    db = MagicMock()
    db.execute.side_effect = [
        MagicMock(scalar_one_or_none=MagicMock(return_value=post)),
        MagicMock(
            scalars=MagicMock(
                return_value=MagicMock(all=MagicMock(return_value=[comment]))
            )
        ),
    ]
    app.dependency_overrides[get_db] = lambda: db

    data = client.get(f"/posts/{post.id}/comments").json()[0]

    assert set(data) == {
        "id",
        "author_name",
        "author_avatar_url",
        "body",
        "created_at",
        "updated_at",
    }


def test_create_comment_uses_profile_and_updates_count_in_one_commit():
    post = make_post(comment_count=2)
    user, db = override_user_and_db(post=post)
    timeline = MagicMock()
    timeline.attach_mock(db.connection.return_value.exec_driver_sql, "advisory")
    timeline.attach_mock(db.execute, "execute")

    def refresh(instance):
        if isinstance(instance, Comment):
            instance.id = uuid.uuid4()
            instance.created_at = datetime.now(timezone.utc)
            instance.updated_at = instance.created_at

    db.refresh.side_effect = refresh

    response = client.post(
        f"/posts/{post.id}/comments", json={"body": "  Thank you!  "}
    )

    assert response.status_code == 201
    comment = db.add.call_args.args[0]
    assert comment.post_id == post.id
    assert comment.author_id == user.id
    assert comment.author_name == "Rowan"
    assert comment.author_avatar_url is None
    assert comment.body == "Thank you!"
    assert post.comment_count == 3
    assert response.json()["comment_count"] == 3
    db.commit.assert_called_once_with()
    sql = str(db.execute.call_args.args[0]).lower()
    assert "for update" in sql
    assert "is_published is true" in sql
    assert "is_hidden is false" in sql
    assert [call[0] for call in timeline.method_calls[:2]] == [
        "advisory",
        "execute",
    ]


def test_create_comment_requires_authentication():
    db = MagicMock()
    app.dependency_overrides[get_db] = lambda: db

    response = client.post(
        f"/posts/{uuid.uuid4()}/comments", json={"body": "Comment"}
    )

    assert response.status_code == 401


def test_create_comment_returns_409_without_profile():
    post = make_post()
    _, db = override_user_and_db(profile=False, post=post)

    response = client.post(f"/posts/{post.id}/comments", json={"body": "Comment"})

    assert response.status_code == 409
    db.add.assert_not_called()


def test_create_comment_returns_404_for_missing_or_unpublished_post():
    post_id = uuid.uuid4()
    _, db = override_user_and_db(post=None)

    response = client.post(f"/posts/{post_id}/comments", json={"body": "Comment"})

    assert response.status_code == 404
    db.add.assert_not_called()
    db.commit.assert_not_called()


def test_create_comment_hidden_parent_uses_generic_not_found_without_mutation():
    post_id = uuid.uuid4()
    _, db = override_user_and_db(post=None)

    response = client.post(f"/posts/{post_id}/comments", json={"body": "Comment"})

    assert response.status_code == 404
    assert response.json() == {"detail": "Post not found"}
    assert "is_hidden is false" in str(db.execute.call_args.args[0]).lower()
    db.add.assert_not_called()
    db.commit.assert_not_called()


@pytest.mark.parametrize("body", ["", "   ", "x" * 2001])
def test_create_comment_validates_body(body):
    post = make_post()
    override_user_and_db(post=post)

    response = client.post(f"/posts/{post.id}/comments", json={"body": body})

    assert response.status_code == 422


@pytest.mark.parametrize(
    "field",
    [
        "id",
        "post_id",
        "author_id",
        "author_name",
        "author_avatar_url",
        "reaction_count",
        "report_count",
        "is_hidden",
        "created_at",
        "updated_at",
    ],
)
def test_create_comment_strictly_rejects_internal_fields(field):
    post = make_post()
    override_user_and_db(post=post)

    response = client.post(
        f"/posts/{post.id}/comments", json={"body": "Comment", field: True}
    )

    assert response.status_code == 422


def test_create_comment_rolls_back_count_and_returns_controlled_conflict():
    post = make_post(comment_count=2)
    _, db = override_user_and_db(post=post)
    db.commit.side_effect = IntegrityError("statement", {}, Exception("db"))

    response = client.post(f"/posts/{post.id}/comments", json={"body": "Comment"})

    assert response.status_code == 409
    db.rollback.assert_called_once_with()
    assert response.json()["detail"] == (
        "The comment could not be created because of a data conflict."
    )
