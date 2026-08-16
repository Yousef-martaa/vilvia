"""Adapter for the MedlinePlus Web Service (https://wsearch.nlm.nih.gov/ws/query).

Everything specific to MedlinePlus -- its query parameters, XML response
shape, field names, and attribution requirements -- is isolated here.
Nothing outside this module ever sees MedlinePlus's wire format; callers
only see `MedlinePlusProvider.fetch() -> list[NormalizedResource]`.

Reference: https://medlineplus.gov/about/developers/webservices/
"""

from __future__ import annotations

import logging
import xml.etree.ElementTree as ET
from typing import ClassVar

import httpx

from app.core.settings import settings
from app.models.enums import ResourceCategory, ResourceStage
from app.providers.base import NormalizedResource, ResourceProvider
from app.providers.html_text import html_to_text

log = logging.getLogger(__name__)

_SUMMARY_CHAR_LIMIT = 220


class MedlinePlusUnavailableError(Exception):
    """Raised when every discovery query failed -- treated as a full
    outage, distinct from a normal partial failure (some queries fail,
    others succeed), which is handled silently by returning partial
    results instead.
    """


class MedlinePlusProvider(ResourceProvider):
    name: ClassVar[str] = "medlineplus"
    _SOURCE_NAME: ClassVar[str] = "MedlinePlus.gov"

    # --- Discovery -------------------------------------------------------
    # MedlinePlus has no "browse by category" endpoint -- every query needs
    # a search term. This curated (category, stage, term) list is how
    # Vilvia decides what's relevant; the actual articles/titles/URLs
    # returned for each term are fully dynamic and controlled by
    # MedlinePlus, not us.
    #
    # Order is significant: if the same MedlinePlus URL is returned by more
    # than one term, the FIRST entry below to surface it wins that url's
    # category/stage for this run (see `fetch`). Keep higher-priority/more
    # specific terms earlier. Tunable without touching any other file.
    _QUERIES: ClassVar[list[tuple[ResourceCategory, ResourceStage, str]]] = [
        (ResourceCategory.child_development, ResourceStage.pregnancy, "fetal development"),
        (ResourceCategory.health_safety, ResourceStage.pregnancy, "prenatal care"),
        (ResourceCategory.child_development, ResourceStage.newborn, "newborn development"),
        (ResourceCategory.feeding, ResourceStage.newborn, "breastfeeding"),
        (ResourceCategory.health_safety, ResourceStage.newborn, "newborn care"),
        (ResourceCategory.sleep, ResourceStage.months_0_6, "infant sleep"),
        (ResourceCategory.feeding, ResourceStage.months_0_6, "infant nutrition"),
        (ResourceCategory.child_development, ResourceStage.months_6_12, "infant development"),
        (ResourceCategory.vaccinations, ResourceStage.months_6_12, "child vaccination schedule"),
        (ResourceCategory.health_safety, ResourceStage.months_6_12, "child safety"),
        (ResourceCategory.feeding, ResourceStage.years_1_3, "toddler nutrition"),
        (ResourceCategory.sleep, ResourceStage.years_1_3, "toddler sleep"),
        (ResourceCategory.everyday_guidance, ResourceStage.years_1_3, "toddler health"),
    ]

    def __init__(self, client: httpx.Client | None = None) -> None:
        self._client = client or httpx.Client()
        self._owns_client = client is None

    def close(self) -> None:
        if self._owns_client:
            self._client.close()

    def fetch(self) -> list[NormalizedResource]:
        seen: dict[str, NormalizedResource] = {}
        failures = 0
        for category, stage, term in self._QUERIES:
            try:
                results = self._fetch_term(category, stage, term)
            except (httpx.HTTPError, ET.ParseError) as exc:
                log.warning("medlineplus: query %r failed (%s), skipping", term, exc)
                failures += 1
                continue

            for resource in results:
                # Deterministic classification: keep the first (highest
                # priority) query's category/stage for a given url. Queries
                # run sequentially, in _QUERIES order, specifically so this
                # is reproducible run-to-run rather than depending on
                # network response timing.
                seen.setdefault(resource.external_id, resource)

        if self._QUERIES and failures == len(self._QUERIES):
            # Every single query failed -- almost certainly a full outage
            # or misconfiguration, not just one flaky topic. Surface this
            # distinctly from "MedlinePlus legitimately had nothing new"
            # so sync_provider (and the CLI's exit code) can tell the two
            # apart.
            raise MedlinePlusUnavailableError(
                f"all {failures} MedlinePlus queries failed"
            )

        return list(seen.values())

    # --- Ingestion ---------------------------------------------------

    def _fetch_term(
        self, category: ResourceCategory, stage: ResourceStage, term: str
    ) -> list[NormalizedResource]:
        params = {
            "db": "healthTopics",
            "term": term,
            "rettype": "brief",
            "retmax": str(settings.medlineplus_retmax),
            "tool": settings.medlineplus_tool_name,
        }
        if settings.medlineplus_contact_email:
            params["email"] = settings.medlineplus_contact_email

        response = self._client.get(
            settings.medlineplus_base_url,
            params=params,
            timeout=settings.medlineplus_timeout_seconds,
        )
        response.raise_for_status()
        return self._normalize(response.text, category, stage)

    # --- Normalization -----------------------------------------------

    def _normalize(
        self, xml_text: str, category: ResourceCategory, stage: ResourceStage
    ) -> list[NormalizedResource]:
        root = ET.fromstring(xml_text)
        resources: list[NormalizedResource] = []

        for document in root.findall(".//document"):
            url = document.get("url")
            if not url:
                continue

            content = {node.get("name"): node for node in document.findall("content")}
            title_node = content.get("title")
            summary_node = content.get("FullSummary")
            if title_node is None or summary_node is None:
                continue

            title = _single_line(html_to_text(_inner_markup(title_node)))
            body = html_to_text(_inner_markup(summary_node))
            if not title or not body:
                continue

            resources.append(
                NormalizedResource(
                    external_id=url,
                    title=title,
                    summary=_summarize(body),
                    body=body,
                    category=category,
                    stage=stage,
                    source_name=self._SOURCE_NAME,
                    source_url=url,
                )
            )

        return resources


def _inner_markup(element: ET.Element) -> str:
    """Re-serialize an XML element's inner content (text + children) back
    into a markup string, so it can be fed through `html_to_text`.

    MedlinePlus nests real markup inside `<content>` elements (e.g. real
    `<span>`/`<p>`/`<li>` sub-elements). This reconstructs that markup
    regardless of whether ElementTree parsed it as genuine child elements
    or the text simply contains literal angle brackets -- either way,
    `html_to_text` strips it the same way.
    """
    parts = [element.text or ""]
    for child in element:
        # ET.tostring() already includes the child's own `.tail` text (the
        # text following its closing tag) -- appending it again here would
        # duplicate it.
        parts.append(ET.tostring(child, encoding="unicode"))
    return "".join(parts)


def _single_line(text: str) -> str:
    return " ".join(text.split())


def _summarize(body: str, limit: int = _SUMMARY_CHAR_LIMIT) -> str:
    first_paragraph = body.split("\n\n", 1)[0]
    if len(first_paragraph) <= limit:
        return first_paragraph
    cut = first_paragraph.rfind(" ", 0, limit)
    if cut <= 0:
        cut = limit
    return first_paragraph[:cut].rstrip() + "..."
