import httpx
import pytest

from app.models.enums import ResourceCategory, ResourceStage
from app.providers.medlineplus import MedlinePlusProvider, MedlinePlusUnavailableError


def _brief_xml(documents: list[tuple[str, str, str]]) -> str:
    """Build a minimal rettype=brief response.

    Each document is (url, title_inner_markup, full_summary_inner_markup).
    """
    parts = ['<?xml version="1.0" encoding="UTF-8"?>', "<nlmSearchResult>", "<list>"]
    for url, title, summary in documents:
        parts.append(
            f'<document rank="0" url="{url}">'
            f'<content name="title">{title}</content>'
            f'<content name="organizationName">National Library of Medicine</content>'
            f'<content name="FullSummary">{summary}</content>'
            f'<content name="mesh">Example</content>'
            f'<content name="groupName">Children and Teenagers</content>'
            f'<content name="snippet"> {summary} ... </content>'
            f"</document>"
        )
    parts.append("</list></nlmSearchResult>")
    return "".join(parts)


def _provider(handler, queries=None) -> MedlinePlusProvider:
    provider = MedlinePlusProvider(client=httpx.Client(transport=httpx.MockTransport(handler)))
    if queries is not None:
        provider._QUERIES = queries  # test-only override for determinism
    return provider


def test_fetch_normalizes_a_document_into_the_provider_independent_shape():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["term"] == "infant sleep"
        xml = _brief_xml(
            [
                (
                    "https://medlineplus.gov/suddeninfantdeathsyndrome.html",
                    'Sudden <span class="qt0">Infant</span> Death Syndrome',
                    "<p>SIDS is the sudden, unexplained death of an infant.</p>"
                    "<p>Second paragraph with detail.</p>",
                )
            ]
        )
        return httpx.Response(200, text=xml)

    queries = [(ResourceCategory.sleep, ResourceStage.months_0_6, "infant sleep")]
    provider = _provider(handler, queries=queries)

    resources = provider.fetch()

    assert len(resources) == 1
    resource = resources[0]
    assert resource.title == "Sudden Infant Death Syndrome"
    assert resource.source_name == "MedlinePlus.gov"
    assert resource.source_url == "https://medlineplus.gov/suddeninfantdeathsyndrome.html"
    assert resource.external_id == resource.source_url
    assert resource.category == ResourceCategory.sleep
    assert resource.stage == ResourceStage.months_0_6
    assert "SIDS is the sudden" in resource.body
    assert "Second paragraph with detail." in resource.body
    assert "<p>" not in resource.body
    assert resource.summary.startswith("SIDS is the sudden")


def test_duplicate_url_across_queries_keeps_first_querys_classification():
    shared_url = "https://medlineplus.gov/infantandnewborncare.html"

    def handler(request: httpx.Request) -> httpx.Response:
        xml = _brief_xml([(shared_url, "Infant and Newborn Care", "<p>Body text.</p>")])
        return httpx.Response(200, text=xml)

    queries = [
        (ResourceCategory.health_safety, ResourceStage.newborn, "newborn care"),
        (ResourceCategory.feeding, ResourceStage.newborn, "breastfeeding"),
    ]
    provider = _provider(handler, queries=queries)

    resources = provider.fetch()

    assert len(resources) == 1
    assert resources[0].category == ResourceCategory.health_safety
    assert resources[0].stage == ResourceStage.newborn


def test_one_query_timing_out_does_not_abort_the_others():
    good_url = "https://medlineplus.gov/toddlerhealth.html"

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.params["term"] == "infant sleep":
            raise httpx.ConnectTimeout("simulated timeout", request=request)
        xml = _brief_xml([(good_url, "Toddler Health", "<p>Body text.</p>")])
        return httpx.Response(200, text=xml)

    queries = [
        (ResourceCategory.sleep, ResourceStage.months_0_6, "infant sleep"),
        (ResourceCategory.everyday_guidance, ResourceStage.years_1_3, "toddler health"),
    ]
    provider = _provider(handler, queries=queries)

    resources = provider.fetch()

    assert len(resources) == 1
    assert resources[0].source_url == good_url


def test_non_200_response_for_one_of_several_queries_is_skipped_without_raising():
    good_url = "https://medlineplus.gov/toddlerhealth.html"

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.params["term"] == "infant sleep":
            return httpx.Response(500, text="upstream error")
        return httpx.Response(
            200, text=_brief_xml([(good_url, "Toddler Health", "<p>Body text.</p>")])
        )

    queries = [
        (ResourceCategory.sleep, ResourceStage.months_0_6, "infant sleep"),
        (ResourceCategory.everyday_guidance, ResourceStage.years_1_3, "toddler health"),
    ]
    provider = _provider(handler, queries=queries)

    resources = provider.fetch()

    assert len(resources) == 1
    assert resources[0].source_url == good_url


def test_malformed_xml_for_one_of_several_queries_is_skipped_without_raising():
    good_url = "https://medlineplus.gov/toddlerhealth.html"

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.params["term"] == "infant sleep":
            return httpx.Response(200, text="not xml at all <<<")
        return httpx.Response(
            200, text=_brief_xml([(good_url, "Toddler Health", "<p>Body text.</p>")])
        )

    queries = [
        (ResourceCategory.sleep, ResourceStage.months_0_6, "infant sleep"),
        (ResourceCategory.everyday_guidance, ResourceStage.years_1_3, "toddler health"),
    ]
    provider = _provider(handler, queries=queries)

    resources = provider.fetch()

    assert len(resources) == 1
    assert resources[0].source_url == good_url


def test_document_missing_full_summary_is_skipped():
    def handler(request: httpx.Request) -> httpx.Response:
        xml = (
            '<?xml version="1.0" encoding="UTF-8"?>'
            "<nlmSearchResult><list>"
            '<document rank="0" url="https://medlineplus.gov/example.html">'
            '<content name="title">Example</content>'
            "</document>"
            "</list></nlmSearchResult>"
        )
        return httpx.Response(200, text=xml)

    queries = [(ResourceCategory.sleep, ResourceStage.months_0_6, "infant sleep")]
    provider = _provider(handler, queries=queries)

    assert provider.fetch() == []


def test_every_query_failing_raises_unavailable_rather_than_returning_empty():
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectTimeout("simulated timeout", request=request)

    queries = [
        (ResourceCategory.sleep, ResourceStage.months_0_6, "infant sleep"),
        (ResourceCategory.everyday_guidance, ResourceStage.years_1_3, "toddler health"),
    ]
    provider = _provider(handler, queries=queries)

    with pytest.raises(MedlinePlusUnavailableError):
        provider.fetch()


def test_sends_tool_name_for_attribution():
    seen_params = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen_params.update(request.url.params)
        return httpx.Response(200, text=_brief_xml([]))

    queries = [(ResourceCategory.sleep, ResourceStage.months_0_6, "infant sleep")]
    provider = _provider(handler, queries=queries)
    provider.fetch()

    assert seen_params["tool"] == "Vilvia"
    assert seen_params["db"] == "healthTopics"
