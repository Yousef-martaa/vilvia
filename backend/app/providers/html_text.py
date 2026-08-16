"""HTML-to-text extraction shared by provider adapters.

Not MedlinePlus-specific: any provider that hands back HTML-formatted
summaries can reuse this. Uses only the stdlib `html.parser` -- no new
dependency -- and is deliberately tolerant of malformed markup (unlike an
XML parser, `HTMLParser.feed()` does not raise on unclosed/invalid tags).
"""

from __future__ import annotations

import re
from html.parser import HTMLParser

_BLOCK_TAGS = frozenset(
    {"p", "li", "div", "br", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6"}
)
_WHITESPACE_RUN = re.compile(r"\s+")

# Internal marker for a block-level boundary, distinct from any whitespace
# that can appear in real text data (including literal newlines from
# source formatting, which must collapse to a space, not a paragraph
# break). Chosen to be a byte sequence that will never occur in text data.
_BLOCK_BREAK = "\x00"


class _TextExtractor(HTMLParser):
    def __init__(self) -> None:
        # convert_charrefs=True (default) decodes entities (&amp;, &#39;,
        # named/numeric refs) automatically before handle_data sees them.
        super().__init__(convert_charrefs=True)
        self._chunks: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in _BLOCK_TAGS:
            self._chunks.append(_BLOCK_BREAK)

    def handle_endtag(self, tag: str) -> None:
        if tag in _BLOCK_TAGS:
            self._chunks.append(_BLOCK_BREAK)

    def handle_data(self, data: str) -> None:
        # Collapse all whitespace runs (including literal newlines that
        # are just source-formatting, not a real paragraph break) to a
        # single space, preserving word-boundary spacing.
        self._chunks.append(_WHITESPACE_RUN.sub(" ", data))

    def text(self) -> str:
        raw = "".join(self._chunks)
        paragraphs = [" ".join(p.split()) for p in raw.split(_BLOCK_BREAK)]
        paragraphs = [p for p in paragraphs if p]
        return "\n\n".join(paragraphs)


def html_to_text(markup: str) -> str:
    """Strip tags from `markup`, decode entities, and collapse whitespace,
    while keeping paragraph/list-item boundaries as blank-line-separated
    paragraphs. Inline tags (e.g. `<span>`, `<a>`) contribute only their
    text, with no extra line breaks.
    """
    parser = _TextExtractor()
    parser.feed(markup)
    parser.close()
    return parser.text()
