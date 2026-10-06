# Birthday Reminders

Native iPhone birthday reminders backed by Life Data, with notifications
scheduled on the phone. The Python service in this repository is a separate
Notion/ntfy deployment and is not used by the native app.

## Native app

The iOS 17+ app shows upcoming birthdays, honors source opt-ins, supports
per-phone mutes, and lets you choose a reminder time and timezone. It stores
its connection in Keychain and a complete birthday snapshot in Application
Support. Failed syncs retain the previous snapshot.

Enrollment is being updated to **Life Data URL + browser approval**. No manual
credential copying is required or offered by the new connection screen. This
version keeps approval unavailable until Life Core publishes its narrow
birthday profile. The existing full-access device approval route must not be
used as a fallback. The separately installed older release may still show its
credential field; do not use that field to provision a broader token.

The prepared client generates its own random candidate credential, places only
its SHA-256 fingerprint/code in the canonical approval link, and checks for
approval with a bounded session request. It saves only the approved identity
and profile to device-only Keychain. Cancel, replacement or expiry invalidate
late responses; failed enrollment preserves an existing accepted connection.
The service owns the exact scope and approval receipt. Phone access is limited
to birthday fields; the Tasks writer has a separate identity. Requested columns
alone do not restrict a whole-table grant.

Birthdays may be `YYYY-MM-DD` or `--MM-DD` when the year is unknown. Edit people
and opt-ins in Life Data; local mute controls affect this phone only. The native
app sends no record writes, has no analytics, and never receives provider/admin
credentials. A replacement phone enrolls independently. Disconnect clears this
phone's saved connection, cache and notifications. Revocation stops a credential
at the service; forgetting local data alone does not prove revocation.

Allow notifications when asked. **No Life Data sign-in is needed to test
notifications.** Settings includes **Send test notification**:
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
