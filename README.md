# Birthday Reminders

Native iPhone birthday reminders backed by Life Data, with notifications
scheduled on the phone. The Python service in this repository is a separate
Notion/ntfy deployment and is not used by the native app.

## Native app

The iOS 17+ app shows upcoming birthdays, honors source opt-ins, supports
per-phone mutes, and lets you choose a reminder time and timezone. It stores
its connection in Keychain and a complete birthday snapshot in Application
Support. Failed syncs retain the previous snapshot.

Connect with your Life Data HTTPS URL and a dedicated app credential with
read access. Operator/admin credentials are rejected. The connection form
lets you map your people table's name, birthday and opt-in columns; IDs and
soft-deletion fields follow Life Data's standard API contract. Birthdays may
be `YYYY-MM-DD` or `--MM-DD` when the year is unknown. Edit people and opt-ins
in Life Data; local mute controls affect this phone only.

The current Life Data `tables:read` scope permits dataset-wide reads, not
only birthdays. Review that access before issuing a credential. The native
app sends no record writes, has no analytics, and never receives infrastructure
credentials. On a replacement phone, install and connect again; Keychain
credentials are device-only. Disconnect removes saved connection, cache and
notifications, leaving Life Data records intact.

Allow notifications when asked. Settings includes **Send test notification**:
leave the app or lock the phone and wait 10 seconds. If permission was denied,
use **Open notification settings**. Focus modes and notification summaries
remain controlled by iOS.

Reminders default to 09:00 in the initial device timezone. The chosen timezone
is fixed until changed in Settings. February 29 uses February 28 in non-leap
years. Same-day birthdays share one notification. The next 60 dates are
scheduled, looking through five subsequent calendar years. The app displays
when to reopen it to renew coverage; it syncs and reschedules on foreground.
Already scheduled notifications work offline with the app closed. Source
changes take effect after a successful sync, not instantly in the background.

**Life Data task creation is pending its tasks-table contract.** The native
app does not create Notion tasks as a fallback. A server-side task writer is
required for daily creation independently of whether the phone app opens.

## Development and installation

Requires Xcode and XcodeGen. No third-party runtime dependencies.

```sh
swift test --scratch-path /tmp/birthday-reminders-swift-build
just -f ios/justfile check
just -f ios/justfile test
just -f ios/justfile run
```

`ios/project.yml` generates the Xcode project. `IOS_TEST_DESTINATION` chooses
the simulator, and `IOS_DERIVED_DATA` chooses a build directory outside the
source tree. The default simulator is iPhone 17.

For a phone build, enroll your device and developer account through Apple's
supported interfaces and supply `IOS_DEVELOPMENT_TEAM` and `IOS_DEVICE_ID`.
Run `just -f ios/justfile build` for a development install. Set
`IOS_INSTALL_HOST` to the paired Mac's SSH host when building elsewhere.
For a release install, supply `IOS_PROFILE`, install a distribution signing
identity accessible to the build shell, and run `just -f ios/justfile deploy`.
That exports `ios/build/BirthdayReminders.ipa` before attempting installation.
Set `IOS_BUNDLE_ID` to the bundle identifier enrolled for your app/profile.
Never commit team, device or profile values.

Tests include birthday boundaries, pagination, malformed responses,
notification reconciliation, Keychain persistence, failed-sync retention,
onboarding and real simulator notification delivery after leaving the app.
The icon uses [Tabler gift](https://api.iconify.design/tabler:gift.svg), MIT;
license included in `ios/App/Tabler-LICENSE.txt`.

## Python service

`app.py` deploys the daily Modal cron; `src/core/` contains its Python logic.
`just test` and `just check` run pytest and ruff. Pushing `main` runs its deploy
workflow. Keep it running until the native replacement and task writer are
verified and the service change is authorized.

## Secrets

`.env.tpl` is the canonical manifest - op:// references into the project's
1Password vault only. All five runtime fields live in its single
`Birthday Reminders ENV` item:

- `NOTION_API_KEY` - this app's own Notion integration with Read and Insert
  content capabilities, access to the People and Tasks databases, and access
  to the specific project page used by its task relation
- `NTFY_TOPIC` - ntfy topic for iOS push, `<random-topic>`. Generate one
  (e.g. `openssl rand -base64 18 | tr -d '+/='`) - random topics are
  ntfy.sh's only access control, so anyone who knows the topic can read it;
  treat it like a password and rotate it if it ever leaks
- `PEOPLE_DATA_SOURCE_ID` - Notion data source id of the People DB
- `TASKS_DATA_SOURCE_ID` - Notion data source id of the Tasks DB
- `PROJECT_PAGE_ID` - Notion page id of the project the created tasks
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
