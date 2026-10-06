# Native Birthday Reminders

The product is an iOS 17+ SwiftUI app using Life Data for birthdays and,
when its catalog contract exists, reminder tasks. The existing Notion/ntfy
service is not the target integration.

## Native app

- Connect using an HTTPS Life Data endpoint and a dedicated consumer token.
  Validate the session and reject operator/admin credentials. Store credentials
  only in Keychain. Keep endpoint, source mapping and preferences on-device.
- A configurable source maps a table's ID, display name, birthday and opt-in
  fields into birthdays. Respect tombstones. Accept YYYY-MM-DD and --MM-DD;
  reject impossible dates. Do not display invented ages for unknown years.
- Show upcoming birthdays, opt-in status, last successful refresh, notification
  permission and scheduling coverage. The app edits reminder preferences, not
  the underlying people directory. Personal records never enter the repository.
- Cache the last complete successful read in Application Support. A failed or
  partial refresh preserves that cache and reports an error. Credentials and
  HTTP bodies must not appear in diagnostics. Disconnect clears the cache and
  pending notifications.
- Schedule local notifications at 09:00 by default in the user's chosen
  timezone (initially the device timezone). Users can change the time and zone.
  February 29 is observed on February 28 in non-leap years.
- Combine same-day birthdays into one reminder. Schedule the next 60 dates,
  searching up to five calendar years ahead, reserving capacity for a test
  notification. Display the earliest unscheduled birthday as the renewal
  deadline. Refresh schedules on launch/foreground, successful sync and settings
  changes. Do not promise background refresh or unlimited scheduling coverage.
- A test-notification button schedules a short-delay notification so delivery
  can be checked with the app closed. Permission denial links to Settings.
- Preserve the old schedule if planning fails. Reconcile requests by stable
  identifiers; expose any scheduling error instead of claiming success.

## Life Data integration boundary

Use only the supported session and rows APIs. Paginate reads, reject repeated
cursors, and fail closed on malformed rows. Source mapping is user configuration,
not a personal schema installed by this app. Existing people records supply
opt-in decisions; the native app may mute reminders locally without changing
the source. Changes to the authoritative directory use its own UI.

Exact-table scopes permit whole-table access. Enforced People projection and
create-only Tasks enrollment remain prerequisites for live credentials. No
broad access fallback is authorized. The app never receives infrastructure
credentials.

## Tasks dependency

The published Tasks catalog supplies required `title`, date-or-datetime
`due_date`/`completed_date`, optional `person_ids` and `project_ids` multi-refs,
and optional status, priority and tags. Schema publication is separate from
historical dedupe coverage, credentials, and authority cutover. Do not create a
competing table, write to Notion as a fallback, or claim live task creation.

Once enrollment and dedupe review are ready, a server-side daily job will insert a task once
per person/year using the supported insert-if-absent API. The actual required
fields, person/project references, status, priority, tags, date semantics and
ID constraints come from that catalog. Preserve completed or edited tasks on
retry. Phone background execution is not responsible for daily task creation.

The adapter uses `/v1/rows/insert` with explicit IDs, declared columns and row
objects. It validates complete, disjoint inserted/existing/rejected receipts;
errors never trigger push/patch fallbacks. Batches are at most 200 rows.
Same-ID retries preserve canceled and tombstoned rows as well as completed rows.
The service owns atomicity and lineage; the consumer grants no provenance access.

IDs are lowercase 32-hex UUIDv5 in a fixed app-owned namespace, using UTF-8 compact
JSON `["v1","birthday",personId,occurrenceYear]`. Person IDs are byte-exact.
Retained migration occurrence mappings override generated IDs. Birthday due dates
are actual occurrence labels, including February 29 observance, regardless of
refresh time or saved-view day boundaries. New task policy is explicit caller
configuration, not inferred from historical catalog options.

## Completion criteria

Automated date, pagination, persistence and scheduling tests; simulator UI
verification; signed phone install and observed background notification; real
Life Data birthdays sync; real tasks integration once available. Retire the old
service only after replacement verification and authorization. Do not mark the
whole project complete while tasks or phone delivery remain unverified.
