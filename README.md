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

Life Data supports exact-table grants, but these permit whole-table access;
requesting fewer columns is not an authorization boundary. Enrollment is
waiting for enforced birthday-column reads and a separate create-only Tasks
credential for the daily writer. No broader credential is provisioned. The native
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

**Life Data Tasks has a published schema; daily task creation is not active.**
The tested adapter in `src/core/life_tasks.py` plans opted-in birthday tasks and
uses the supported atomic `/v1/rows/insert` route. Existing, completed, canceled
and tombstoned rows are preserved by that service contract. Retries reuse the
same person/year ID even after a rename or credential change. Retained historical
occurrence mappings take precedence over generated IDs.

The adapter writes a date-only `due_date`, JSON-array `person_ids` and optional
`project_ids`, plus a separate UTC millisecond edit timestamp. Status, priority,
tags and projects are omitted unless explicitly configured; schema options do
not choose a user's creation policy. Identity uses UUIDv5 with the fixed app
namespace and UTF-8 compact JSON `["v1","birthday",personId,occurrenceYear]`.
Person IDs are not trimmed, case-folded or Unicode-normalized.

Conflicting duplicate People records fail planning before opt-in filtering.
HTTP or receipt failures raise `InsertInterrupted` with earlier validated
batch receipts and the original cause, so prior rejections remain available.
Replaying the same IDs is safe after a lost acknowledgement.

Before connecting the daily cron, establish narrow caller enrollment, complete
People reads, historical dedupe coverage, the service's lineage contract, and
reviewed opt-ins and creation policy. Mock transport tests verify the adapter's
retry and receipt handling, not the service's database atomicity or live access.
The native app does not create tasks as a Notion fallback; phone background
execution is not responsible for the daily writer.

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

Personal release builds use the manual **Build iOS Ad Hoc** workflow. Configure
`IOS_DEVICE_ID` and `IOS_BUNDLE_ID` in the project's ENV item, and run bootstrap
to give this project's CI account the documented Apple Signing vault access.
The workflow reads the shared distribution certificate and Ad Hoc profile,
validates that they authorize the selected bundle and device, signs in a
disposable keychain, and verifies the exported app.

Generate a temporary age identity locally (`age-keygen -o <private-path>`),
then dispatch with its public recipient as `artifact_recipient`. Keep the
private identity local. After CI passes, download the encrypted artifact within
one day, decrypt it locally, verify the IPA SHA256 against the workflow log,
and put it at `ios/build/BirthdayReminders.ipa`. Never upload a plaintext IPA.
Remove the temporary identity after decryption and the transfer copies after
installation. Workflow dispatch requires the workflow to exist on the default
branch; merging this PR also triggers the existing service deploy and needs
owner approval.

Install the verified artifact without rebuilding:

```sh
IOS_INSTALL_HOST=<paired-mac> IOS_DEVICE_ID=<enrolled-device> \
  just -f ios/justfile _install build/BirthdayReminders.ipa
```

Local Debug builds require native developer enrollment, accessible signing,
`IOS_DEVELOPMENT_TEAM`, `IOS_DEVICE_ID`, and `IOS_BUNDLE_ID`; use
`just -f ios/justfile build`. Local Release signing is a fallback with a stated
reason and also requires `IOS_PROFILE` and an accessible distribution identity.
Never commit team, device, profile, or private signing values.

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
