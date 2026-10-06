# AGENTS.md

The native iOS app lives in `ios/`. It reads birthdays through Life Data's
supported API and schedules its own local notifications. `Package.swift`
exposes `BirthdayCore` for fast macOS tests. Its enrollment policy bundles
the reviewed Life Core public entry into the system JavaScriptCore framework.

The Python service in `app.py` remains a separately deployed daily Modal
cron (9am America/New_York), currently reading Notion and sending ntfy.
Changing it or pushing main can affect the live service.

## Native app

- `ios/project.yml` owns the generated Xcode project; never edit `.xcodeproj`.
- `ios/Core/`: date validation, reminder planning, paginated Life Data reads,
  atomic snapshot cache and notification reconciliation. No SwiftUI imports.
- `ios/App/`: SwiftUI, Keychain, UserNotifications, application lifecycle.
- Run `swift test --scratch-path /tmp/birthday-reminders-swift-build` for core
  tests, `just -f ios/justfile test` for Keychain/model/UI tests, and
  `just -f ios/justfile run` for the simulator. Derived data stays outside iCloud.
- Enrollment UX is URL plus explicit browser approval, never manual token entry.
  `EnrollmentSession` hosts random candidate generation, fingerprint-only links,
  bounded polling and generation/deadline fencing. `CoreEnrollmentPolicy` runs
  the pinned canonical policy resource; provenance is in `docs/enrollment-policy.md`.
  Production must keep `EnrollmentContract` absent until the service confirms
  deployment and configuration of its exact narrow profile. Never substitute Life UI's full-replica `/login` contract.
- Credentials belong in this app's device-only Keychain, never the bundle,
  defaults, URLs or diagnostics. Core owns exact scope/identity receipt validation;
  phone People read and Tasks writer use separate identities. Candidate cleanup
  uses POST `/v1/session`; only `{logged_out:true}` proves revocation, not 401.
- An approved installer must check its enrollment attempt before committing.
  Save the cache before replacing Keychain; failed/canceled enrollment preserves
  the previously accepted connection. Notification testing needs no enrollment.
- Source opt-ins come from Life Data. Mutes are per-phone preferences.
- Schedule at most 60 grouped birthday dates, show the renewal deadline,
  and retain cached people when refresh fails. Local notifications do not
  execute a daily task-writing job.
- Life Data task creation is not active. Tasks and Projects schemas are published;
  integrate only against that actual catalog contract; never create provisional task tables or fall
  back to writing Notion from the native app.
- Consumer access uses dedicated Life Data credentials through its API only.
  Exact-table grants are whole-table grants, not enforced column projection.
  Enforced birthday-field reads and create-only Tasks enrollment remain pending.
  No live consumer credential is bundled or provisioned; no broad fallback.
- Personal Ad Hoc delivery uses `.github/workflows/build-ios.yml`, manual only.
  `scripts/sign-ios.py` verifies profile, identity and export in a disposable
  keychain. Only per-dispatch age-encrypted IPA artifacts are uploaded, retained
  one day. Native checks run signing tests without secrets.
- Signing uses the approved Apple Signing shared-vault contract: distribution
  certificate/password and wildcard profile, read by this project's CI account.
  Apple Signing owns renewal; rotating its material affects its documented Apple
  app consumers. App runtime never receives it. Project ENV owns IOS_DEVICE_ID
  and IOS_BUNDLE_ID. This does not authorize broad Life Data access.
- Install a decrypted, verified CI IPA through `_install`, with IOS_INSTALL_HOST
  selecting the paired Mac. Local Debug requires IOS_DEVELOPMENT_TEAM and usable
  development signing; local Release is a stated-reason fallback requiring
  IOS_PROFILE. Never open windowed Xcode on the headless build host.

## Architecture rule (the one that matters)

**Business logic lives in `src/core/` as plain Python with NO Modal imports.**
Only `app.py` imports `modal` - it is the deployment shim (image, secrets,
endpoints, schedules). This keeps the logic portable: the same `core` package
runs in tests, on the mac mini via launchd, or on any future platform.

- No HTTP endpoints: the template webhook + spawned worker were deleted as
  unused. If one comes back, it MUST use `requires_proxy_auth=True` - never
  expose an unauthenticated endpoint.
- Cron: Modal is the PREFERRED home for schedules - but the Starter plan
  allows **5 deployed crons across ALL apps**, so track the budget. Overflow
  goes to GHA cron or CF Cron Triggers (see the `infra` skill).

## Stack

uv · pydantic-settings (env config) · httpx · structlog · pytest · ruff.
Config comes from env vars only: Modal Secret in the cloud, `op run` locally.
`.env.tpl` is the canonical secrets manifest (op:// refs, committed).
Instantiate `Settings()` inside functions, never at import time.

## Commands

Standard verb set (see global AGENTS.md) - the justfile is the interface,
not a script catalog; one-offs go in `scripts/` and run directly.

| Command | Purpose |
|---|---|
| `just dev` | Live-reload dev against real Modal infra (`modal serve`) |
| `just test` / `just check` / `just fmt` | pytest / ruff read-only / ruff fix |
| `just logs` | Stream deployed-app logs |
| `just sync-secrets` | Push `.env.tpl` → Modal secret store |
| `just deploy` | test + sync-secrets + `modal deploy` |

## TDD

Write the test in `tests/` first, then the `src/core/` code. `app.py` shim
functions stay thin enough to not need tests.

## Credential provisioning

`scripts/provision.py` implements `--list`, `--batches`, and
`--batch modal-token` for `op-project-bootstrap`. Modal CI credentials are
minted and verified as a pair in memory, then saved atomically to the project
vault. The operator opens the stderr approval URL in the configured remote
browser session (agents use chrome-control) and approves its code. Do not
use `modal token new` or write a temporary credential config.

Birthday Reminders owns its Modal app, runtime Secret, daily schedule, and
independently minted CI token. The CI token is stored only in its project
vault. Modal Starter personal tokens retain workspace-level permissions;
this accepted provider limitation allows independent rotation but does not
enforce access to just this app. Environment-scoped service users require
[Team or Enterprise](https://modal.com/docs/guide/service-users).

All runtime variables come from `Birthday Reminders ENV`; `.env.tpl`
references its five env-named fields. The separate CI Modal item never
reaches the runtime. The app's own Notion integration has Read and Insert
content capabilities for People, Tasks, and its specific project page;
Update content, comments, and user information are disabled.
