"""Per-birthday actions: ntfy iOS push + high-priority Notion task. No Modal imports.

Both actions are non-throwing on expected failure modes so one person's
failure never blocks the rest of the run.
"""

import datetime

import httpx
import structlog

log = structlog.get_logger()

_PAGES_URL = "https://api.notion.com/v1/pages"


def _notion_headers(api_key: str) -> dict:
    return {
        "Authorization": f"Bearer {api_key}",
        "Notion-Version": "2026-03-11",
        "Content-Type": "application/json",
    }


def send_push(name: str, ntfy_topic: str) -> bool:
    """iOS push via ntfy.sh. Returns False on failure instead of raising."""
    try:
        resp = httpx.post(
            f"https://ntfy.sh/{ntfy_topic}",
            data=f"It's {name}'s birthday today — send them a message!",
            headers={"Title": "Birthday reminder"},
            timeout=30,
        )
    except httpx.HTTPError as exc:
        log.error("ntfy_push_failed", name=name, error=str(exc))
        return False
    if resp.status_code != 200:
        log.error("ntfy_push_failed", name=name, status=resp.status_code)
        return False
    log.info("ntfy_push_sent", name=name)
    return True


def create_birthday_task(
    name: str,
    api_key: str,
    today: datetime.date,
    tasks_data_source_id: str,
    project_page_id: str,
) -> str | None:
    """Create a 'Wish <Name> a happy birthday' task due today; skip if it already
    exists (the cron may re-run). Returns the new page id, or None if skipped."""
    headers = _notion_headers(api_key)
    tasks_query_url = f"https://api.notion.com/v1/data_sources/{tasks_data_source_id}/query"
    title = f"Wish {name} a happy birthday"

    query = {
        "filter": {
            "and": [
                {"property": "Name", "title": {"equals": title}},
                {"property": "Due Date", "date": {"equals": today.isoformat()}},
            ]
        },
        "page_size": 1,
    }
    resp = httpx.post(tasks_query_url, headers=headers, json=query, timeout=30)
    resp.raise_for_status()
    if resp.json()["results"]:
        log.info("task_already_exists", name=name, title=title)
        return None

    payload = {
        "parent": {"type": "data_source_id", "data_source_id": tasks_data_source_id},
        "properties": {
            "Name": {"title": [{"text": {"content": title}}]},
            "Priority": {"select": {"name": "High"}},  # exact existing option in Tasks schema
            "Due Date": {"date": {"start": today.isoformat()}},
            "Project": {"relation": [{"id": project_page_id}]},
            "Notes": {"rich_text": [{"text": {"content": "Auto-created by birthday-reminders"}}]},
        },
    }
    resp = httpx.post(_PAGES_URL, headers=headers, json=payload, timeout=30)
    resp.raise_for_status()
    page_id = resp.json()["id"]
    log.info("task_created", name=name, page_id=page_id)
    return page_id
