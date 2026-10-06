"""Life Data birthday task planning and insert-only transport.

Not connected to the cron. Enrollment, complete People reads, migration dedupe
coverage and creation policy must be established before enabling a live caller.
"""

import calendar
import datetime as dt
import json
import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from uuid import UUID, uuid5

import httpx

# Durable application identity, shared by all installations. Never rotate this
# with credentials or derive it from a device, title, endpoint or project ID.
TASK_NAMESPACE = UUID("de603401-5838-4cc7-98ee-f2015a433a2e")
SOURCE_KIND = "birthday"


def _json(value) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _nonempty(value) -> bool:
    return isinstance(value, str) and bool(value.strip())


def occurrence_id(person_id: str, year: int) -> str:
    """UUIDv5 over UTF-8 compact JSON, preserving the exact person ID bytes."""
    if not _nonempty(person_id) or type(year) is not int or not 1 <= year <= 9999:
        raise ValueError("Invalid occurrence identity")
    return uuid5(TASK_NAMESPACE, _json(["v1", SOURCE_KIND, person_id, year])).hex


@dataclass(frozen=True)
class BirthdayPerson:
    id: str
    name: str
    birthday: str
    notify_birthday: bool
    deleted_at: str | None = None


@dataclass(frozen=True)
class TaskPolicy:
    """Optional fields are omitted unless the caller explicitly configures them."""

    status: str | None = None
    priority: str | None = None
    tags: tuple[str, ...] | None = None
    project_ids: tuple[str, ...] | None = None

    def fields(self) -> dict:
        if self.status not in (None, "To Do", "In Progress", "Canceled", "Completed"):
            raise ValueError("Invalid task status")
        if self.priority not in (None, "Low", "Medium", "High"):
            raise ValueError("Invalid task priority")
        fields = {}
        for key in ("status", "priority", "tags", "project_ids"):
            value = getattr(self, key)
            if value is None:
                continue
            if key in ("tags", "project_ids"):
                if not isinstance(value, (tuple, list)) or not all(map(_nonempty, value)):
                    raise ValueError("Invalid task references or tags")
                value = _json(value)
            fields[key] = value
        return fields


def _month_day(birthday: str, year: int) -> tuple[int, int]:
    if not isinstance(birthday, str) or not re.fullmatch(
        r"(?:[0-9]{4}-|--)[0-9]{2}-[0-9]{2}", birthday
    ):
        raise ValueError("Invalid birthday")
    try:
        parsed = dt.date.fromisoformat(
            "2000" + birthday[1:] if birthday.startswith("--") else birthday
        )
    except ValueError:
        raise ValueError("Invalid birthday") from None
    if (parsed.month, parsed.day) == (2, 29) and not calendar.isleap(year):
        return 2, 28
    return parsed.month, parsed.day


def plan_tasks(
    people: Sequence[BirthdayPerson],
    day: dt.date,
    *,
    updated_at: dt.datetime,
    retained_ids: Mapping[tuple[str, int], str],
    policy: TaskPolicy,
) -> list[dict]:
    """Plan today's opted-in tasks from a complete read snapshot.

    `day` is the actual birthday occurrence's calendar label. The caller must
    supply reviewed migration mappings (including tombstones); an empty mapping
    is not evidence that historical dedupe coverage is complete. No task reads
    or title-based dedupe are substituted for that review.
    """
    if type(day) is not dt.date or updated_at.utcoffset() is None:
        raise ValueError("A calendar date and aware edit timestamp are required")
    stamp = updated_at.astimezone(dt.UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    fields = policy.fields()
    seen_people, seen_tasks = set(), set()
    rows = []
    for person in people:
        if not _nonempty(person.id) or type(person.notify_birthday) is not bool:
            raise ValueError("Invalid person identity or opt-in")
        if person.id in seen_people:
            raise ValueError("Duplicate person")
        seen_people.add(person.id)
        if person.deleted_at is not None or not person.notify_birthday:
            continue
        if not _nonempty(person.name):
            raise ValueError("Missing display name")
        if _month_day(person.birthday, day.year) != (day.month, day.day):
            continue
        task_id = retained_ids.get((person.id, day.year), occurrence_id(person.id, day.year))
        if not _nonempty(task_id) or task_id in seen_tasks:
            raise ValueError("Invalid or conflicting retained task identity")
        seen_tasks.add(task_id)
        rows.append(
            {
                "id": task_id,
                "title": f"Wish {person.name} a happy birthday",
                "due_date": day.isoformat(),
                "person_ids": _json([person.id]),
                "updated_at": stamp,
                **fields,
            }
        )
    return rows


def _validate_receipt(receipt, ids: set[str]) -> None:
    try:
        if not isinstance(receipt, dict) or not all(
            isinstance(receipt.get(key), list) for key in ("inserted", "existing", "rejected")
        ):
            raise ValueError
        reported = (
            receipt["inserted"]
            + receipt["existing"]
            + [rejection["id"] for rejection in receipt["rejected"]]
        )
        if not all(isinstance(item, str) for item in reported):
            raise ValueError
        if len(reported) != len(ids) or set(reported) != ids:
            raise ValueError
    except (KeyError, TypeError, ValueError):
        raise ValueError("Invalid Life Data insert receipt") from None


class InsertInterrupted(RuntimeError):
    """Request failure, with all validated receipts from earlier batches."""

    def __init__(self, receipt: dict):
        super().__init__("Life Data insert interrupted; inspect partial receipt before retrying")
        self.receipt = receipt


def insert_tasks(client: httpx.Client, rows: Sequence[dict]) -> dict:
    """Use the supported atomic insert API, never push/patch or a fallback.

    Client enrollment must establish create-only authority before live use.
    Rejections are returned, not counted as successes. Transport/receipt errors
    raise InsertInterrupted with prior receipts and the original cause. The
    caller can replay the same planned IDs, including earlier successful chunks.
    The service preserves existing/tombstoned rows.
    """
    if client.base_url.scheme != "https":
        raise ValueError("Life Data requires an HTTPS endpoint")
    ids = [row.get("id") for row in rows]
    if not all(map(_nonempty, ids)) or len(set(ids)) != len(ids):
        raise ValueError("Task IDs must be nonempty and unique")
    result = {"inserted": [], "existing": [], "rejected": []}
    for start in range(0, len(rows), 200):
        batch = rows[start : start + 200]
        try:
            response = client.post(
                "/v1/rows/insert",
                json={
                    "table": "tasks",
                    "columns": list(dict.fromkeys(k for r in batch for k in r)),
                    "rows": batch,
                },
                follow_redirects=False,
                timeout=30,
            )
            response.raise_for_status()
            receipt = response.json()
            _validate_receipt(receipt, set(ids[start : start + 200]))
        except (httpx.HTTPError, ValueError) as error:
            raise InsertInterrupted(result) from error
        for key in result:
            result[key].extend(receipt[key])
    return result
