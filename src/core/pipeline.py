"""Daily birthday run — plain Python, no Modal imports. Runs anywhere."""

import datetime

import structlog

from core.actions import create_birthday_task, send_push
from core.birthdays import query_people, todays_birthdays
from core.config import Settings

log = structlog.get_logger()


def run(today: datetime.date | None = None) -> dict:
    """Fetch opted-in people, find today's birthdays, push + create a task for each."""
    settings = Settings()
    # ponytail: date.today() is UTC in the cloud; at a 9am New York cron that's
    # always the same calendar date as New York, so no tz math needed.
    today = today or datetime.date.today()
    people = query_people(settings.notion_api_key)
    celebrants = todays_birthdays(people, today)
    log.info("birthday_check", people=len(people), birthdays=len(celebrants), date=str(today))
    birthdays = [
        {
            "name": p.name,
            "pushed": send_push(p.name, settings.ntfy_topic),
            "task_id": create_birthday_task(p.name, settings.notion_api_key, today),
        }
        for p in celebrants
    ]
    return {"ok": True, "birthdays": birthdays}
