# Canonical secrets manifest — 1Password secret references only, SAFE to commit.
# Local dev:       op run --env-file=.env.tpl -- <cmd>   (see justfile)
# Push to Modal:   just sync-secrets

NOTION_API_KEY=op://Birthdays/Birthdays ENV/NOTION_API_KEY
NTFY_TOPIC=op://Birthdays/Birthdays ENV/NTFY_TOPIC
PEOPLE_DATA_SOURCE_ID=op://Birthdays/Birthdays ENV/PEOPLE_DATA_SOURCE_ID
TASKS_DATA_SOURCE_ID=op://Birthdays/Birthdays ENV/TASKS_DATA_SOURCE_ID
PROJECT_PAGE_ID=op://Birthdays/Birthdays ENV/PROJECT_PAGE_ID
