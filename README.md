# Birthdays

Native iPhone birthday reminders backed by Soma, with notifications
scheduled on the phone. There is no active server-side birthday job. The Python
Soma Tasks adapter is tested but not connected to a scheduler.

## Native app

The iOS 17+ app searches names without case or accent differences and sorts by
name, next birthday, or shared notification opt-in. The Sort sheet combines,
reorders and reverses rules; upcoming first is the default. Sort choices persist
on this phone. You can also choose a reminder time and timezone. It stores
its connection in Keychain and a complete birthday snapshot in Application
Support. Failed syncs retain the previous snapshot.

Connect with your **Soma URL**, then choose **Continue in browser** and
open the approval link. Review the birthday read and notification opt-in edit grants and approve in
your browser; return to the app while it finishes connecting. No token copying
is required. The app uses the service-owned `birthdays-editor-v1`
profile and rejects broader grants. An unsupported hub cannot fall back to
full-access enrollment.

The client generates its own random candidate credential, places only
its SHA-256 fingerprint/code in the canonical approval link, and checks for
approval with a bounded session request. It saves only the approved identity
and profile to device-only Keychain. Cancel, replacement or expiry invalidate
late responses; failed enrollment preserves an existing accepted connection.
The service owns the exact scope and approval receipt. Phone access is limited
to birthday fields; the Tasks writer has a separate identity. Requested columns
alone do not restrict a whole-table grant.

Birthdays may be `YYYY-MM-DD` or `--MM-DD` when the year is unknown. The list's
**Birthday notifications** toggle updates only `notify_birthday` in Soma.
It shows the confirmed choice after saving, then reschedules this phone.
Concurrent edits and uncertain saves require a refresh before another attempt;
they are never automatically retried. Pending changes temporarily suppress
that person's reminders, including after an offline restart, until refreshed.
Existing read-only connections keep
working: choose **Enable opt-in editing** for browser approval with a new
device credential. Canceling or failing approval preserves the old connection.
Names and birthday dates remain editable through Soma. Existing per-phone
mutes remain effective and show an explicit **Enable on this phone** action.
The native app has no analytics and never receives provider/admin
credentials. A replacement phone enrolls independently. Disconnect clears this
phone's saved connection, cache and notifications. Revocation stops a credential
at the service; forgetting local data alone does not prove revocation.

Allow notifications when asked. **No Soma sign-in is needed to test
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

**Soma Tasks has a published schema; daily task creation is not active.**
The tested adapter in `src/core/soma_tasks.py` plans opted-in birthday tasks and
uses the policy-bound `/v1/rows/create` route for an atomic task and origin.
Existing, completed, canceled
and tombstoned rows are preserved by that service contract. Retries reuse the
same person/year ID even after a rename or credential change. Retained historical
occurrence mappings take precedence over generated IDs, using explicit adopted
intent. A missing adopted target fails instead of creating a replacement.

The adapter writes a date-only `due_date`, JSON-array `person_ids` and optional
`project_ids`, plus a separate UTC millisecond edit timestamp. Status, priority,
tags and projects are omitted unless explicitly configured; schema options do
not choose a user's creation policy. Identity uses UUIDv5 with the fixed app
namespace and UTF-8 compact JSON `["v1","birthday",personId,occurrenceYear]`.
Person IDs are not trimmed, case-folded or Unicode-normalized.

Conflicting duplicate People records fail planning before opt-in filtering.
Missing birthdays are skipped without inventing dates. HTTP or receipt failures
raise `CreationInterrupted` with earlier validated receipts and the original
cause. The adapter stops and never retries automatically. A caller may replay
identical intent after a lost acknowledgement; an `existing` receipt establishes
presence only and never claims that this caller created the row.

The adapter defaults to Soma Core's pinned canonical Python validator through
an injectable boundary; no handwritten fallback exists. The
[policy provenance](docs/creation-policy.md) records the exact library pin.
Activation requires separately verified configured policy and credential receipts;
credential provisioning alone does not enable daily creation.

Before connecting the daily cron, establish narrow caller enrollment, complete
People reads, historical dedupe coverage, the service's lineage contract, and
reviewed opt-ins and creation policy. Mock transport tests verify the adapter's
retry and receipt handling, not the service's database atomicity or live access.
The native app does not create tasks as a Notion fallback; phone background
execution is not responsible for the daily writer.

## Development and installation

Requires Xcode and XcodeGen. The bundled [Soma Core enrollment policy](docs/enrollment-policy.md)
runs in the system JavaScriptCore framework; no replica runtime is included.

```sh
swift test --scratch-path /tmp/birthdays-swift-build
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
and put it at `ios/build/Birthdays.ipa`. Never upload a plaintext IPA.
Remove the temporary identity after decryption and the transfer copies after
installation. Workflow dispatch requires the workflow to exist on the default
branch. Pushes to main run native and Python checks; releases are manual.

Install the verified artifact without rebuilding:

```sh
IOS_INSTALL_HOST=<paired-mac> IOS_DEVICE_ID=<enrolled-device> \
  just -f ios/justfile _install build/Birthdays.ipa
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

## Python Tasks adapter

`src/core/soma_tasks.py` contains the dormant task planner and creation adapter.
`just test` and `just check` run pytest and ruff. There is no server entrypoint,
cron, automatic deployment workflow or notification service in this repository.
Task-writer activation requires the readiness checks described above and a new,
explicitly configured runtime. Phone notifications work independently.

## Secrets

The native app uses browser enrollment and its own Keychain credential.
`.env.tpl` has no runtime secrets while the server-side writer is inactive.
The manual iOS signing workflow declares its own project-owned signing inputs;
bootstrap uses those workflow references when configuring CI. Future server
configuration belongs in the project's ENV item and must use its independently
revocable, narrowly scoped Soma writer credential.
