from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env")

    app_name: str = "Vilvia"
    debug: bool = False
    database_url: str = "postgresql+psycopg://postgres:postgres@localhost:5432/vilvia"


settings = Settings()
