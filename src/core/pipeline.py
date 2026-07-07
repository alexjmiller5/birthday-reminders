"""Business logic — plain Python, no Modal imports. Runs anywhere."""

import structlog

log = structlog.get_logger()


def run(payload: dict) -> dict:
    log.info("processing", payload=payload)
    # Placeholder — birthday pipeline (Notion People query -> ntfy push -> task creation)
    # lands in the next work item.
    return {"ok": True, "received": payload}
