from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_dynamic_localhost_origin_is_allowed():
    response = client.get("/health", headers={"Origin": "http://localhost:54231"})

    assert response.status_code == 200
    assert (
        response.headers["access-control-allow-origin"] == "http://localhost:54231"
    )


def test_different_dynamic_localhost_port_is_also_allowed():
    response = client.get("/health", headers={"Origin": "http://localhost:9999"})

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://localhost:9999"


def test_non_matching_origin_is_not_allowed():
    response = client.get("/health", headers={"Origin": "https://evil.example.com"})

    assert response.status_code == 200
    assert "access-control-allow-origin" not in response.headers


def test_preflight_request_is_handled():
    response = client.options(
        "/health",
        headers={
            "Origin": "http://localhost:54231",
            "Access-Control-Request-Method": "GET",
        },
    )

    assert response.status_code == 200
    assert "access-control-allow-methods" in response.headers
