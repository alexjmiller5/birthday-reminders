"""Tests for core.actions — httpx mocked via pytest-mock; no live ntfy or Notion."""

import datetime
from unittest.mock import Mock

import httpx

from core.actions import (
    PROJECT_PAGE_ID,
    TASKS_DATA_SOURCE_ID,
    create_birthday_task,
    send_push,
)

TODAY = datetime.date(2026, 7, 6)


def response(status_code: int = 200, json_body: dict | None = None) -> Mock:
    resp = Mock(spec=httpx.Response)
    resp.status_code = status_code
    resp.json.return_value = json_body or {}
    return resp


# --- send_push ---


def test_send_push_happy_path(mocker):
    post = mocker.patch("core.actions.httpx.post", return_value=response(200))
    assert send_push("Sam", "my-topic") is True
    post.assert_called_once()
    args, kwargs = post.call_args
    assert args[0] == "https://ntfy.sh/my-topic"
    assert kwargs["data"] == "It's Sam's birthday today — send them a message!"
    assert kwargs["headers"]["Title"] == "Birthday reminder"


def test_send_push_non_200_logs_and_returns_false(mocker):
    mocker.patch("core.actions.httpx.post", return_value=response(500))
    assert send_push("Sam", "my-topic") is False  # no exception raised


def test_send_push_network_error_returns_false(mocker):
    mocker.patch("core.actions.httpx.post", side_effect=httpx.ConnectError("boom"))
    assert send_push("Sam", "my-topic") is False


# --- create_birthday_task ---


def test_create_task_happy_path(mocker):
    query_resp = response(200, {"results": []})
    create_resp = response(200, {"id": "new-page-id"})
    post = mocker.patch("core.actions.httpx.post", side_effect=[query_resp, create_resp])

    page_id = create_birthday_task("Sam", api_key="k", today=TODAY)

    assert page_id == "new-page-id"
    assert post.call_count == 2

    # 1st call: idempotency query against the Tasks data source
    query_call = post.call_args_list[0]
    assert TASKS_DATA_SOURCE_ID in query_call.args[0]
    filters = query_call.kwargs["json"]["filter"]["and"]
    assert {"property": "Name", "title": {"equals": "Wish Sam a happy birthday"}} in filters
    assert {"property": "Due Date", "date": {"equals": "2026-07-06"}} in filters

    # 2nd call: page creation with exact property payloads
    create_call = post.call_args_list[1]
    assert create_call.args[0] == "https://api.notion.com/v1/pages"
    body = create_call.kwargs["json"]
    assert body["parent"] == {"type": "data_source_id", "data_source_id": TASKS_DATA_SOURCE_ID}
    props = body["properties"]
    assert props["Name"] == {"title": [{"text": {"content": "Wish Sam a happy birthday"}}]}
    assert props["Priority"] == {"select": {"name": "High"}}
    assert props["Due Date"] == {"date": {"start": "2026-07-06"}}
    assert props["Project"] == {"relation": [{"id": PROJECT_PAGE_ID}]}
    assert props["Notes"] == {
        "rich_text": [{"text": {"content": "Auto-created by birthday-reminders"}}]
    }
    assert create_call.kwargs["headers"]["Authorization"] == "Bearer k"
    assert create_call.kwargs["headers"]["Notion-Version"] == "2026-03-11"


def test_create_task_idempotent_skip(mocker):
    query_resp = response(200, {"results": [{"id": "existing-page"}]})
    post = mocker.patch("core.actions.httpx.post", return_value=query_resp)

    assert create_birthday_task("Sam", api_key="k", today=TODAY) is None
    post.assert_called_once()  # no create call
