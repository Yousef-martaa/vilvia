from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env")

    app_name: str = "Vilvia"
    debug: bool = False
    database_url: str = "postgresql+psycopg://postgres:postgres@localhost:5432/vilvia"
    cors_origins: list[str] = []
    cors_origin_regex: str | None = r"^http://localhost:\d+$"

    # MedlinePlus Web Service (https://medlineplus.gov/about/developers/webservices/)
    medlineplus_base_url: str = "https://wsearch.nlm.nih.gov/ws/query"
    medlineplus_tool_name: str = "Vilvia"
    medlineplus_contact_email: str | None = None
    medlineplus_timeout_seconds: float = 10.0
    medlineplus_retmax: int = 5


settings = Settings()
