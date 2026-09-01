import uuid
from types import SimpleNamespace
from unittest.mock import MagicMock

from pydantic import SecretStr

from app.models.enums import AccountDeletionStatus
from scripts import fulfill_account_deletions as script


def test_operator_command_requires_service_role_secret(monkeypatch, capsys):
    monkeypatch.setattr(script.settings, "supabase_service_role_key", None)

    result = script.main([str(uuid.uuid4())])

    assert result == 2
    assert "SUPABASE_SERVICE_ROLE_KEY is required" in capsys.readouterr().err


def test_operator_command_fulfills_and_purges_without_printing_user_id(
    monkeypatch, capsys
):
    user_id = uuid.uuid4()
    db = MagicMock()
    admin = MagicMock()
    monkeypatch.setattr(
        script.settings, "supabase_service_role_key", SecretStr("secret")
    )
    purge_db = MagicMock()
    monkeypatch.setattr(
        script, "SessionLocal", MagicMock(side_effect=[db, purge_db])
    )
    monkeypatch.setattr(script, "SupabaseAuthAdmin", MagicMock(return_value=admin))
    fulfill = MagicMock(
        return_value=SimpleNamespace(status=AccountDeletionStatus.completed)
    )
    monkeypatch.setattr(script, "fulfill_account_deletion", fulfill)
    monkeypatch.setattr(script, "purge_completed_requests", MagicMock(return_value=1))

    result = script.main([str(user_id)])

    assert result == 0
    fulfill.assert_called_once_with(db, user_id, admin.delete_user)
    output = capsys.readouterr().out
    assert "completed" in output
    assert str(user_id) not in output
    db.close.assert_called_once_with()
    purge_db.close.assert_called_once_with()
    admin.close.assert_called_once_with()


def test_purge_mode_needs_no_supabase_secret(monkeypatch):
    db = MagicMock()
    monkeypatch.setattr(script.settings, "supabase_service_role_key", None)
    monkeypatch.setattr(script, "SessionLocal", MagicMock(return_value=db))
    purge = MagicMock(return_value=2)
    monkeypatch.setattr(script, "purge_completed_requests", purge)

    result = script.main(["--purge-completed"])

    assert result == 0
    purge.assert_called_once_with(
        db,
        script.settings.account_deletion_completed_retention_days,
        max_access_token_lifetime_seconds=(
            script.settings.supabase_access_token_max_lifetime_seconds
        ),
        jwt_clock_skew_seconds=script.settings.supabase_jwt_clock_skew_seconds,
    )
    db.close.assert_called_once_with()


def test_operator_failure_is_generic_and_retryable(monkeypatch, capsys):
    db = MagicMock()
    admin = MagicMock()
    monkeypatch.setattr(
        script.settings, "supabase_service_role_key", SecretStr("secret")
    )
    monkeypatch.setattr(script, "SessionLocal", MagicMock(return_value=db))
    monkeypatch.setattr(script, "SupabaseAuthAdmin", MagicMock(return_value=admin))
    monkeypatch.setattr(
        script,
        "fulfill_account_deletion",
        MagicMock(side_effect=RuntimeError("private@example.com secret")),
    )

    result = script.main([str(uuid.uuid4())])

    assert result == 1
    error = capsys.readouterr().err
    assert "remains retryable" in error
    assert "private@example.com" not in error
    assert "secret" not in error
    db.close.assert_called_once_with()
    admin.close.assert_called_once_with()


def test_purge_failure_does_not_report_completed_deletion_as_failed(
    monkeypatch, capsys
):
    db = MagicMock()
    purge_db = MagicMock()
    admin = MagicMock()
    monkeypatch.setattr(
        script.settings, "supabase_service_role_key", SecretStr("secret")
    )
    monkeypatch.setattr(
        script, "SessionLocal", MagicMock(side_effect=[db, purge_db])
    )
    monkeypatch.setattr(script, "SupabaseAuthAdmin", MagicMock(return_value=admin))
    monkeypatch.setattr(
        script,
        "fulfill_account_deletion",
        MagicMock(
            return_value=SimpleNamespace(status=AccountDeletionStatus.completed)
        ),
    )
    monkeypatch.setattr(
        script,
        "purge_completed_requests",
        MagicMock(side_effect=RuntimeError("maintenance failure")),
    )

    result = script.main([str(uuid.uuid4())])

    output = capsys.readouterr()
    assert result == 1
    assert "Account deletion state: completed" in output.out
    assert "deletion completed" in output.err
    assert "deletion failed" not in output.err
