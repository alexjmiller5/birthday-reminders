import pytest
from pydantic import ValidationError

from core.config import Settings

ENV = {
    "NOTION_API_KEY": "secret_test",
    "NTFY_TOPIC": "test-topic",
    "PEOPLE_DATA_SOURCE_ID": "people-ds",
    "TASKS_DATA_SOURCE_ID": "tasks-ds",
    "PROJECT_PAGE_ID": "project-page",
}


def set_env(monkeypatch, **overrides):
    for key, value in (ENV | overrides).items():
        monkeypatch.setenv(key, value)


def test_settings_reads_env(monkeypatch):
    set_env(monkeypatch)
    s = Settings()
    assert s.notion_api_key == "secret_test"
    assert s.ntfy_topic == "test-topic"
    assert s.people_data_source_id == "people-ds"
    assert s.tasks_data_source_id == "tasks-ds"
    assert s.project_page_id == "project-page"


@pytest.mark.parametrize("missing", ENV)
def test_every_field_is_required(monkeypatch, missing):
    set_env(monkeypatch)
    monkeypatch.delenv(missing)
    with pytest.raises(ValidationError):
        Settings()
