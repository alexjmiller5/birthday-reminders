"""Consumer contract tests with synthetic records and an isolated HTTP transport."""

import datetime as dt
import json

import httpx
import pytest

from core.life_tasks import (
    BirthdayPerson,
    InsertInterrupted,
    TaskPolicy,
    insert_tasks,
    occurrence_id,
    plan_tasks,
)

DAY = dt.date(2030, 2, 28)
STAMP = dt.datetime(2030, 2, 28, 14, tzinfo=dt.UTC)


def person(**changes):
    return BirthdayPerson(
        **{
            "id": "person-1",
            "name": "<person-1>",
            "birthday": "--02-28",
            "notify_birthday": True,
            **changes,
        }
    )


def plan(people=None, **kwargs):
    return plan_tasks(
        [person()] if people is None else people,
        DAY,
        updated_at=STAMP,
        retained_ids={},
        policy=TaskPolicy(),
        **kwargs,
    )


def test_minimal_row_has_calendar_label_person_ref_and_no_inferred_policy():
    (row,) = plan()
    assert row == {
        "id": occurrence_id("person-1", 2030),
        "title": "Wish <person-1> a happy birthday",
        "due_date": "2030-02-28",
        "person_ids": '["person-1"]',
        "updated_at": "2030-02-28T14:00:00.000Z",
    }


def test_identity_survives_rename_refresh_and_distinguishes_year_person_bytes():
    assert occurrence_id("person-1", 2030) == "ce64b9e7f42f5f529f299a908c0d3935"
    assert occurrence_id(" péRson-1 ", 2030) == "54c37ba88b5d58cf9fcc753e0750348d"
    (original,) = plan()
    (later,) = plan_tasks(
        [person(name="<renamed>")],
        DAY,
        updated_at=STAMP + dt.timedelta(hours=8),
        retained_ids={},
        policy=TaskPolicy(),
    )
    assert original["id"] == later["id"]
    assert (
        len(
            {
                occurrence_id("person-1", 2030),
                occurrence_id("person-1", 2031),
                occurrence_id("person-2", 2030),
                occurrence_id("Person-1", 2030),
                occurrence_id(" person-1 ", 2030),
            }
        )
        == 5
    )


def test_opt_out_tombstone_and_other_days_produce_no_task():
    assert (
        plan(
            [
                person(notify_birthday=False),
                person(id="person-2", deleted_at="2030-01-01T00:00:00.000Z"),
                person(id="person-3", birthday="--03-01"),
            ]
        )
        == []
    )


@pytest.mark.parametrize("birthday", ["--02-29", "2000-02-29", "1990-02-28"])
def test_known_unknown_year_and_leap_observance(birthday):
    assert plan([person(birthday=birthday)])[0]["due_date"] == "2030-02-28"
    if birthday.endswith("02-29"):
        assert (
            plan_tasks(
                [person(birthday=birthday)],
                dt.date(2032, 2, 28),
                updated_at=STAMP,
                retained_ids={},
                policy=TaskPolicy(),
            )
            == []
        )
        assert (
            plan_tasks(
                [person(birthday=birthday)],
                dt.date(2032, 2, 29),
                updated_at=STAMP,
                retained_ids={},
                policy=TaskPolicy(),
            )[0]["due_date"]
            == "2032-02-29"
        )


@pytest.mark.parametrize(
    "birthday",
    ["--02-30", "2001-02-29", "20300228", "--2-28", "2030-02-28T00:00:00Z", "2030-13-01", "", None],
)
def test_invalid_opted_in_birthday_fails_the_plan(birthday):
    with pytest.raises(ValueError, match="birthday"):
        plan([person(birthday=birthday)])


def test_retained_occurrence_mapping_wins_and_optional_policy_is_explicit():
    (row,) = plan_tasks(
        [person()],
        DAY,
        updated_at=STAMP,
        retained_ids={("person-1", 2030): "a" * 32},
        policy=TaskPolicy(
            status="To Do", priority="Low", tags=("Chore",), project_ids=("project-1", "project-2")
        ),
    )
    assert row["id"] == "a" * 32
    assert row["status"] == "To Do" and row["priority"] == "Low"
    assert json.loads(row["tags"]) == ["Chore"]
    assert json.loads(row["project_ids"]) == ["project-1", "project-2"]
    assert "assignees" not in row


def test_invalid_mapping_and_duplicate_people_cannot_create_ambiguous_ids():
    with pytest.raises(ValueError):
        plan_tasks(
            [person()],
            DAY,
            updated_at=STAMP,
            retained_ids={("person-1", 2030): ""},
            policy=TaskPolicy(),
        )
    with pytest.raises(ValueError):
        plan([person(), person()])
    with pytest.raises(ValueError):
        plan_tasks(
            [person(), person(id="person-2")],
            DAY,
            updated_at=STAMP,
            retained_ids={("person-1", 2030): "a" * 32, ("person-2", 2030): "a" * 32},
            policy=TaskPolicy(),
        )


@pytest.mark.parametrize("changes", [{"notify_birthday": "false"}, {"id": ""}, {"name": ""}])
def test_invalid_person_cannot_be_silently_enrolled(changes):
    with pytest.raises(ValueError):
        plan([person(**changes)])


@pytest.mark.parametrize("values", [{"status": "Done"}, {"priority": "Urgent"}])
def test_policy_uses_actual_catalog_options(values):
    with pytest.raises(ValueError):
        plan_tasks([person()], DAY, updated_at=STAMP, retained_ids={}, policy=TaskPolicy(**values))


def test_naive_clock_rejected_and_aware_clock_does_not_move_due_date():
    with pytest.raises(ValueError):
        plan_tasks(
            [person()],
            DAY,
            updated_at=STAMP.replace(tzinfo=None),
            retained_ids={},
            policy=TaskPolicy(),
        )
    (row,) = plan_tasks(
        [person()],
        DAY,
        updated_at=dt.datetime(2030, 3, 1, 1, tzinfo=dt.timezone(dt.timedelta(hours=9))),
        retained_ids={},
        policy=TaskPolicy(),
    )
    assert row["due_date"] == "2030-02-28"
    assert row["updated_at"] == "2030-02-28T16:00:00.000Z"


@pytest.mark.parametrize(
    "state",
    [{"status": "Completed"}, {"status": "Canceled"}, {"deleted_at": "2030-02-28T15:00:00.000Z"}],
)
def test_lost_ack_retry_uses_only_insert_and_preserves_existing_state(state):
    # Models the published service contract, not a test of its SQL atomicity.
    saved = {}
    calls = []

    def server(request):
        assert request.url.path == "/v1/rows/insert" and request.method == "POST"
        body = json.loads(request.content)
        assert body["table"] == "tasks" and "history" not in body
        assert set(body["columns"]) == set(body["rows"][0])
        calls.append(body)
        (row,) = body["rows"]
        if not saved:
            saved.update({**row, **state, "title": "<edited title>"})
            raise httpx.ReadTimeout("lost acknowledgement", request=request)
        assert row["id"] == saved["id"]
        return httpx.Response(200, json={"inserted": [], "existing": [row["id"]], "rejected": []})

    with httpx.Client(
        base_url="https://hub.example", transport=httpx.MockTransport(server)
    ) as client:
        with pytest.raises(InsertInterrupted) as error:
            insert_tasks(client, plan())
        assert isinstance(error.value.__cause__, httpx.ReadTimeout)
        before = saved.copy()
        receipt = insert_tasks(client, plan([person(name="<renamed>")]))
    assert receipt == {"inserted": [], "existing": [before["id"]], "rejected": []}
    assert saved == before and len(calls) == 2


@pytest.mark.parametrize(
    "receipt",
    [
        None,
        {"upserted": 1},
        {"inserted": [], "existing": [], "rejected": []},
        {"inserted": ["foreign"], "existing": [], "rejected": []},
        {"inserted": ["row-1"], "existing": ["row-1"], "rejected": []},
        {"inserted": ["row-1"], "existing": [], "rejected": [{"id": "row-1"}]},
        {"inserted": [], "existing": [], "rejected": [None]},
    ],
)
def test_ambiguous_receipt_never_reports_success(receipt):
    with httpx.Client(
        base_url="https://hub.example",
        transport=httpx.MockTransport(lambda r: httpx.Response(200, json=receipt)),
    ) as client:
        with pytest.raises(InsertInterrupted, match="receipt") as error:
            insert_tasks(client, [{"id": "row-1", "title": "<task>"}])
        assert isinstance(error.value.__cause__, ValueError)


def test_chunked_partial_rejections_are_returned_to_caller():
    calls = []

    def server(request):
        rows = json.loads(request.content)["rows"]
        calls.append(len(rows))
        return httpx.Response(
            200,
            json={
                "inserted": [r["id"] for r in rows[1:]],
                "existing": [],
                "rejected": [{"id": rows[0]["id"], "rule": "write-conflict", "retryable": True}],
            },
        )

    with httpx.Client(
        base_url="https://hub.example", transport=httpx.MockTransport(server)
    ) as client:
        receipt = insert_tasks(client, [{"id": f"row-{i}"} for i in range(201)])
    assert calls == [200, 1]
    assert len(receipt["inserted"]) == 199
    assert [r["id"] for r in receipt["rejected"]] == ["row-0", "row-200"]


@pytest.mark.parametrize("status", [307, 401, 403, 404, 500])
def test_http_errors_and_redirects_never_fall_back(status):
    calls = []

    def server(request):
        calls.append(request.url)
        return httpx.Response(status, headers={"Location": "https://elsewhere.example"})

    with httpx.Client(
        base_url="https://hub.example", follow_redirects=True, transport=httpx.MockTransport(server)
    ) as client:
        with pytest.raises(InsertInterrupted) as error:
            insert_tasks(client, plan())
        assert isinstance(error.value.__cause__, httpx.HTTPStatusError)
    assert len(calls) == 1


def test_empty_batch_no_network_and_duplicates_rejected_before_first_chunk():
    def server(request):
        pytest.fail("unexpected network call")

    with httpx.Client(
        base_url="https://hub.example", transport=httpx.MockTransport(server)
    ) as client:
        assert insert_tasks(client, []) == {"inserted": [], "existing": [], "rejected": []}
        with pytest.raises(ValueError):
            insert_tasks(client, [{"id": f"row-{i}"} for i in range(201)] + [{"id": "row-0"}])


def test_insecure_endpoint_is_rejected_before_sending_anything():
    def server(request):
        pytest.fail("insecure request reached transport")

    with httpx.Client(
        base_url="http://hub.example", transport=httpx.MockTransport(server)
    ) as client:
        with pytest.raises(ValueError, match="HTTPS"):
            insert_tasks(client, plan())


@pytest.mark.parametrize("inactive", [{"notify_birthday": False}, {"deleted_at": "2030-01-01"}])
@pytest.mark.parametrize("reverse", [False, True])
def test_conflicting_duplicate_records_fail_before_filtering(inactive, reverse):
    people = [person(), person(**inactive)]
    with pytest.raises(ValueError, match="Duplicate"):
        plan(list(reversed(people)) if reverse else people)


@pytest.mark.parametrize("failure", ["timeout", "http", "receipt"])
def test_later_batch_failure_preserves_earlier_receipts(failure):
    calls = []
    first = {
        "inserted": [f"row-{i}" for i in range(1, 200)],
        "existing": [],
        "rejected": [{"id": "row-0", "rule": "required"}],
    }

    def server(request):
        calls.append(request)
        if len(calls) == 1:
            return httpx.Response(200, json=first)
        if failure == "timeout":
            raise httpx.ReadTimeout("lost acknowledgement", request=request)
        return httpx.Response(500 if failure == "http" else 200, json={})

    with httpx.Client(
        base_url="https://hub.example", transport=httpx.MockTransport(server)
    ) as client:
        with pytest.raises(InsertInterrupted) as error:
            insert_tasks(client, [{"id": f"row-{i}"} for i in range(201)])
    assert error.value.receipt == first
