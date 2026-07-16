"""Settings from env vars — Modal Secret in the cloud, `op run` locally.

One field per line in .env.tpl. Instantiate Settings() inside functions,
not at import time, so tests can run without secrets.
"""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    notion_api_key: str
    # ntfy topics are the only auth ntfy.sh has — generate a random unguessable
    # string, treat it like a password, and subscribe in the ntfy iOS app (README).
    ntfy_topic: str
    # Notion IDs (stable IDs, not names — see README for the required schema)
    people_data_source_id: str
    tasks_data_source_id: str
    project_page_id: str
