"""Tests for the provider-agnostic sync/upsert engine.

These are mock/fake-based unit tests of the orchestration and
change-detection logic (counting, provider-failure handling, lock-skip
handling, and the commit-before-fetch ordering) -- the same style used
elsewhere in this test suite (see test_resources.py, test_seed_resources.py).
Genuine Postgres-level behavior this module also depends on (SAVEPOINT
rollback isolation, `INSERT ... ON CONFLICT` atomicity, session-level
advisory-lock cross-process exclusion) is verified by actually running
`scripts/sync_medlineplus.py` against a real local database, not by these
mocks -- a fake session cannot meaningfully prove real transactional
behavior.
"""

import uuid
from contextlib import nullcontext
from types import SimpleNamespace
from typing import ClassVar

from app.models.enums import ResourceCategory, ResourceStage
from app.models.resource import Resource
from app.providers.base import NormalizedResource, ResourceProvider
from app.services.resource_sync import EXTERNAL_RESOURCE_NAMESPACE, _changed, sync_provider


def _candidate(**overrides) -> NormalizedResource:
    defaults = dict(
        external_id="https://medlineplus.gov/example.html",
        title="Example Title",
        summary="Example summary.",
        body="Example body.",
        category=ResourceCategory.sleep,
        stage=ResourceStage.months_0_6,
        source_name="MedlinePlus.gov",
        source_url="https://medlineplus.gov/example.html",
    )
    defaults.update(overrides)
    return NormalizedResource(**defaults)


def _resource_from(candidate: NormalizedResource, resource_id: uuid.UUID) -> Resource:
    return Resource(
        id=resource_id,
        title=candidate.title,
        summary=candidate.summary,
        body=candidate.body,
        category=candidate.category,
        stage=candidate.stage,
        source_name=candidate.source_name,
        source_url=candidate.source_url,
        is_published=True,
    )


def _resource_id(provider_name: str, candidate: NormalizedResource) -> uuid.UUID:
    return uuid.uuid5(EXTERNAL_RESOURCE_NAMESPACE, f"{provider_name}:{candidate.external_id}")


class FakeProvider(ResourceProvider):
    name: ClassVar[str] = "testprov"

    def __init__(self, candidates=None, error=None, events=None):
        self._candidates = candidates or []
        self._error = error
        self.fetch_calls = 0
        self.events = events if events is not None else []

    def fetch(self):
        self.fetch_calls += 1
        self.events.append("fetch")
        if self._error is not None:
            raise self._error
        return self._candidates


class FakeSession:
    """Just enough of the Session interface for sync_provider's orchestration,
    with explicit, inspectable behavior instead of a MagicMock's opacity."""

    def __init__(self, existing_by_id=None, lock_acquired=True, events=None):
        self._existing_by_id = dict(existing_by_id or {})
        self._lock_acquired = lock_acquired
        self.inserted_statements = []
        self.commit_calls = 0
        self.rollback_calls = 0
        self.lock_calls = 0
        self.unlock_calls = 0
        self.events = events if events is not None else []

    def execute(self, stmt):
        sql = str(stmt)
        if "pg_try_advisory_lock" in sql:
            self.lock_calls += 1
            self.events.append("lock")
            return SimpleNamespace(scalar=lambda: self._lock_acquired)
        if "pg_advisory_unlock" in sql:
            self.unlock_calls += 1
            self.events.append("unlock")
            return SimpleNamespace(scalar=lambda: True)
        self.inserted_statements.append(stmt)
        self.events.append("insert")
        return SimpleNamespace(scalar=lambda: None)

    def get(self, _model, pk):
        return self._existing_by_id.get(pk)

    def begin_nested(self):
        return nullcontext()

    def flush(self):
        pass

    def commit(self):
        self.commit_calls += 1
        self.events.append("commit")

    def rollback(self):
        self.rollback_calls += 1
        self.events.append("rollback")


# --- _changed ------------------------------------------------------------


def test_changed_is_false_for_identical_fields():
    candidate = _candidate()
    existing = _resource_from(candidate, uuid.uuid4())
    assert _changed(existing, candidate) is False


def test_changed_is_true_when_a_tracked_field_differs():
    candidate = _candidate()
    existing = _resource_from(candidate, uuid.uuid4())
    existing.title = "A different title"
    assert _changed(existing, candidate) is True


# --- sync_provider: counting ----------------------------------------------


def test_unchanged_row_is_counted_and_not_written():
    candidate = _candidate()
    resource_id = _resource_id(FakeProvider.name, candidate)
    existing = _resource_from(candidate, resource_id)
    session = FakeSession(existing_by_id={resource_id: existing})

    result = sync_provider(session, FakeProvider([candidate]), publish=True)

    assert result.unchanged == 1
    assert result.inserted == 0
    assert result.updated == 0
    assert session.inserted_statements == []  # no ON CONFLICT insert issued
    assert session.commit_calls >= 1


def test_changed_row_is_updated_in_place():
    candidate = _candidate(title="New title from upstream")
    resource_id = _resource_id(FakeProvider.name, candidate)
    existing = _resource_from(candidate, resource_id)
    existing.title = "Stale title"
    session = FakeSession(existing_by_id={resource_id: existing})

    result = sync_provider(session, FakeProvider([candidate]), publish=True)

    assert result.updated == 1
    assert result.unchanged == 0
    assert existing.title == "New title from upstream"


def test_new_row_is_inserted():
    candidate = _candidate()
    session = FakeSession(existing_by_id={})

    result = sync_provider(session, FakeProvider([candidate]), publish=True)

    assert result.inserted == 1
    assert len(session.inserted_statements) == 1


# --- sync_provider: transaction/lock lifecycle ----------------------------


def test_lock_transaction_is_committed_before_fetch_and_persistence_after():
    events: list[str] = []
    candidate = _candidate()
    session = FakeSession(existing_by_id={}, events=events)
    provider = FakeProvider([candidate], events=events)

    sync_provider(session, provider, publish=True)

    # The lock-acquisition transaction must be committed *before* fetch()
    # runs -- fetch() performs external HTTP calls and must never run with
    # a DB transaction held open -- and the persistence work (insert) must
    # only happen *after* fetch() returns.
    assert events.index("lock") < events.index("commit") < events.index("fetch")
    assert events.index("fetch") < events.index("insert")


def test_provider_failure_leaves_database_untouched():
    session = FakeSession()
    provider = FakeProvider(error=RuntimeError("medlineplus is down"))

    result = sync_provider(session, provider, publish=True)

    assert result.provider_failed is True
    assert session.inserted_statements == []
    # lock acquired and released symmetrically even on failure
    assert session.lock_calls == 1
    assert session.unlock_calls == 1


def test_lock_not_acquired_skips_without_calling_provider():
    session = FakeSession(lock_acquired=False)
    provider = FakeProvider([_candidate()])

    result = sync_provider(session, provider, publish=True)

    assert result.skipped_locked is True
    assert provider.fetch_calls == 0
    assert session.inserted_statements == []
    # never held the lock, so never attempts to release it
    assert session.unlock_calls == 0


def test_lock_is_released_even_when_final_commit_raises():
    class ExplodingSession(FakeSession):
        def commit(self):
            super().commit()
            if self.commit_calls == 2:
                # 1st commit = ending the lock-acquisition transaction
                # (must succeed); 2nd commit = the final persistence
                # commit -- simulate *that* one failing.
                raise RuntimeError("connection lost")

    session = ExplodingSession(existing_by_id={})
    provider = FakeProvider([_candidate()])

    try:
        sync_provider(session, provider, publish=True)
        raised = False
    except RuntimeError:
        raised = True

    assert raised is True
    # The lock must still have been released despite the commit failure.
    assert session.lock_calls == 1
    assert session.unlock_calls == 1


def test_publish_flag_is_only_applied_to_new_rows():
    candidate = _candidate()
    session = FakeSession(existing_by_id={})

    sync_provider(session, FakeProvider([candidate]), publish=True)

    insert_values = session.inserted_statements[0].compile().params
    assert insert_values["is_published"] is True
