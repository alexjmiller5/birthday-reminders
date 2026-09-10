# birthday-reminders

Opt-in birthday reminders sourced from a Notion People DB. A daily Modal
cron checks for people with the "Birthday Notifications" checkbox whose
birthday is today, sends an iOS push via [ntfy](https://ntfy.sh), and
auto-creates a high-priority task in a Notion Tasks DB.

Built from the `modal-service` template — all infrastructure declared in
`app.py` as code. The only entrypoint is a daily cron
(`modal.Cron("0 9 * * *", timezone="America/New_York")` — timezone-aware, so
DST is handled). The template's HTTP webhook + spawned worker were deleted as
unused; restore from the template if an HTTP caller ever appears.

Cron budget: Modal Starter allows 5 deployed crons across ALL apps. As of
2026-09-02 the deployed crons are `notion-automations` (1) and this app — 2/5.

## Layout

```
app.py            Modal shim — image, secrets, schedule
src/core/         business logic (plain Python, portable)
tests/            pytest
.env.tpl          secrets manifest (1Password op:// refs, committed)
justfile          dev / test / sync-secrets / deploy
```

## Secrets

`.env.tpl` is the canonical manifest — op:// references into the project's
1Password vault only. All five runtime fields live in its single
`Birthday Reminders ENV` item:

- `NOTION_API_KEY` - this app's own Notion integration with Read and Insert
  content capabilities, access to the People and Tasks databases, and access
  to the specific project page used by its task relation
- `NTFY_TOPIC` — ntfy topic for iOS push, `<random-topic>`. Generate one
  (e.g. `openssl rand -base64 18 | tr -d '+/='`) — random topics are
  ntfy.sh's only access control, so anyone who knows the topic can read it;
  treat it like a password and rotate it if it ever leaks
- `PEOPLE_DATA_SOURCE_ID` — Notion data source id of the People DB
- `TASKS_DATA_SOURCE_ID` — Notion data source id of the Tasks DB
- `PROJECT_PAGE_ID` — Notion page id of the project the created tasks
  relate to

Local dev: `op run --env-file=.env.tpl -- <cmd>`. Cloud: `just sync-secrets`
pushes to the Modal secret store.

## Manual setup

Run bootstrap with your repository name. This repo's `.env.tpl` uses the
vault name `Birthday Reminders`:

```bash
op-project-bootstrap .env.tpl --repo <owner>/<repo>
```

Bootstrap reads `.env.tpl` and the deploy workflow to create the project
vault, environment item, dedicated Modal CI token, and read-only CI service
account. Fill the environment fields with this project's own credentials.

`scripts/provision.py` emits a Modal approval URL and verification code on
stderr. Open that URL in the configured remote browser session (agents use
chrome-control) and approve the code. It verifies the new token pair in
memory; bootstrap saves both fields to `Birthday Reminders CI Modal Token`
at once through JSON stdin. It never opens a local browser or writes a
provider config or temporary credential file.

Install the [ntfy iOS app](https://apps.apple.com/app/ntfy/id1625396347) and
subscribe to the configured `NTFY_TOPIC` topic to receive notifications.

### Required Notion schema

Property names are matched exactly (see `src/core/birthdays.py` and
`src/core/actions.py`):

- **People DB**: `Name` (title), `Birthday` (date), `Birthday Notifications`
  (checkbox)
- **Tasks DB**: `Name` (title), `Due Date` (date), `Priority` (select with a
  `High` option), `Tags` (multi_select with a `Chore` option), `Project`
  (relation), `Notes` (rich text)
