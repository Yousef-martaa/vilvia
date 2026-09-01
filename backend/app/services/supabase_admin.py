import uuid

import httpx


class SupabaseAuthDeletionError(Exception):
    """A retryable/operational failure deleting a Supabase Auth user."""


class SupabaseAuthAdmin:
    def __init__(
        self,
        *,
        supabase_url: str,
        service_role_key: str,
        timeout_seconds: float,
        client: httpx.Client | None = None,
    ) -> None:
        self._client = client or httpx.Client(timeout=timeout_seconds)
        self._owns_client = client is None
        self._base_url = supabase_url.rstrip("/")
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
        }

    def delete_user(self, user_id: uuid.UUID) -> None:
        """Delete an Auth identity; an already-absent identity is success."""
        try:
            response = self._client.delete(
                f"{self._base_url}/auth/v1/admin/users/{user_id}",
                headers=self._headers,
            )
        except httpx.HTTPError as exc:
            raise SupabaseAuthDeletionError(
                "Supabase Auth deletion request failed"
            ) from exc

        if response.status_code == 404:
            return
        if not 200 <= response.status_code < 300:
            # Do not include the response body: it may contain account data or
            # deployment details and is unnecessary for a retry decision.
            raise SupabaseAuthDeletionError(
                f"Supabase Auth deletion returned HTTP {response.status_code}"
            )

    def close(self) -> None:
        if self._owns_client:
            self._client.close()
