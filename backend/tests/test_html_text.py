from app.providers.html_text import html_to_text


def test_strips_simple_tags():
    assert html_to_text("<p>Hello <b>world</b></p>") == "Hello world"


def test_decodes_entities():
    assert html_to_text("Rock &amp; Roll &#39;n&#39; stuff") == "Rock & Roll 'n' stuff"


def test_preserves_paragraph_breaks():
    markup = "<p>First paragraph.</p><p>Second paragraph.</p>"
    assert html_to_text(markup) == "First paragraph.\n\nSecond paragraph."


def test_preserves_list_item_breaks():
    markup = "<ul><li>One</li><li>Two</li></ul>"
    assert html_to_text(markup) == "One\n\nTwo"


def test_inline_tags_do_not_add_breaks():
    markup = 'Sudden <span class="qt0">infant</span> death syndrome'
    assert html_to_text(markup) == "Sudden infant death syndrome"


def test_collapses_internal_whitespace():
    markup = "<p>Too    much   \n  whitespace</p>"
    assert html_to_text(markup) == "Too much whitespace"


def test_links_contribute_only_their_text():
    markup = '<p>See <a href="https://example.com">this link</a> for more.</p>'
    assert html_to_text(markup) == "See this link for more."


def test_empty_input_returns_empty_string():
    assert html_to_text("") == ""
