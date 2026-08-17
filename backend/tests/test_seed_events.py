from unittest.mock import MagicMock, patch

from scripts.seed_events import SEED_NAMESPACE, _event_id, _seed_records, seed_events
from datetime import datetime, timezone


def mock_session_returning(existing_events):
    mock_db = MagicMock()
    mock_db.execute.return_value.scalars.return_value.all.return_value = existing_events
    return mock_db


def test_seed_events_inserts_all_when_none_exist():
    mock_db = mock_session_returning([])

    with patch("scripts.seed_events.SessionLocal", return_value=mock_db):
        touched = seed_events()

    records = _seed_records(datetime.now(timezone.utc))
    assert len(touched) == len(records)
    assert mock_db.add.call_count == len(records)
    added_events = [call.args[0] for call in mock_db.add.call_args_list]
    assert all(event.is_published is True for event in added_events)
    mock_db.commit.assert_called_once()
    mock_db.close.assert_called_once()


def test_seed_events_refreshes_dates_on_already_seeded_records():
    records = _seed_records(datetime.now(timezone.utc))
    existing_events = []
    for record in records:
        existing = MagicMock()
        existing.id = _event_id(record["key"])
        # Simulate a stale date from a previous seed run, long past.
        existing.starts_at = datetime(2020, 1, 1, tzinfo=timezone.utc)
        existing_events.append(existing)
    mock_db = mock_session_returning(existing_events)

    with patch("scripts.seed_events.SessionLocal", return_value=mock_db):
        touched = seed_events()

    # Refreshed, not skipped: no new rows added, but every existing row's
    # starts_at was updated away from the stale 2020 date.
    assert len(touched) == len(records)
    mock_db.add.assert_not_called()
    for existing in existing_events:
        assert existing.starts_at.year != 2020
    mock_db.commit.assert_called_once()
    mock_db.close.assert_called_once()


def test_seed_events_rolls_back_on_failure():
    mock_db = mock_session_returning([])
    mock_db.commit.side_effect = RuntimeError("db error")

    with patch("scripts.seed_events.SessionLocal", return_value=mock_db):
        try:
            seed_events()
            raised = False
        except RuntimeError:
            raised = True

    assert raised is True
    mock_db.rollback.assert_called_once()
    mock_db.close.assert_called_once()


def test_event_ids_are_deterministic_and_namespaced():
    assert _event_id("parent-baby-playgroup") == _event_id("parent-baby-playgroup")
    assert _event_id("parent-baby-playgroup") != _event_id("new-parents-meetup")
    # Sanity check it's actually derived from the fixed namespace, not a
    # random default.
    import uuid

    assert _event_id("parent-baby-playgroup") == uuid.uuid5(
        SEED_NAMESPACE, "parent-baby-playgroup"
    )
