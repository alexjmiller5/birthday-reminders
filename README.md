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
1Password vault only, never plaintext:

- `NOTION_API_KEY` — Notion internal integration secret
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

One-time steps that cannot be codified. Substitute your own vault and repo
names (this repo's `.env.tpl` uses the vault name `Birthday-Reminders`):

```
op vault create "<vault>"
OUT=$(op service-account create "<project>-ci" --vault "<vault>:read_items" --format json </dev/null)
op item create --category "API Credential" --title "<Project> CI op Service Account Token" --vault Personal "token[concealed]=$(echo "$OUT" | jq -r .token)" </dev/null
gh secret set OP_SERVICE_ACCOUNT_TOKEN --repo <owner>/<repo> --body "$(op read 'op://Personal/<Project> CI op Service Account Token/token')"
```

Then create these items in the vault (names/fields must match `.env.tpl`
and `.github/workflows/deploy.yml`):

- `Birthday-Reminders Notion API Key` — field `credential`: a Notion internal integration secret with
  access to the People and Tasks DBs; fields `people-data-source-id` /
  `tasks-data-source-id` / `project-page-id`: the Notion IDs from `.env.tpl`
- `Birthday-Reminders ntfy Topic` — field `topic`: `<random-topic>` — generate one (e.g.
  `openssl rand -base64 18 | tr -d '+/='`) and treat it like a password
- `Birthday-Reminders CI Modal Token` — fields `token-id` / `token-secret`: Modal
  deploy token for CI

Other steps:

- Install the [ntfy iOS app](https://apps.apple.com/app/ntfy/id1625396347)
  and subscribe to the `NTFY_TOPIC` topic — without this, pushes go nowhere
- `uv run modal token new` — authenticate the machine with Modal

### Required Notion schema

Property names are matched exactly (see `src/core/birthdays.py` and
`src/core/actions.py`):

- **People DB**: `Name` (title), `Birthday` (date), `Birthday Notifications`
  (checkbox)
- **Tasks DB**: `Name` (title), `Due Date` (date), `Priority` (select with a
  `High` option), `Tags` (multi_select with a `Chore` option), `Project`
  (relation), `Notes` (rich text)
