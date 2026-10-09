"""Synthetic consumer tests using the pinned canonical policy and HTTP boundary."""

import datetime as dt
import json

import httpx
import pytest

from core import soma_tasks as tasks

DAY = dt.date(2030, 2, 28)
STAMP = dt.datetime(2030, 2, 28, 14, tzinfo=dt.UTC)
POLICY = {
    "id": "birthdays-tasks-v1",
    "revision": "8231fa18788c8a475e08a1e788623c1d94872961636afff2e0924396a7fbd68c",
}
SCOPES = [f"rows:create:{POLICY['id']}:{POLICY['revision']}"]
TARGET = "ce64b9e7f42f5f529f299a908c0d3935"


def person(**changes):
    return tasks.BirthdayPerson(
        **{
            "id": "person-1",
            "name": "<person-1>",
            "birthday": "--02-28",
            "notify_birthday": True,
            **changes,
        }
    )


def plan(people=None, **changes):
    return tasks.plan_tasks(
        [person()] if people is None else people,
        **{
            "day": DAY,
            "updated_at": STAMP,
            "retained_ids": {},
            "policy": tasks.TaskPolicy(),
            **changes,
        },
    )


def session(**changes):
    return {
        "scopes": SCOPES,
        "capabilities": {
            "rowCreation": {"protocol": "atomic-origin-v1", "policies": [POLICY]},
        },
        **changes,
    }


def created(request):
    return {
        "kind": "created",
        "policy": POLICY,
        "id": request["target"]["id"],
        "revision": {"updated_at": request["updatedAt"], "hub_at": "2030-02-28T14:00:01.000Z"},
        "originId": f"people:{request['sourceId']}:{request['target']['id']}",
    }


def run(server, plans=None, **changes):
    with httpx.Client(
        base_url="https://hub.example", transport=httpx.MockTransport(server), follow_redirects=True
    ) as client:
        return tasks.create_tasks(
            client,
            plan() if plans is None else plans,
            policy=POLICY,
            scopes=SCOPES,
            **changes,
        )


def test_planner_preserves_identity_and_emits_minimal_generated_intent():
    assert plan() == [
        {
            "sourceId": "person-1",
            "occurrenceKey": 2030,
            "target": {"kind": "generated", "id": TARGET},
            "updatedAt": "2030-02-28T14:00:00.000Z",
            "values": {
                "title": "Wish <person-1> a happy birthday",
                "due_date": "2030-02-28",
                "person_ids": '["person-1"]',
            },
        }
    ]
    assert tasks.occurrence_id(" péRson-1 ", 2030) == "54c37ba88b5d58cf9fcc753e0750348d"
    assert plan([person(name="<renamed>")])[0]["target"]["id"] == TARGET
    assert (
        len(
            {
                tasks.occurrence_id(p, y)
                for p, y in [
                    ("person-1", 2030),
                    ("person-1", 2031),
                    ("Person-1", 2030),
                    (" person-1 ", 2030),
                ]
            }
        )
        == 4
    )


def test_retained_target_is_adopted_even_when_equal_to_generated_id():
    assert plan(retained_ids={("person-1", 2030): TARGET})[0]["target"] == {
        "kind": "adopted",
        "id": TARGET,
    }
    assert (
        plan(retained_ids={("person-1", 2030): "historical-id"})[0]["target"]["id"]
        == "historical-id"
    )
    with pytest.raises(ValueError):
        plan(retained_ids={("person-1", 2030): ""})


@pytest.mark.parametrize("birthday", [None, ""])
def test_selected_people_without_dates_are_skipped_without_blocking_known_birthdays(birthday):
    assert len(plan([person(birthday=birthday), person(id="person-2")])) == 1


@pytest.mark.parametrize("birthday", ["--02-30", "2001-02-29", "--2-28", "2030-02-28T00:00:00Z"])
def test_malformed_dates_fail_instead_of_inventing_a_date(birthday):
    with pytest.raises(ValueError, match="birthday"):
        plan([person(birthday=birthday)])


def test_opt_out_deleted_and_other_day_are_skipped_and_duplicates_still_fail():
    assert (
        plan(
            [
                person(notify_birthday=False),
                person(id="p2", deleted_at="2030-01-01"),
                person(id="p3", birthday="--03-01"),
            ]
        )
        == []
    )
    for people in [
        [person(), person(notify_birthday=False)],
        [person(notify_birthday=False), person()],
    ]:
        with pytest.raises(ValueError, match="Duplicate"):
            plan(people)


def test_leap_observance_and_edit_timezone_do_not_change_calendar_label():
    assert plan([person(birthday="--02-29")])[0]["values"]["due_date"] == "2030-02-28"
    assert plan([person(birthday="--02-29")], day=dt.date(2032, 2, 28)) == []
    assert plan([person(birthday="--02-29")], day=dt.date(2032, 2, 29))[0]["occurrenceKey"] == 2032
    assert (
        plan(updated_at=dt.datetime(2030, 3, 1, 1, tzinfo=dt.timezone(dt.timedelta(hours=9))))[0][
            "values"
        ]["due_date"]
        == "2030-02-28"
    )
    with pytest.raises(ValueError):
        plan(updated_at=STAMP.replace(tzinfo=None))


def test_optional_fields_only_when_explicit_and_catalog_values_checked():
    values = plan(
        policy=tasks.TaskPolicy(
            status="To Do", priority="Low", tags=("Chore",), project_ids=("project-1",)
        )
    )[0]["values"]
    assert values["status"] == "To Do" and values["priority"] == "Low"
    assert values["tags"] == '["Chore"]' and values["project_ids"] == '["project-1"]'
    for policy in [tasks.TaskPolicy(status="Done"), tasks.TaskPolicy(priority="Urgent")]:
        with pytest.raises(ValueError):
            plan(policy=policy)


def test_session_preflight_and_single_create_use_canonical_contract():
    calls = []

    def server(request):
        calls.append((request.method, request.url.path))
        if request.method == "GET":
            return httpx.Response(200, json=session())
        body = json.loads(request.content)
        assert body == {"policy": POLICY, **plan()[0]}
        return httpx.Response(200, json=created(body))

    receipt = run(server)
    assert calls == [("GET", "/v1/session"), ("POST", "/v1/rows/create")]
    assert receipt["created"][0]["originId"] == f"people:person-1:{TARGET}"
    assert receipt["existing"] == []


@pytest.mark.parametrize(
    "data",
    [
        session(scopes=["full"]),
        session(scopes=SCOPES + ["tables:write:tasks"]),
        session(scopes=SCOPES * 2),
        session(capabilities={}),
        session(
            capabilities={
                "rowCreation": {
                    "protocol": "atomic-origin-v1",
                    "policies": [{"id": POLICY["id"], "revision": "b" * 64}],
                }
            }
        ),
        session(capabilities={**session()["capabilities"], "governance": {}}),
    ],
)
def test_unavailable_stale_or_broad_session_never_writes(data):
    def server(request):
        assert request.method == "GET"
        return httpx.Response(200, json=data)

    with pytest.raises(tasks.CreationInterrupted):
        run(server)


@pytest.mark.parametrize(
    "change",
    [
        {"id": "foreign"},
        {"policy": {"id": "different", "revision": "a" * 64}},
        {"originId": "invented"},
        {"kind": "unknown"},
        {"extra": True},
        {"revision": {"updated_at": "2030-02-28T14:00:02.000Z", "hub_at": "bad"}},
    ],
)
def test_malformed_receipt_is_indeterminate_and_never_success(change):
    def server(request):
        if request.method == "GET":
            return httpx.Response(200, json=session())
        return httpx.Response(200, json={**created(json.loads(request.content)), **change})

    with pytest.raises(tasks.CreationInterrupted) as error:
        run(server)
    assert error.value.receipt == {"created": [], "existing": []}


@pytest.mark.parametrize("status", [307, 401, 403, 409, 422, 503])
def test_adopted_error_never_tries_generated_fallback_or_redirect(status):
    calls = []

    def server(request):
        calls.append(request.url.path)
        if request.method == "GET":
            return httpx.Response(200, json=session())
        assert json.loads(request.content)["target"] == {"kind": "adopted", "id": "old-task"}
        return httpx.Response(
            status,
            json={"error": "adopted_missing"},
            headers={"Location": "https://elsewhere.example"},
        )

    with pytest.raises(tasks.CreationInterrupted):
        run(server, plan(retained_ids={("person-1", 2030): "old-task"}))
    assert calls == ["/v1/session", "/v1/rows/create"]


def test_adopted_created_claim_is_rejected():
    def server(request):
        return httpx.Response(
            200, json=session() if request.method == "GET" else created(json.loads(request.content))
        )

    with pytest.raises(tasks.CreationInterrupted):
        run(server, plan(retained_ids={("person-1", 2030): TARGET}))


def test_lost_ack_retry_preserves_target_and_existing_has_no_creation_attribution():
    calls = []

    def server(request):
        if request.method == "GET":
            return httpx.Response(200, json=session())
        body = json.loads(request.content)
        calls.append(body)
        if len(calls) == 1:
            raise httpx.ReadTimeout("lost acknowledgment", request=request)
        return httpx.Response(200, json={"kind": "existing", "policy": POLICY, "id": TARGET})

    with pytest.raises(tasks.CreationInterrupted):
        run(server)
    result = run(server)
    assert calls[0] == calls[1]
    assert result == {
        "created": [],
        "existing": [{"kind": "existing", "policy": POLICY, "id": TARGET}],
    }


def test_later_failure_retains_prior_receipt_and_stops_remaining_requests():
    calls = []

    def server(request):
        if request.method == "GET":
            return httpx.Response(200, json=session())
        body = json.loads(request.content)
        calls.append(body)
        if len(calls) == 2:
            raise httpx.ReadTimeout("uncertain", request=request)
        return httpx.Response(200, json=created(body))

    with pytest.raises(tasks.CreationInterrupted) as error:
        run(server, plan([person(), person(id="p2"), person(id="p3")]))
    assert len(calls) == 2
    assert error.value.receipt["created"][0]["id"] == TARGET
    assert error.value.receipt["existing"] == []


def test_empty_duplicate_and_insecure_requests_fail_before_network():
    def server(request):
        pytest.fail("unexpected network")

    assert run(server, []) == {"created": [], "existing": []}
    with pytest.raises(ValueError):
        run(server, plan() * 2)
    with httpx.Client(
        base_url="http://hub.example", transport=httpx.MockTransport(server)
    ) as client:
        with pytest.raises(ValueError, match="HTTPS"):
            tasks.create_tasks(client, plan(), policy=POLICY, scopes=SCOPES)


@pytest.mark.parametrize("changes", [{"notify_birthday": "false"}, {"id": ""}, {"name": ""}])
def test_invalid_person_cannot_be_silently_enrolled(changes):
    with pytest.raises(ValueError):
        plan([person(**changes)])


def test_conflicting_adopted_ids_fail_before_any_write():
    with pytest.raises(ValueError):
        plan(
            [person(), person(id="p2")],
            retained_ids={("person-1", 2030): "same", ("p2", 2030): "same"},
        )


@pytest.mark.parametrize("year", [True, "2030", 0, 10000])
def test_occurrence_year_is_an_integer_calendar_year(year):
    with pytest.raises(ValueError):
        tasks.occurrence_id("person-1", year)


def test_adopted_existing_succeeds_without_lineage_or_creation_claim():
    def server(request):
        if request.method == "GET":
            return httpx.Response(200, json=session())
        assert json.loads(request.content)["target"] == {"kind": "adopted", "id": "old-task"}
        return httpx.Response(200, json={"kind": "existing", "policy": POLICY, "id": "old-task"})

    assert run(server, plan(retained_ids={("person-1", 2030): "old-task"})) == {
        "created": [],
        "existing": [{"kind": "existing", "policy": POLICY, "id": "old-task"}],
    }


@pytest.mark.parametrize("status", [307, 401, 403, 503])
def test_failed_session_preflight_never_sends_a_create_or_follows_redirect(status):
    calls = []

    def server(request):
        calls.append(str(request.url))
        return httpx.Response(status, headers={"Location": "https://elsewhere.example"})

    with pytest.raises(tasks.CreationInterrupted):
        run(server)
    assert calls == ["https://hub.example/v1/session"]


def test_actual_python_validator_accepts_tuple_scope_input():
    from types import SimpleNamespace

    from soma.creation import validate_creation_receipt, validate_creation_session

    validator = SimpleNamespace(
        validate_session=validate_creation_session, validate_receipt=validate_creation_receipt
    )
    calls = []

    def server(request):
        calls.append(request.url.path)
        if request.method == "GET":
            return httpx.Response(200, json=session())
        return httpx.Response(200, json=created(json.loads(request.content)))

    with httpx.Client(
        base_url="https://hub.example", transport=httpx.MockTransport(server)
    ) as client:
        result = tasks.create_tasks(
            client, plan(), policy=POLICY, scopes=tuple(SCOPES), validator=validator
        )
    assert calls == ["/v1/session", "/v1/rows/create"]
    assert result["created"][0]["id"] == TARGET
