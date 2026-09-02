# AGENTS.md

Python service deployed on Modal: a single daily cron (9am America/New_York,
timezone-aware `modal.Cron`) that runs the birthday pipeline.

## Architecture rule (the one that matters)

**Business logic lives in `src/core/` as plain Python with NO Modal imports.**
Only `app.py` imports `modal` — it is the deployment shim (image, secrets,
endpoints, schedules). This keeps the logic portable: the same `core` package
runs in tests, on the mac mini via launchd, or on any future platform.

- No HTTP endpoints: the template webhook + spawned worker were deleted as
  unused. If one comes back, it MUST use `requires_proxy_auth=True` — never
  expose an unauthenticated endpoint.
- Cron: Modal is the PREFERRED home for schedules — but the Starter plan
  allows **5 deployed crons across ALL apps**, so track the budget. Overflow
  goes to GHA cron or CF Cron Triggers (see the `infra` skill).

## Stack

uv · pydantic-settings (env config) · httpx · structlog · pytest · ruff.
Config comes from env vars only: Modal Secret in the cloud, `op run` locally.
`.env.tpl` is the canonical secrets manifest (op:// refs, committed).
Instantiate `Settings()` inside functions, never at import time.

## Commands

Standard verb set (see global AGENTS.md) — the justfile is the interface,
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
