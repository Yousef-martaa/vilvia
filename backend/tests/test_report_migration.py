from importlib import import_module
from unittest.mock import MagicMock

from alembic.config import Config
from alembic.script import ScriptDirectory


migration = import_module(
    "migrations.versions.b83c2d9e4f10_harden_community_reports"
)


def _upgrade_sql(monkeypatch) -> str:
    operations = MagicMock()
    monkeypatch.setattr(migration, "op", operations)
    migration.upgrade()
    return "\n".join(str(call.args[0]) for call in operations.execute.call_args_list)


def test_reporting_migration_is_followed_by_visibility_migration():
    config = Config("alembic.ini")
    scripts = ScriptDirectory.from_config(config)
    assert scripts.get_revision(migration.revision).nextrev == {"e6a1c4f9b207"}


def test_valid_legacy_targets_are_migrated_and_counts_recalculated(monkeypatch):
    sql = _upgrade_sql(monkeypatch).lower()

    assert "set post_id = target_id where target_type = 'post'" in sql
    assert "set comment_id = target_id where target_type = 'comment'" in sql
    assert "update posts" in sql and "where r.post_id = p.id" in sql
    assert "update comments" in sql and "where r.comment_id = c.id" in sql


def test_invalid_legacy_data_aborts_instead_of_being_discarded(monkeypatch):
    sql = _upgrade_sql(monkeypatch).lower()

    assert "orphaned reported_by value" in sql
    assert "orphaned report target" in sql
    assert "duplicate reporter and target" in sql
    assert "raise exception" in sql
    assert "delete from reports" not in sql


def test_migration_adds_integrity_constraints_before_dropping_legacy_columns(
    monkeypatch,
):
    operations = MagicMock()
    monkeypatch.setattr(migration, "op", operations)
    migration.upgrade()

    foreign_keys = {
        call.args[0]: call.kwargs.get("ondelete")
        for call in operations.create_foreign_key.call_args_list
    }
    assert foreign_keys == {
        "reports_post_id_fkey": "CASCADE",
        "reports_comment_id_fkey": "CASCADE",
        "reports_reported_by_fkey": "RESTRICT",
    }
    dropped = [call.args[1] for call in operations.drop_column.call_args_list]
    assert dropped == ["target_type", "target_id"]
