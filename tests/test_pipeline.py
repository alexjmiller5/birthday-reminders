import datetime

from core.birthdays import Person
from core.pipeline import run

TODAY = datetime.date(2026, 7, 7)

ALICE = Person(page_id="p1", name="Alice", birthday=datetime.date(1990, 7, 7))
BOB = Person(page_id="p2", name="Bob", birthday=datetime.date(1985, 12, 25))


def _setup(mocker, people):
    mocker.patch.dict(
        "os.environ",
        {
            "NOTION_API_KEY": "secret_test",
            "NTFY_TOPIC": "test-topic",
            "PEOPLE_DATA_SOURCE_ID": "people-ds",
            "TASKS_DATA_SOURCE_ID": "tasks-ds",
            "PROJECT_PAGE_ID": "project-page",
        },
    )
    mocker.patch("core.pipeline.query_people", return_value=people)
    push = mocker.patch("core.pipeline.send_push", return_value=True)
    task = mocker.patch("core.pipeline.create_birthday_task", return_value="task-id")
    return push, task


def test_run_pushes_and_creates_task_for_each_birthday(mocker):
    push, task = _setup(mocker, [ALICE, BOB])
    result = run(today=TODAY)
    push.assert_called_once_with("Alice", "test-topic")
    task.assert_called_once_with("Alice", "secret_test", TODAY, "tasks-ds", "project-page")
    assert result == {
        "ok": True,
        "birthdays": [{"name": "Alice", "pushed": True, "task_id": "task-id"}],
    }


def test_run_no_birthdays_does_nothing(mocker):
    push, task = _setup(mocker, [BOB])
    result = run(today=TODAY)
    push.assert_not_called()
    task.assert_not_called()
    assert result == {"ok": True, "birthdays": []}


def test_run_one_failure_does_not_block_others(mocker):
    carol = Person(page_id="p3", name="Carol", birthday=datetime.date(1992, 7, 7))
    push, task = _setup(mocker, [ALICE, carol])
    push.side_effect = [False, True]
    result = run(today=TODAY)
    assert push.call_count == 2
    assert task.call_count == 2
    assert [b["pushed"] for b in result["birthdays"]] == [False, True]
