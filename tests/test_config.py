from core.config import Settings


def test_settings_reads_env(monkeypatch):
    monkeypatch.setenv("NOTION_API_KEY", "secret_test")
    monkeypatch.setenv("NTFY_TOPIC", "test-topic")
    s = Settings()
    assert s.notion_api_key == "secret_test"
    assert s.ntfy_topic == "test-topic"
