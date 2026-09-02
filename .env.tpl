# Canonical secrets manifest — 1Password secret references only, SAFE to commit.
# Local dev:       op run --env-file=.env.tpl -- <cmd>   (see justfile)
# Push to Modal:   just sync-secrets

NOTION_API_KEY=op://Birthday-Reminders/Birthday-Reminders Notion API Key/credential
NTFY_TOPIC=op://Birthday-Reminders/Birthday-Reminders ntfy Topic/topic
PEOPLE_DATA_SOURCE_ID=op://Birthday-Reminders/Birthday-Reminders Notion API Key/people-data-source-id
TASKS_DATA_SOURCE_ID=op://Birthday-Reminders/Birthday-Reminders Notion API Key/tasks-data-source-id
PROJECT_PAGE_ID=op://Birthday-Reminders/Birthday-Reminders Notion API Key/project-page-id
