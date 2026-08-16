"""The provider boundary: everything outside `app/providers/` deals only in
`NormalizedResource` and `ResourceProvider.fetch()`. No provider-specific
field names, request/response formats, or error types cross this line.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import ClassVar

from app.models.enums import ResourceCategory, ResourceStage


@dataclass(frozen=True)
class NormalizedResource:
    """A candidate resource in Vilvia's own shape, independent of whichever
    external provider produced it.

    `external_id` is the provider's own stable identifier for this content
    (for MedlinePlus, its topic URL) -- kept distinct from `source_url`
    (the attribution link shown to users) since a future provider's stable
    identifier might not be a URL at all.
    """

    external_id: str
    title: str
    summary: str
    body: str
    category: ResourceCategory
    stage: ResourceStage
    source_name: str
    source_url: str


class ResourceProvider(ABC):
    """One external trusted content source.

    Implementations own their own discovery (deciding what's relevant),
    ingestion (fetching it), and normalization (converting it into
    `NormalizedResource`) internally. `fetch()` is the only thing callers
    ever see.
    """

    name: ClassVar[str]

    @abstractmethod
    def fetch(self) -> list[NormalizedResource]:
        """Return this provider's current candidate resources.

        Must not raise for partial/expected failure modes (a single query
        timing out, one malformed response, etc.) -- those should be caught
        and logged internally, simply omitting that batch of results.
        Raising is reserved for total, unexpected failure.
        """
        raise NotImplementedError
