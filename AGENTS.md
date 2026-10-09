# AGENTS.md

The native iOS app lives in `ios/`. It reads birthdays through Soma's
supported API and schedules its own local notifications. `Package.swift`
exposes `BirthdaysCore` for fast macOS tests. Its enrollment policy bundles
the reviewed Soma Core public entry into the system JavaScriptCore framework.

The Python Soma Tasks adapter is dormant. There is no server entrypoint,
active birthday cron or automatic deployment workflow. Main pushes run checks.

## Native app

The shipped bundle ID is `com.alexmiller.birthday-reminders`. Keep it stable
for installed identity and Keychain continuity. Task occurrence IDs and their
application namespace are stable across display-name changes.

- `ios/project.yml` owns the generated Xcode project; never edit `.xcodeproj`.
- `ios/Core/`: date validation, reminder planning, paginated Soma reads,
  atomic snapshot cache and notification reconciliation. No SwiftUI imports.
- `ios/App/`: SwiftUI, Keychain, UserNotifications, application lifecycle.
- Run `swift test --scratch-path /tmp/birthdays-swift-build` for core
  tests, `just -f ios/justfile test` for Keychain/model/UI tests, and
  `just -f ios/justfile run` for the simulator. Derived data stays outside iCloud.
- Enrollment UX is URL plus explicit browser approval, never manual token entry.
  `EnrollmentSession` hosts random candidate generation, fingerprint-only links,
  bounded polling and generation/deadline fencing. `CoreEnrollmentPolicy` runs
  the pinned canonical policy resource; provenance is in `docs/enrollment-policy.md`.
  New connections use profile `birthdays-editor-v1` and exact scopes declared
  in `BirthdaysAccess`: seven People read columns and patch-only notify_birthday.
  Existing reader connections retain five-column reads until explicit browser
  reenrollment. Never substitute Iris's full-replica `/login` contract.
- Credentials belong in this app's device-only Keychain, never the bundle,
  defaults, URLs or diagnostics. Core owns exact scope/identity receipt validation;
  phone People read and Tasks writer use separate identities. Candidate cleanup
  uses POST `/v1/session`; only `{logged_out:true}` proves revocation, not 401.
- An approved installer must check its enrollment attempt before committing.
  Save the cache before replacing Keychain; failed/canceled enrollment preserves
  the previously accepted connection. Notification testing needs no enrollment.
- Source opt-ins come from Soma. Toggle writes use its conditional patch
  with cached updated_at/hub_at revisions and canonical live session validation.
  Confirmed saves reconcile notifications; uncertain/conflicting writes persist
  a refresh gate across restarts. No automatic write retries. Mutes remain
  per-phone preferences. Search is transient; ordered reversible sorts persist.
- Schedule at most 60 grouped birthday dates, show the renewal deadline,
  and retain cached people when refresh fails. Local notifications do not
  execute a daily task-writing job.
- `src/core/soma_tasks.py` plans Tasks rows against the published catalog and
  calls `/v1/rows/create` with the pinned canonical Soma Core Python validator.
  It is not connected to the cron. Live activation requires the exact configured
  policy/credential receipt, complete People reads,
  reviewed historical occurrence mappings and explicit creation policy. Never use a provisional
  table or write Notion as a native fallback.
- Task IDs use the durable application namespace in `soma_tasks.py`, UUIDv5
  over UTF-8 compact JSON `["v1","birthday",personId,occurrenceYear]`, with
  byte-exact person IDs. Preserve retained occurrence mappings first. Keep
  birthday due dates as calendar labels; edit timestamps do not alter identity.
  Never rotate the namespace with credentials or overwrite existing tasks.
  Retained targets always use adopted intent, even when equal to the generated
  ID; missing adopted targets fail closed. Missing dates are skipped.
  `created` confirms the atomic task/origin result; `existing` makes no creation
  attribution. Errors stop requests and retain earlier validated receipts.
- Consumer access uses dedicated Soma credentials through its API only.
  Exact-table grants are whole-table grants, not enforced column projection.
  The phone reader and daily Tasks writer enroll independently. The writer's
  exact policy-bound create grant and five People read-column grants must pass
  canonical live session validation before use. Credentials are never bundled;
  provisioning does not activate the cron. No broad fallback.
- Personal Ad Hoc delivery uses `.github/workflows/build-ios.yml`, manual only.
  `scripts/sign-ios.py` verifies profile, identity and export in a disposable
  keychain. Only per-dispatch age-encrypted IPA artifacts are uploaded, retained
  one day. Native checks run signing tests without secrets.
- Signing uses the approved Apple Signing shared-vault contract: distribution
  certificate/password and wildcard profile, read by this project's CI account.
  Apple Signing owns renewal; rotating its material affects its documented Apple
  app consumers. App runtime never receives it. Project ENV owns IOS_DEVICE_ID
  and IOS_BUNDLE_ID. This does not authorize broad Soma access.
- Install a decrypted, verified CI IPA through `_install`, with IOS_INSTALL_HOST
  selecting the paired Mac. Local Debug requires IOS_DEVELOPMENT_TEAM and usable
  development signing; local Release is a stated-reason fallback requiring
  IOS_PROFILE. Never open windowed Xcode on the headless build host.

## Python Tasks adapter

Business logic lives in `src/core/` as plain Python with no provider runtime
imports. `soma_tasks.py` is a library, not an active task-writing job. Activation
requires the verified dedupe and scoped service contracts above, plus an explicit
runtime implementation. Never add a Notion or ntfy fallback.

## Stack and commands

uv, httpx, pinned Soma Core validators, pytest and ruff. Run `just test`,
`just check` and `just fmt` for tests, read-only checks and formatting.
Write tests before changing the adapter. Use the native justfile for app builds
and installation. Native releases remain manually dispatched; CI does not
activate server-side tasks.

## Credentials

`.env.tpl` contains no server runtime secrets while the Tasks writer is dormant.
The separate writer identity must stay narrowly scoped and must never be reused
by the phone. Project signing inputs are declared in the manual iOS workflow;
provider credentials never reach the native app or the Tasks library.
