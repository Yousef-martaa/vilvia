from importlib import import_module
from unittest.mock import MagicMock

from alembic.config import Config
from alembic.script import ScriptDirectory


migration = import_module(
    "migrations.versions.fecdb3c7a299_add_profile_last_name_and_parent_role"
)


def test_profile_migration_is_current_single_head():
    scripts = ScriptDirectory.from_config(Config("alembic.ini"))
    assert scripts.get_heads() == [migration.revision]
    assert migration.down_revision == "f4c9d2a7e105"


def test_upgrade_adds_nullable_columns(monkeypatch):
    operations = MagicMock()
    monkeypatch.setattr(migration, "op", operations)

    migration.upgrade()

    assert operations.add_column.call_count == 2
    calls = operations.add_column.call_args_list

    table_1, col_1 = calls[0].args
    assert table_1 == "profiles"
    assert col_1.name == "last_name"
    assert col_1.nullable is True

    table_2, col_2 = calls[1].args
    assert table_2 == "profiles"
    assert col_2.name == "parent_role"
    assert col_2.nullable is True


def test_downgrade_removes_columns_cleanly(monkeypatch):
    operations = MagicMock()
    monkeypatch.setattr(migration, "op", operations)

    migration.downgrade()

    assert operations.drop_column.call_count == 2
    calls = operations.drop_column.call_args_list

    assert calls[0].args == ("profiles", "parent_role")
    assert calls[1].args == ("profiles", "last_name")
