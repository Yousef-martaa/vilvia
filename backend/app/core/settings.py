from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env")

    app_name: str = "Vilvia"
    debug: bool = False
    database_url: str = "postgresql+psycopg://postgres:postgres@localhost:5432/vilvia"
    cors_origins: list[str] = []
    cors_origin_regex: str | None = r"^http://localhost:\d+$"

    # Supabase Auth: only the project URL is needed. Verification uses the
    # project's public JWKS endpoint (derived from this URL) -- no secret
    # or service-role key is required for verifying tokens.
    supabase_url: str = "https://project-id.supabase.co"

    # MedlinePlus Web Service (https://medlineplus.gov/about/developers/webservices/)
    medlineplus_base_url: str = "https://wsearch.nlm.nih.gov/ws/query"
    medlineplus_tool_name: str = "Vilvia"
    medlineplus_contact_email: str | None = None
    medlineplus_timeout_seconds: float = 10.0
    medlineplus_retmax: int = 5

    # API rate limiting (Issue #83): in-memory, single-process only -- see
    # docs/FEATURES/rate_limiting.md for the multi-worker/multi-instance
    # limitation and the documented future Redis-backed upgrade path.
    rate_limit_enabled: bool = True
    rate_limit_public_per_minute: int = 60
    rate_limit_me_read_per_minute: int = 60
    rate_limit_me_bootstrap_per_minute: int = 10
    rate_limit_admin_read_per_minute: int = 60
    rate_limit_admin_write_per_minute: int = 20


settings = Settings()
