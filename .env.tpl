# Canonical secrets manifest — 1Password secret references only, SAFE to commit.
# Local dev:       op run --env-file=.env.tpl -- <cmd>   (see justfile)
# Push to Modal:   just sync-secrets

NOTION_API_KEY=op://Birthday-Reminders/Notion/credential
NTFY_TOPIC=op://Birthday-Reminders/ntfy/topic
PEOPLE_DATA_SOURCE_ID=op://Birthday-Reminders/Notion/people-data-source-id
TASKS_DATA_SOURCE_ID=op://Birthday-Reminders/Notion/tasks-data-source-id
PROJECT_PAGE_ID=op://Birthday-Reminders/Notion/project-page-id
