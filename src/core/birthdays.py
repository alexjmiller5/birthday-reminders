"""Birthday detection from the Notion People DB — plain Python, no Modal imports."""

import calendar
import datetime
from dataclasses import dataclass

import httpx

PEOPLE_DATA_SOURCE_ID = "1a803953-a8af-80ab-824d-000bfe407316"
_QUERY_URL = f"https://api.notion.com/v1/data_sources/{PEOPLE_DATA_SOURCE_ID}/query"


@dataclass(frozen=True)
class Person:
    page_id: str
    name: str
    birthday: datetime.date


def query_people(api_key: str) -> list[Person]:
    """People opted in to Birthday Notifications who have a Birthday set."""
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Notion-Version": "2026-03-11",
        "Content-Type": "application/json",
    }
    body: dict = {
        "filter": {
            "and": [
                {"property": "Birthday Notifications", "checkbox": {"equals": True}},
                {"property": "Birthday", "date": {"is_not_empty": True}},
            ]
        },
        "page_size": 100,
    }
    people: list[Person] = []
    while True:
        resp = httpx.post(_QUERY_URL, headers=headers, json=body, timeout=30)
        resp.raise_for_status()
        data = resp.json()
        for page in data["results"]:
            props = page["properties"]
            date_prop = props["Birthday"]["date"]
            if not date_prop or not date_prop.get("start"):
                continue  # filter guarantees non-empty, but don't crash the run on one bad page
            people.append(
                Person(
                    page_id=page["id"],
                    name="".join(t["plain_text"] for t in props["Name"]["title"]),
                    # start may carry a time component; the date is the first 10 chars
                    birthday=datetime.date.fromisoformat(date_prop["start"][:10]),
                )
            )
        if not data.get("has_more"):
            return people
        body["start_cursor"] = data["next_cursor"]


def todays_birthdays(people: list[Person], today: datetime.date) -> list[Person]:
    """People whose birthday is today, ignoring year; Feb 29 -> Feb 28 on non-leap years."""

    def month_day(b: datetime.date) -> tuple[int, int]:
        if b.month == 2 and b.day == 29 and not calendar.isleap(today.year):
            return (2, 28)
        return (b.month, b.day)

    return [p for p in people if month_day(p.birthday) == (today.month, today.day)]
