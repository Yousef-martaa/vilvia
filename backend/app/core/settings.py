from pydantic import Field, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


def minimum_account_deletion_retention_seconds(
    max_token_lifetime_seconds: int, clock_skew_seconds: int
) -> int:
    """Cover future-iat and expired-exp leeway around a token's lifetime."""
    return max_token_lifetime_seconds + (2 * clock_skew_seconds)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env")

    app_name: str = "Vilvia"
    debug: bool = False
    database_url: str = "postgresql+psycopg://postgres:postgres@localhost:5432/vilvia"
    cors_origins: list[str] = []
    cors_origin_regex: str | None = r"^http://localhost:\d+$"

    # Normal API authentication needs only the public project URL. The
    # service-role key is optional and used only by the manually invoked,
    # operator-only account-deletion command.
    supabase_url: str = "https://project-id.supabase.co"
    supabase_publishable_key: str = "pk-placeholder"
    supabase_service_role_key: SecretStr | None = None
    supabase_admin_timeout_seconds: float = 10.0
    supabase_access_token_max_lifetime_seconds: int = Field(default=3600, gt=0)
    supabase_jwt_clock_skew_seconds: int = Field(default=60, ge=0)
    account_deletion_completed_retention_days: int = Field(default=7, gt=0)

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
    rate_limit_account_deletion_request_per_minute: int = 5
    rate_limit_admin_read_per_minute: int = 60
    rate_limit_admin_write_per_minute: int = 20
    rate_limit_community_write_per_minute: int = 10

    @model_validator(mode="after")
    def validate_account_deletion_retention(self) -> "Settings":
        retention_seconds = (
            self.account_deletion_completed_retention_days * 24 * 60 * 60
        )
        required_seconds = minimum_account_deletion_retention_seconds(
            self.supabase_access_token_max_lifetime_seconds,
            self.supabase_jwt_clock_skew_seconds,
        )
        if retention_seconds < required_seconds:
            raise ValueError(
                "account deletion retention must cover the maximum Supabase "
                "access-token lifetime plus twice the JWT clock skew"
            )
        return self


settings = Settings()
