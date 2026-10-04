# Native Birthday Reminders Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deliver native birthday notifications backed by Life Data.

**Architecture:** A dependency-free Swift core handles birthdays, HTTP reads and
cache persistence. SwiftUI and UserNotifications own the phone experience.
The future task writer is a separate server-side consumer of the tasks catalog.

**Tech Stack:** Swift, SwiftUI, Foundation, UserNotifications, Security, XcodeGen.

**Spec:** ../specs/2026-10-04-native-birthdays-design.md

## Global constraints

iOS 17+. No personal data or credentials in source. No third-party runtime
dependencies or analytics. No live writes to a provisional tasks schema.
Existing service deployment requires separate authorization before pushing main.

## Review focus

Invalid dates must not normalize silently. A partial paginated read must not
erase reminders. A failed sync must preserve cache. Renewal coverage must never
exceed the first omitted birthday. Credentials must not follow redirects.

## Task 1: Birthday and notification planning

Files: `Package.swift`, `ios/Core/Birthday.swift`, `ios/Core/ReminderPlan.swift`,
`ios/CoreTests/BirthdayTests.swift`.

- [x] Write and run failing tests for unknown birth year, invalid dates, leap-day
  handling, same-day grouping, past reminder exclusion and the 60-request limit.
- [x] Implement `BirthdayDate`, `BirthdayPerson`, `ReminderPreferences` and
  `ReminderPlan.make(people:preferences:now:limit:)` with stable date identifiers.
- [x] Run `swift test`; mutation-check date validity and capacity boundaries.

## Task 2: Life Data and local persistence

Files: `ios/Core/LifeDataClient.swift`, `ios/Core/BirthdayCache.swift`, core tests.

- [x] Test the actual HTTP adapter with URLProtocol fixtures: pagination,
  tombstones, invalid payloads, 401, repeated cursors, rejected admin credentials
  and redirects. Assert requests contain only configured columns.
- [x] Implement complete read snapshots and atomic Codable cache replacement.
- [x] Verify failed reads preserve the previous on-disk snapshot.

## Task 3: Native app and notifications

Files: `ios/project.yml`, `ios/justfile`, `ios/App/*`, `ios/AppTests/*`.

- [x] Adapt the iOS template build interface; keep generated products outside
  the source tree and all signing values external.
- [x] Implement Keychain connection, upcoming list, local mutes, reminder time
  and timezone settings, permission recovery, last-sync and coverage displays.
- [x] Reconcile real notification requests and support a short-delay test.
- [x] Build and exercise the app in the simulator, including relaunch persistence.

## Task 4: Connect and finish

- [ ] Verify allowed consumer token scopes, enroll the app and sync real birthdays.
- [ ] Once tasks exists, read its catalog and implement/test the daily insert-only
  task writer, including a retry after a lost response and completed-task reuse.
- [ ] Sign/install on the phone and observe the test notification with app closed.
- [ ] Update README and AGENTS, commit all changes, push an authorized branch,
  verify CI, and retire the old notification pipeline after replacement approval.
