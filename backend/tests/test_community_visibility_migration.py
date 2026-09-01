from importlib import import_module
from unittest.mock import MagicMock

from alembic.config import Config
from alembic.script import ScriptDirectory


migration = import_module(
    "migrations.versions.e6a1c4f9b207_add_community_visibility"
)


def test_visibility_migration_is_current_head():
    scripts = ScriptDirectory.from_config(Config("alembic.ini"))
    assert scripts.get_current_head() == migration.revision


def test_upgrade_adds_non_nullable_false_columns(monkeypatch):
    operations = MagicMock()
    monkeypatch.setattr(migration, "op", operations)
    migration.upgrade()

    calls = operations.add_column.call_args_list
    assert [call.args[0] for call in calls] == ["posts", "comments"]
    for call in calls:
        column = call.args[1]
        assert column.name == "is_hidden"
        assert column.nullable is False
        assert str(column.server_default.arg).lower() == "false"
    operations.execute.assert_not_called()


def test_downgrade_only_drops_visibility_columns(monkeypatch):
    operations = MagicMock()
    monkeypatch.setattr(migration, "op", operations)
    migration.downgrade()

    assert [call.args for call in operations.drop_column.call_args_list] == [
        ("comments", "is_hidden"),
        ("posts", "is_hidden"),
    ]
    assert [call[0] for call in operations.method_calls] == [
        "drop_column",
        "drop_column",
    ]
