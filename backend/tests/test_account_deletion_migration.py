from importlib import import_module
from unittest.mock import MagicMock

from alembic.config import Config
from alembic.script import ScriptDirectory


migration = import_module(
    "migrations.versions.f4c9d2a7e105_add_account_deletion_requests"
)


def test_account_deletion_migration_is_current_single_head():
    scripts = ScriptDirectory.from_config(Config("alembic.ini"))
    assert scripts.get_heads() == [migration.revision]
    assert migration.down_revision == "e6a1c4f9b207"


def test_upgrade_creates_durable_non_profile_linked_state(monkeypatch):
    operations = MagicMock()
    monkeypatch.setattr(migration, "op", operations)

    migration.upgrade()

    table_call = operations.create_table.call_args
    assert table_call.args[0] == "account_deletion_requests"
    columns = {
        column.name: column
        for column in table_call.args[1:]
        if column.__class__.__name__ == "Column"
    }
    assert set(columns) == {
        "user_id",
        "status",
        "requested_at",
        "auth_deleted_at",
        "completed_at",
        "updated_at",
    }
    assert columns["user_id"].nullable is False
    assert columns["status"].nullable is False
    assert str(columns["status"].server_default.arg) == "'requested'"
    assert list(columns["status"].type.enums) == [
        "requested",
        "auth_deleted",
        "completed",
    ]
    # No FK is intentional: the recovery row must outlive Profile cleanup.
    assert not columns["user_id"].foreign_keys
    constraints = {
        item.name: str(item.sqltext).lower()
        for item in table_call.args[1:]
        if item.__class__.__name__ == "CheckConstraint"
    }
    lifecycle = constraints["account_deletion_requests_lifecycle_check"]
    assert "status = 'requested'" in lifecycle
    assert "status = 'auth_deleted'" in lifecycle
    assert "status = 'completed'" in lifecycle


def test_downgrade_only_removes_account_deletion_table(monkeypatch):
    operations = MagicMock()
    monkeypatch.setattr(migration, "op", operations)

    migration.downgrade()

    operations.drop_table.assert_called_once_with("account_deletion_requests")
    assert [call[0] for call in operations.method_calls] == ["drop_table"]
