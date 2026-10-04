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

The currently documented table scopes are dataset-wide. No live credential
is provisioned until the narrowest available scope is verified and any broader
access is explicitly accepted. The app never receives infrastructure credentials.

## Tasks dependency

The Life Data tasks table is being prepared separately. Its absence must not
disable native birthday notifications. Do not create a competing tasks table,
write to Notion as a fallback, or claim task creation is working.

After its catalog is available, a server-side daily job will insert a task once
per person/year using the supported insert-if-absent API. The actual required
fields, person/project references, status, priority, tags, date semantics and
ID constraints come from that catalog. Preserve completed or edited tasks on
retry. Phone background execution is not responsible for daily task creation.

## Completion criteria

Automated date, pagination, persistence and scheduling tests; simulator UI
verification; signed phone install and observed background notification; real
Life Data birthdays sync; real tasks integration once available. Retire the old
service only after replacement verification and authorization. Do not mark the
whole project complete while tasks or phone delivery remain unverified.
