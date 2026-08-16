"""Provider-agnostic persistence/cache layer for externally-sourced
resources.

This is the one piece of the ingestion pipeline every provider shares:
`sync_provider(db, provider, publish=...)` takes any `ResourceProvider`,
fetches its current candidates, and upserts them into `resources`. Nothing
here knows about MedlinePlus, XML, or HTTP -- it only deals in
`NormalizedResource`.

Non-destructive by design: this only ever inserts/updates rows for
candidates the provider actually returns this run. It never deletes rows,
so a provider that returns nothing (e.g. because it's down) simply results
in zero writes -- every previously-synced resource is left exactly as it
was. Callers never need to special-case "the provider failed" to protect
existing data; the upsert-only semantics do that automatically.
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass, field

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.models.resource import Resource
from app.providers.base import NormalizedResource, ResourceProvider

log = logging.getLogger(__name__)

# Fixed namespace for deriving deterministic resource ids from
# "<provider.name>:<candidate.external_id>". Do not change this value --
# doing so would make every previously-synced external resource look "new"
# on the next run and re-insert it under a different id.
EXTERNAL_RESOURCE_NAMESPACE = uuid.UUID("36840f00-19da-4132-94c7-7a0137f8e411")

# Advisory lock key used to stop two sync runs (e.g. an overlapping cron
# invocation) from executing concurrently against the same database. This
# is a Postgres session-level lock, visible to every connection to this
# database -- not just within one process -- so it correctly prevents
# overlap between separate OS processes/hosts, not merely threads.
_SYNC_LOCK_KEY = 987_654_321

_TRACKED_FIELDS = (
    "title",
    "summary",
    "body",
    "category",
    "stage",
    "source_name",
    "source_url",
)


@dataclass
class SyncResult:
    inserted: int = 0
    updated: int = 0
    unchanged: int = 0
    failed: int = 0
    provider_failed: bool = False
    skipped_locked: bool = False
    errors: list[str] = field(default_factory=list)


def sync_provider(db: Session, provider: ResourceProvider, *, publish: bool) -> SyncResult:
    """Fetch `provider`'s current candidates and upsert them into `resources`.

    Lock/transaction lifecycle (in order):
      1. Acquire the PostgreSQL SESSION-level advisory lock
         (`pg_try_advisory_lock`) and immediately commit the transaction
         that was auto-begun to issue it. Session-level advisory locks are
         explicitly unaffected by COMMIT/ROLLBACK -- they stay held by
         this DB session regardless -- so this commit only ends the
         transaction, not the lock.
      2. Call `provider.fetch()` with *no* DB transaction open. This is
         the whole point of step 1: `fetch()` makes multiple external HTTP
         requests, and a DB transaction (let alone one holding a
         transaction-level lock) must never sit open across that external,
         slow, failure-prone I/O.
      3. Upsert the results in their own, separate persistence transaction.
      4. Commit the persistence transaction.
      5. Release the advisory lock in `finally`, regardless of how the run
         ended.

    Transaction semantics for step 3: one outer transaction for the whole
    persistence phase. Each candidate is applied inside its own SAVEPOINT
    (`Session.begin_nested`). If a single candidate fails (e.g. an
    unexpected constraint violation), only *that* SAVEPOINT is rolled back
    -- automatically, by the nested transaction's own context manager --
    while every previously-applied candidate in this run remains staged in
    the outer transaction. The outer transaction is committed once, after
    every candidate has been processed. This is deliberately not a single
    all-or-nothing transaction: one bad row must not discard an otherwise
    -successful run.

    Concurrency: the advisory lock ensures only one sync for this database
    runs at a time (a second overlapping invocation returns immediately
    with `skipped_locked=True` and touches nothing). This is a PostgreSQL
    SESSION-level lock, visible to every connection to this database --
    it correctly prevents overlap between separate OS processes/hosts
    sharing the same database, not merely threads within one process. As
    defense in depth, each insert also uses `INSERT ... ON CONFLICT DO
    UPDATE` keyed on the deterministic id, so even in the rare case two
    processes both discover the same brand-new resource at the same
    moment (e.g. if the lock were somehow bypassed), Postgres resolves the
    conflict atomically -- no duplicate row, no crash. What this does
    *not* guarantee under a lock-bypassing race is exact inserted/updated
    bookkeeping for that specific brand-new-resource collision; it only
    guarantees no data corruption. The advisory lock is what actually
    prevents overlap; the deployment scheduler should still avoid
    triggering overlapping runs as the primary safeguard.

    Lock release is unconditional and cannot mask a failure from this
    function: `_release_lock` catches and logs its own errors rather than
    raising, so a problem releasing the lock never replaces or hides
    whatever this function was already returning/raising because of a
    fetch, upsert, or commit failure.
    """
    acquired = db.execute(select(func.pg_try_advisory_lock(_SYNC_LOCK_KEY))).scalar()
    if not acquired:
        # Nothing of ours to clean up -- end this trivial transaction and
        # bail out without ever holding the lock.
        db.commit()
        log.warning("%s: another sync is already running, skipping", provider.name)
        return SyncResult(skipped_locked=True)

    try:
        # Step 1: end the transaction used to acquire the lock. The lock
        # itself survives (see docstring above).
        db.commit()

        # Step 2: external HTTP work, deliberately with no DB transaction
        # open.
        try:
            candidates = provider.fetch()
        except Exception:
            log.exception("%s: fetch failed entirely", provider.name)
            return SyncResult(provider_failed=True)

        # Step 3 + 4: persistence transaction.
        result = SyncResult()
        for candidate in candidates:
            resource_id = uuid.uuid5(
                EXTERNAL_RESOURCE_NAMESPACE, f"{provider.name}:{candidate.external_id}"
            )
            try:
                outcome = _upsert_one(db, resource_id, candidate, publish=publish)
            except SQLAlchemyError as exc:
                # The `with db.begin_nested()` block inside `_upsert_one`
                # has already rolled back only this candidate's SAVEPOINT.
                # The outer transaction (and every prior successful
                # candidate in it) is untouched.
                log.exception(
                    "%s: failed to upsert %s", provider.name, candidate.source_url
                )
                result.failed += 1
                result.errors.append(f"{candidate.source_url}: {exc}")
                continue

            setattr(result, outcome, getattr(result, outcome) + 1)

        db.commit()
        return result
    finally:
        # Step 5: always attempt to release the lock -- on the success
        # path above, on a `return` from the fetch-failure branch, or if
        # `db.commit()` itself raises and propagates out of this `try`.
        _release_lock(db)


def _release_lock(db: Session) -> None:
    """Best-effort advisory lock release. Never raises: an error here must
    not replace or hide whatever `sync_provider` was already
    returning/raising.
    """
    try:
        # Clear any aborted-transaction state left behind by a failed
        # commit above, so the unlock statement itself can run. A no-op if
        # there was nothing to roll back.
        db.rollback()
        db.execute(select(func.pg_advisory_unlock(_SYNC_LOCK_KEY)))
        db.commit()
    except Exception:
        log.exception("failed to release advisory lock %s", _SYNC_LOCK_KEY)


def _upsert_one(
    db: Session, resource_id: uuid.UUID, candidate: NormalizedResource, *, publish: bool
) -> str:
    with db.begin_nested():
        existing = db.get(Resource, resource_id)

        if existing is not None:
            if not _changed(existing, candidate):
                return "unchanged"
            for field_name in _TRACKED_FIELDS:
                setattr(existing, field_name, getattr(candidate, field_name))
            db.flush()
            return "updated"

        values = {field_name: getattr(candidate, field_name) for field_name in _TRACKED_FIELDS}
        stmt = (
            pg_insert(Resource)
            .values(id=resource_id, is_published=publish, **values)
            .on_conflict_do_update(
                index_elements=[Resource.id],
                # Deliberately excludes is_published: a resource an admin
                # has manually unpublished must not be silently
                # re-published just because it was seen again upstream.
                set_={**values, "updated_at": func.now()},
            )
        )
        db.execute(stmt)
        return "inserted"


def _changed(existing: Resource, candidate: NormalizedResource) -> bool:
    return any(
        getattr(existing, field_name) != getattr(candidate, field_name)
        for field_name in _TRACKED_FIELDS
    )
