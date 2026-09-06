import json
from fastapi.testclient import TestClient
from app.main import app
from app.core.settings import settings

client = TestClient(app)

def test_deletion_request_page_returns_html_and_injects_config():
    # Use a specific key to verify injection
    original_key = settings.supabase_publishable_key
    settings.supabase_publishable_key = "test-pub-key-123"

    try:
        response = client.get("/deletion-request")
        assert response.status_code == 200
        assert "text/html" in response.headers["content-type"]
        assert "Vilvia" in response.text
        assert "Account Deletion Request" in response.text

        # Verify Jinja2 rendering of the config JSON
        expected_config = json.dumps({
            "supabase_url": settings.supabase_url,
            "supabase_key": "test-pub-key-123"
        })
        assert expected_config in response.text

        # Verify the JS bug fix (createClient call)
        assert "const { createClient } = supabase;" in response.text
        assert "createClient(config.supabase_url, config.supabase_key)" in response.text

        # Verify disclosure completeness
        assert "Admin-created Events are retained." in response.text
        assert "Every Post and Comment you authored" in response.text
    finally:
        settings.supabase_publishable_key = original_key

def test_deletion_request_page_contains_supabase_sdk():
    response = client.get("/deletion-request")
    assert "https://cdn.jsdelivr.net/npm/@supabase/supabase-js" in response.text
