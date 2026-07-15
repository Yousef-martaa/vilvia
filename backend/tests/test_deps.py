from unittest.mock import MagicMock, patch

from app.api.deps import get_db


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
