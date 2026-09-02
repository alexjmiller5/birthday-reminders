"""Modal deployment shim — ALL infrastructure lives here, as code.

Business logic stays in src/core/ (plain Python, no Modal imports) so the
same package runs on the mac mini, in tests, or anywhere else. This file
only maps that logic onto Modal: image, secrets, schedules.
"""

import modal

APP_NAME = "birthday-reminders"  # also the Modal secret name (see justfile sync-secrets)

app = modal.App(APP_NAME)

image = (
    modal.Image.debian_slim(python_version="3.13")
    .uv_sync(extra_options="--no-dev")  # reads pyproject.toml + uv.lock; skip dev group
    # add_local_dir, NOT add_local_python_source: the latter can't resolve
    # packages under src/ layout, and this also carries non-.py data files.
    .add_local_dir("src/core", remote_path="/root/core", ignore=["**/__pycache__"])
)

secrets = [modal.Secret.from_name(APP_NAME)]


# Cron budget (Starter plan: 5 deployed crons TOTAL across all apps): as of
# 2026-09-02 notion-automations has 1 — this one makes 2/5.
@app.function(
    image=image,
    secrets=secrets,
    timeout=600,
    schedule=modal.Cron("0 9 * * *", timezone="America/New_York"),
)
def daily_birthday_check() -> dict:
    """9am New York daily: today's birthdays -> ntfy push + Notion task each."""
    from core.pipeline import run

    return run()
