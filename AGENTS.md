# AGENTS.md

The native iOS app lives in `ios/`. It reads birthdays through Life Data's
supported API and schedules its own local notifications. `Package.swift`
exposes the dependency-free `BirthdayCore` library for fast macOS tests.

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
- Credentials belong in this app's Keychain, never the bundle, defaults or
  fixtures. Endpoint and source mapping are supplied through the connection UI.
- Source opt-ins come from Life Data. Mutes are per-phone preferences.
- Schedule at most 60 grouped birthday dates, show the renewal deadline,
  and retain cached people when refresh fails. Local notifications do not
  execute a daily task-writing job.
- Life Data task creation is not implemented. Implement against its actual
  published catalog contract; never create provisional task tables or fall
  back to writing Notion from the native app.
- Consumer access uses dedicated Life Data credentials through its API only.
  Current table scopes are dataset-wide; broader access needs explicit approval
  before provisioning. No live native credential is bundled or provisioned.
- Phone builds require external IOS_DEVELOPMENT_TEAM and IOS_DEVICE_ID values;
  Ad Hoc release also requires IOS_PROFILE and a usable signing identity.
  IOS_INSTALL_HOST selects the paired installer Mac. Never open windowed Xcode
  on the headless build host.

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
