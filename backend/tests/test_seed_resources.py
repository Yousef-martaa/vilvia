from unittest.mock import MagicMock, patch

import pytest

from scripts.seed_resources import SEED_RECORDS, _resource_id, seed_resources


def mock_session_returning(existing_ids):
    mock_db = MagicMock()
    mock_db.execute.return_value.scalars.return_value.all.return_value = existing_ids
    return mock_db


def test_seed_resources_inserts_all_when_none_exist():
    mock_db = mock_session_returning([])

    with patch("scripts.seed_resources.SessionLocal", return_value=mock_db):
        inserted = seed_resources()

    assert len(inserted) == len(SEED_RECORDS)
    assert mock_db.add.call_count == len(SEED_RECORDS)
    added_resources = [call.args[0] for call in mock_db.add.call_args_list]
    assert all(resource.is_published is True for resource in added_resources)
    mock_db.commit.assert_called_once()
    mock_db.close.assert_called_once()


def test_seed_resources_skips_existing_records():
    already_seeded_ids = [_resource_id(record["key"]) for record in SEED_RECORDS]
    mock_db = mock_session_returning(already_seeded_ids)

    with patch("scripts.seed_resources.SessionLocal", return_value=mock_db):
        inserted = seed_resources()

    assert inserted == []
    mock_db.add.assert_not_called()
    mock_db.commit.assert_called_once()
    mock_db.close.assert_called_once()


def test_seed_resources_rolls_back_on_failure():
    mock_db = mock_session_returning([])
    mock_db.commit.side_effect = RuntimeError("db error")

    with patch("scripts.seed_resources.SessionLocal", return_value=mock_db):
        with pytest.raises(RuntimeError):
            seed_resources()

    mock_db.rollback.assert_called_once()
    mock_db.close.assert_called_once()
