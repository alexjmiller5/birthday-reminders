# birthday-reminders

Opt-in birthday reminders sourced from my Notion People DB. A daily Modal
cron checks for people with the "Birthday Notifications" checkbox whose
birthday is today, sends an iOS push via [ntfy](https://ntfy.sh), and
auto-creates a high-priority task in my Notion Tasks DB.

Built from the `modal-service` template: authenticated HTTP webhook, spawned
background workers, and cron — all infrastructure declared in `app.py` as
code.

## Layout

```
app.py            Modal shim — image, secrets, endpoints, schedules
src/core/         business logic (plain Python, portable)
tests/            pytest
.env.tpl          secrets manifest (1Password op:// refs, committed)
justfile          dev / test / sync-secrets / deploy
```

## Secrets

`.env.tpl` is the canonical manifest — op:// references into the
`Birthday-Reminders` 1Password vault only, never plaintext:

- `NOTION_API_KEY` — Notion internal integration secret
- `NTFY_TOPIC` — ntfy topic for iOS push. Optional: defaults to
  `bday-56hqsioQJ5-YM-ju7wfgag`, a randomly generated unguessable string
  (random topics are ntfy.sh's only access control — anyone who knows the
  topic can read it, so treat it like a password and override via the
  1Password item if it ever leaks)

Local dev: `op run --env-file=.env.tpl -- <cmd>`. Cloud: `just sync-secrets`
pushes to the Modal secret store.

## Manual setup (Alex)

This scaffold was created under the restricted `claude-code` service account,
which cannot create vaults or service accounts. Run these yourself:

```
op vault create "Birthday-Reminders"
OUT=$(op service-account create "birthday-reminders-ci" --vault "Birthday-Reminders:read_items" --format json </dev/null)
op item create --category "API Credential" --title "birthday-reminders-ci SA Token" --vault Personal "token[concealed]=$(echo "$OUT" | jq -r .token)" </dev/null
gh secret set OP_SERVICE_ACCOUNT_TOKEN --repo alexjmiller5/birthday-reminders --body "$(op read 'op://Personal/birthday-reminders-ci SA Token/token')"
```

Then create these items in the `Birthday-Reminders` vault (names/fields must
match `.env.tpl` and `.github/workflows/deploy.yml`):

- `Notion` — field `credential`: a Notion internal integration secret with
  access to the People and Tasks DBs
- `ntfy` — field `topic`: the ntfy topic subscribed on the iPhone
- `Modal Birthday-Reminders` — fields `token-id` / `token-secret`: Modal
  deploy token for CI

Other one-time steps that cannot be codified:

- Install the [ntfy iOS app](https://apps.apple.com/app/ntfy/id1625396347)
  and subscribe to the `NTFY_TOPIC` topic (default
  `bday-56hqsioQJ5-YM-ju7wfgag`) — without this, pushes go nowhere
- `uv run modal token new` — authenticate this machine with Modal
- Mint a Proxy Auth Token in the Modal dashboard for HTTP callers
  (iPhone Shortcuts)
