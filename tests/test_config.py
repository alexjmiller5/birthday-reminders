from core.config import Settings


def test_settings_reads_env(monkeypatch):
    monkeypatch.setenv("NOTION_API_KEY", "secret_test")
    monkeypatch.setenv("NTFY_TOPIC", "test-topic")
    s = Settings()
    assert s.notion_api_key == "secret_test"
    assert s.ntfy_topic == "test-topic"


def test_ntfy_topic_has_default(monkeypatch):
    monkeypatch.setenv("NOTION_API_KEY", "secret_test")
    monkeypatch.delenv("NTFY_TOPIC", raising=False)
    assert Settings().ntfy_topic == "bday-56hqsioQJ5-YM-ju7wfgag"
