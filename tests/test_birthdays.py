"""Tests for core.birthdays — fixture payloads mimic Notion query responses; no live API."""

import datetime
from unittest.mock import Mock

import httpx

from core.birthdays import PEOPLE_DATA_SOURCE_ID, Person, query_people, todays_birthdays


def notion_page(page_id: str, name: str, birthday: str) -> dict:
    """Minimal Notion page payload as returned by a data-source query."""
    return {
        "object": "page",
        "id": page_id,
        "properties": {
            "Name": {"type": "title", "title": [{"plain_text": name}]},
            "Birthday": {"type": "date", "date": {"start": birthday}},
            "Birthday Notifications": {"type": "checkbox", "checkbox": True},
        },
    }


def response(pages: list[dict], next_cursor: str | None = None) -> Mock:
    resp = Mock(spec=httpx.Response)
    resp.json.return_value = {
        "object": "list",
        "results": pages,
        "has_more": next_cursor is not None,
        "next_cursor": next_cursor,
    }
    return resp


# --- query_people (thin Notion client) ---


def test_query_people_parses_pages(mocker):
    post = mocker.patch(
        "core.birthdays.httpx.post",
        return_value=response([notion_page("p1", "Ada Lovelace", "1815-12-10")]),
    )
    people = query_people("secret_key")
    assert people == [
        Person(page_id="p1", name="Ada Lovelace", birthday=datetime.date(1815, 12, 10))
    ]
    url = post.call_args.args[0]
    assert PEOPLE_DATA_SOURCE_ID in url
    assert post.call_args.kwargs["headers"]["Authorization"] == "Bearer secret_key"
    assert post.call_args.kwargs["headers"]["Notion-Version"] == "2026-03-11"


def test_query_people_filters_on_checkbox_and_birthday(mocker):
    post = mocker.patch("core.birthdays.httpx.post", return_value=response([]))
    query_people("k")
    sent_filter = post.call_args.kwargs["json"]["filter"]
    assert {"property": "Birthday Notifications", "checkbox": {"equals": True}} in sent_filter[
        "and"
    ]
    assert {"property": "Birthday", "date": {"is_not_empty": True}} in sent_filter["and"]


def test_query_people_paginates(mocker):
    post = mocker.patch(
        "core.birthdays.httpx.post",
        side_effect=[
            response([notion_page("p1", "A", "1990-01-01")], next_cursor="cur2"),
            response([notion_page("p2", "B", "1991-02-02")]),
        ],
    )
    people = query_people("k")
    assert [p.page_id for p in people] == ["p1", "p2"]
    assert post.call_count == 2
    assert post.call_args_list[1].kwargs["json"]["start_cursor"] == "cur2"


def test_query_people_skips_malformed_dates(mocker):
    page = notion_page("p1", "Broken", "1990-01-01")
    page["properties"]["Birthday"]["date"] = None  # filter says non-empty, but be safe
    mocker.patch("core.birthdays.httpx.post", return_value=response([page]))
    assert query_people("k") == []


# --- todays_birthdays (pure logic) ---


def person(birthday: datetime.date, name: str = "X") -> Person:
    return Person(page_id="id", name=name, birthday=birthday)


def test_match_ignores_year():
    p = person(datetime.date(1900, 7, 7))  # year-less birthdays stored with placeholder year
    assert todays_birthdays([p], datetime.date(2026, 7, 7)) == [p]


def test_no_match():
    p = person(datetime.date(1990, 7, 8))
    assert todays_birthdays([p], datetime.date(2026, 7, 7)) == []


def test_feb29_maps_to_feb28_on_nonleap_year():
    p = person(datetime.date(2000, 2, 29))
    assert todays_birthdays([p], datetime.date(2026, 2, 28)) == [p]
    assert todays_birthdays([p], datetime.date(2026, 3, 1)) == []


def test_feb29_stays_feb29_on_leap_year():
    p = person(datetime.date(2000, 2, 29))
    assert todays_birthdays([p], datetime.date(2028, 2, 29)) == [p]
    assert todays_birthdays([p], datetime.date(2028, 2, 28)) == []


def test_feb28_birthday_not_duplicated_with_feb29_logic():
    p = person(datetime.date(1995, 2, 28))
    assert todays_birthdays([p], datetime.date(2028, 2, 28)) == [p]
    assert todays_birthdays([p], datetime.date(2028, 2, 29)) == []
