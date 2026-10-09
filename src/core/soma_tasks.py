"""Soma birthday task planning and atomic-origin creation transport.

Not connected to the cron. Enrollment, complete People reads, migration dedupe
coverage and creation policy must be established before enabling a live caller.
"""

import calendar
import datetime as dt
import json
import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Protocol
from uuid import UUID, uuid5

import httpx
from soma.creation import validate_creation_receipt, validate_creation_session

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
    birthday: str | None
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
        if person.birthday is None or person.birthday == "":
            continue
        if not _nonempty(person.name):
            raise ValueError("Missing display name")
        if _month_day(person.birthday, day.year) != (day.month, day.day):
            continue
        key = (person.id, day.year)
        adopted = key in retained_ids
        task_id = retained_ids[key] if adopted else occurrence_id(person.id, day.year)
        if not _nonempty(task_id) or task_id in seen_tasks:
            raise ValueError("Invalid or conflicting retained task identity")
        seen_tasks.add(task_id)
        rows.append(
            {
                "sourceId": person.id,
                "occurrenceKey": day.year,
                "target": {"kind": "adopted" if adopted else "generated", "id": task_id},
                "updatedAt": stamp,
                "values": {
                    "title": f"Wish {person.name} a happy birthday",
                    "due_date": day.isoformat(),
                    "person_ids": _json([person.id]),
                    **fields,
                },
            }
        )
    return rows


class CreationValidator(Protocol):
    """Host binding to Soma Core's canonical pure checks, not a second validator."""

    def validate_session(self, reply: dict, policy: dict, scopes: list[str]) -> bool: ...

    def validate_receipt(self, request: dict, reply: dict) -> dict | None: ...


class CoreCreationValidator:
    """Bind the pinned library's pure functions without duplicating its policy."""

    validate_session = staticmethod(validate_creation_session)
    validate_receipt = staticmethod(validate_creation_receipt)


class CreationInterrupted(RuntimeError):
    """Indeterminate/error outcome with validated receipts from earlier requests."""

    def __init__(self, receipt: dict):
        super().__init__("Soma creation interrupted; inspect receipts before retrying")
        self.receipt = receipt


def create_tasks(
    client: httpx.Client,
    intents: Sequence[dict],
    *,
    policy: dict,
    scopes: Sequence[str],
    validator: CreationValidator = CoreCreationValidator(),
) -> dict:
    """Create one task plus origin per request under the exact advertised grant.

    The host supplies a pinned canonical validator and a dedicated credential.
    The default binding uses Soma Core; there is no configured live writer. Errors
    stop this batch, preserve prior receipts and never trigger a fallback/retry.
    A caller may retry identical intent; existing settles presence only, without
    attributing creation. Adopted missing is an error, never a generated insert.
    """
    if client.base_url.scheme != "https":
        raise ValueError("Soma requires an HTTPS endpoint")
    try:
        ids = [intent["target"]["id"] for intent in intents]
    except (KeyError, TypeError):
        raise ValueError("Invalid task target") from None
    if not all(map(_nonempty, ids)) or len(set(ids)) != len(ids):
        raise ValueError("Task IDs must be nonempty and unique")
    result = {"created": [], "existing": []}
    if not intents:
        return result
    try:
        response = client.get("/v1/session", follow_redirects=False, timeout=30)
        response.raise_for_status()
        if not validator.validate_session(
            {"status": response.status_code, "data": response.json()}, policy, list(scopes)
        ):
            raise ValueError("Unsupported Soma creation session")
        for intent in intents:
            request = {**intent, "policy": dict(policy)}
            response = client.post(
                "/v1/rows/create", json=request, follow_redirects=False, timeout=30
            )
            response.raise_for_status()
            receipt = validator.validate_receipt(
                request, {"status": response.status_code, "data": response.json()}
            )
            if receipt is None:
                raise ValueError("Invalid Soma creation receipt")
            result[receipt["kind"]].append(receipt)
    except (httpx.HTTPError, ValueError) as error:
        raise CreationInterrupted(result) from error
    return result
