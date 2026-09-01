import inspect
import uuid
from unittest.mock import MagicMock, call, patch

import pytest
from fastapi import HTTPException

from app.api.deps import AuthenticatedUser, get_db, require_admin
from app.models.enums import UserRole
from app.models.account_deletion_request import AccountDeletionRequest
from app.models.profile import Profile


def test_get_db_yields_session():
    mock_session = MagicMock()
    with patch("app.api.deps.SessionLocal", return_value=mock_session):
        gen = get_db()
        db = next(gen)
        assert db is mock_session


def test_get_db_closes_session_on_completion():
    mock_session = MagicMock()
    with patch("app.api.deps.SessionLocal", return_value=mock_session):
        gen = get_db()
        next(gen)
        try:
            next(gen)
        except StopIteration:
            pass
        mock_session.close.assert_called_once()


def test_get_db_closes_session_on_exception():
    mock_session = MagicMock()
    with patch("app.api.deps.SessionLocal", return_value=mock_session):
        gen = get_db()
        next(gen)
        try:
            gen.throw(Exception("simulated request error"))
        except Exception:
            pass
        mock_session.close.assert_called_once()


# --- require_admin ------------------------------------------------------


def _make_user():
    return AuthenticatedUser(id=uuid.uuid4(), email="someone@example.com")


def test_require_admin_allows_an_admin_profile():
    user = _make_user()
    admin_profile = MagicMock(role=UserRole.admin)
    mock_db = MagicMock()
    mock_db.get.side_effect = lambda model, _id: (
        admin_profile if model is Profile else None
    )

    result = require_admin(current_user=user, db=mock_db)

    assert result is admin_profile
    # Resolved server-side from the verified identity, not from any
    # client-supplied value.
    assert mock_db.get.call_args_list == [
        call(Profile, user.id),
        call(AccountDeletionRequest, user.id),
    ]


def test_require_admin_rejects_a_non_admin_profile():
    user = _make_user()
    parent_profile = MagicMock(role=UserRole.parent)
    mock_db = MagicMock()
    mock_db.get.return_value = parent_profile

    with pytest.raises(HTTPException) as exc_info:
        require_admin(current_user=user, db=mock_db)

    assert exc_info.value.status_code == 403


def test_require_admin_rejects_a_missing_profile():
    user = _make_user()
    mock_db = MagicMock()
    mock_db.get.return_value = None

    with pytest.raises(HTTPException) as exc_info:
        require_admin(current_user=user, db=mock_db)

    assert exc_info.value.status_code == 403


def test_require_admin_never_trusts_client_supplied_role():
    # require_admin takes no request body/role input at all -- the only
    # way it can decide "admin" is by resolving the Profile itself from
    # the verified identity. This test documents that there is no
    # parameter here a caller could use to assert their own role.
    params = inspect.signature(require_admin).parameters
    assert set(params) == {"current_user", "db"}
