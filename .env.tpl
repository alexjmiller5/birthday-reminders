# Canonical secrets manifest — 1Password secret references only, SAFE to commit.
# Local dev:       op run --env-file=.env.tpl -- <cmd>   (see justfile)
# Push to Modal:   just sync-secrets

NOTION_API_KEY=op://Birthday Reminders/Birthday Reminders ENV/NOTION_API_KEY
NTFY_TOPIC=op://Birthday Reminders/Birthday Reminders ENV/NTFY_TOPIC
PEOPLE_DATA_SOURCE_ID=op://Birthday Reminders/Birthday Reminders ENV/PEOPLE_DATA_SOURCE_ID
TASKS_DATA_SOURCE_ID=op://Birthday Reminders/Birthday Reminders ENV/TASKS_DATA_SOURCE_ID
PROJECT_PAGE_ID=op://Birthday Reminders/Birthday Reminders ENV/PROJECT_PAGE_ID
