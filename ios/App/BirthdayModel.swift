import BirthdaysCore
import Foundation
import Observation
import UserNotifications

@MainActor @Observable
final class BirthdayModel {
  private(set) var connection: Connection?
  private(set) var snapshot: BirthdaySnapshot?
  private(set) var upcoming: [UpcomingBirthday] = []
  private(set) var authorization: UNAuthorizationStatus = .notDetermined
  private(set) var scheduledCount = 0
  private(set) var renewBefore: Date?
  private(set) var busy = false
  private(set) var savingPersonID: String?
  private var pendingOptInIDs: Set<String>
  var needsOptInRefresh: Bool { !pendingOptInIDs.isEmpty }
  private(set) var sortRules: [BirthdaySortRule]
  var search = ""
  var visibleBirthdays: [UpcomingBirthday] {
    BirthdayListOrder.apply(upcoming, search: search, rules: sortRules)
  }
  var canEditOptIns: Bool { connection?.enrollmentProfile?.id == BirthdaysAccess.editorProfile }
  var error: String?
  var notice: String?
  var preferences: ReminderPreferences
  private let cache: BirthdayCache
  private let credentials: ConnectionStore
  private let defaults: UserDefaults
  private let session: URLSession
  private let authorize: () async throws -> Bool
  private let notifications = LocalNotifications()
  private let notificationStore: any NotificationStore
  private let authorizationStatus: () async -> UNAuthorizationStatus

  init(
    cache: BirthdayCache = BirthdayCache(
      url: URL.applicationSupportDirectory.appendingPathComponent(
        "birthdays/birthdays.json"),
      legacyURL: URL.applicationSupportDirectory.appendingPathComponent("BirthdayReminders/birthdays.json")),
    credentials: ConnectionStore = ConnectionStore(), defaults: UserDefaults = .standard,
    session: URLSession = .shared,
    notificationStore: any NotificationStore = LocalNotifications(),
    authorizationStatus: @escaping () async -> UNAuthorizationStatus = {
      await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    },
    authorize: @escaping () async throws -> Bool = {
      try await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .sound, .badge,
      ])
    }
  ) {
    self.cache = cache
    self.credentials = credentials
    self.defaults = defaults
    self.session = session
    self.authorize = authorize
    self.notificationStore = notificationStore
    self.authorizationStatus = authorizationStatus
    sortRules = BirthdayListOrder.normalized(defaults.data(forKey: "birthday-sort-rules")
      .flatMap { try? JSONDecoder().decode([BirthdaySortRule].self, from: $0) } ?? BirthdaySortRule.defaults)
    pendingOptInIDs = Set(defaults.stringArray(forKey: "pending-opt-in-ids") ?? [])
    preferences =
      defaults.data(forKey: "reminder-preferences")
      .flatMap { try? JSONDecoder().decode(ReminderPreferences.self, from: $0) }
      ?? ReminderPreferences()
    do {
      connection = try credentials.load()
      if let saved = try cache.load(), let connection,
        saved.endpoint == connection.endpoint, saved.source == connection.source
      {
        snapshot = saved
      }
      rebuildUpcoming()
    } catch { self.error = "Saved data could not be loaded. Reconnect to Life Data." }
  }

  // Called only after EnrollmentSession validates the candidate identity/profile.
  func installApprovedConnection(
    endpoint: String, token: String, source: PeopleSource,
    enrollmentProfile: EnrollmentProfileReceipt? = nil,
    isCurrent: @escaping @MainActor () -> Bool = { true },
    accepted: @escaping @MainActor () -> Void = {}
  ) async -> Bool {
    while busy {
      guard isCurrent(), !Task.isCancelled else { return false }
      do { try await Task.sleep(for: .milliseconds(100)) } catch { return false }
    }
    guard isCurrent() else { return false }
    busy = true
    defer { busy = false }
    do {
      let endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
      let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
      let client = try LifeDataClient(endpoint: endpoint, token: token, session: session)
      let people = try await client.people(source: source,
        includeRevisions: enrollmentProfile?.id == BirthdaysAccess.editorProfile)
      let value = BirthdaySnapshot(
        endpoint: endpoint, source: source, people: people, fetchedAt: Date())
      let newConnection = Connection(endpoint: endpoint, token: token, source: source,
        enrollmentProfile: enrollmentProfile)
      try Task.checkCancellation()
      guard isCurrent() else { throw CancellationError() }
      let previousSnapshot = try? cache.load()
      do {
        try cache.save(value)
        // Keychain is the acceptance commit point. A failed cache write must
        // never replace the previously accepted credential.
        try credentials.save(newConnection)
      } catch {
        if let previousSnapshot { try? cache.save(previousSnapshot) }
        else { try? cache.clear() }
        throw error
      }
      connection = newConnection
      snapshot = value
      setNeedsOptInRefresh(false)
      accepted()
      error = nil
      rebuildUpcoming()
      await reschedule()
      return true
    } catch {
      report(error)
      return false
    }
  }

  func refresh() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    await updateAuthorization()
    if needsOptInRefresh { await reschedule() }
    guard let connection else { return }
    do {
      let client = try LifeDataClient(
        endpoint: connection.endpoint, token: connection.token, session: session)
      let people = try await client.people(source: connection.source, includeRevisions: canEditOptIns)
      let value = BirthdaySnapshot(
        endpoint: connection.endpoint, source: connection.source, people: people, fetchedAt: Date())
      try cache.save(value)
      snapshot = value
      setNeedsOptInRefresh(false)
      error = nil
    } catch { report(error) }
    rebuildUpcoming()
    await reschedule()
  }

  func saveSortRules(_ rules: [BirthdaySortRule]) {
    sortRules = BirthdayListOrder.normalized(rules)
    if let data = try? JSONEncoder().encode(sortRules) { defaults.set(data, forKey: "birthday-sort-rules") }
  }

  func setOptIn(_ person: BirthdayPerson, enabled: Bool) async {
    guard !busy, !needsOptInRefresh, canEditOptIns, let connection,
      let current = snapshot?.people.first(where: { $0.id == person.id }), current == person,
      person.enabled != enabled else { return }
    busy = true
    savingPersonID = person.id
    error = nil
    // Persist before sending: termination or a lost acknowledgment must never
    // turn an uncertain write into an automatic retry against a stale cache.
    pendingOptInIDs.insert(person.id)
    defaults.set(Array(pendingOptInIDs).sorted(), forKey: "pending-opt-in-ids")
    // Suppress this person's cached reminders before sending. An offline restart
    // cannot restore them while the retained cache is awaiting reconciliation.
    await reschedule()
    defer { busy = false; savingPersonID = nil }
    do {
      let contract = try BirthdaysAccess.editorContract()
      let client = try LifeDataClient(endpoint: connection.endpoint, token: connection.token, session: session)
      let saved = try await client.setOptIn(person, enabled: enabled, source: connection.source, contract: contract)
      let value = BirthdaySnapshot(endpoint: connection.endpoint, source: connection.source,
        people: (snapshot?.people ?? []).map { $0.id == saved.id ? saved : $0 },
        fetchedAt: snapshot?.fetchedAt ?? Date())
      // The service has confirmed the flag, so this phone must reconcile even
      // if storage is temporarily full. Keep the refresh gate on cache failure.
      snapshot = value
      rebuildUpcoming()
      try cache.save(value)
      setNeedsOptInRefresh(false)
    } catch BirthdayError.http(409) {
      error = "This person changed in Life Data. Refresh to see the latest choice before trying again."
    } catch {
      self.error = "The notification choice could not be confirmed and saved. Refresh before trying again."
    }
    await reschedule()
  }

  private func setNeedsOptInRefresh(_ value: Bool) {
    if !value { pendingOptInIDs = [] }
    defaults.set(Array(pendingOptInIDs).sorted(), forKey: "pending-opt-in-ids")
  }

  func savePreferences(_ value: ReminderPreferences) async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      _ = try ReminderPlan.make(people: [], preferences: value, now: Date())
      let data = try JSONEncoder().encode(value)
      defaults.set(data, forKey: "reminder-preferences")
      preferences = value
      rebuildUpcoming()
      await reschedule()
    } catch { report(error) }
  }

  func mute(_ person: BirthdayPerson, muted: Bool) async {
    var value = preferences
    if muted { value.mutedIDs.insert(person.id) } else { value.mutedIDs.remove(person.id) }
    await savePreferences(value)
  }

  func enableNotifications() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      _ = try await authorize()
      await reschedule()
    } catch { report(error) }
  }

  func sendTest() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      _ = try await authorize()
      await reschedule()
      guard authorization == .authorized || authorization == .provisional else { return }
      try await notifications.sendTest()
      notice = "Lock your phone or leave the app. A test notification will arrive in 10 seconds."
    } catch { report(error) }
  }

  func disconnect() {
    guard !busy else {
      error = "Wait for the current operation to finish, then disconnect."
      return
    }
    do {
      try credentials.clear()
      notifications.center.removeAllPendingNotificationRequests()
      notifications.center.removeAllDeliveredNotifications()
      connection = nil
      setNeedsOptInRefresh(false)
      snapshot = nil
      upcoming = []
      scheduledCount = 0
      renewBefore = nil
      preferences.mutedIDs = []
      defaults.set(try JSONEncoder().encode(preferences), forKey: "reminder-preferences")
      try cache.clear()
      error = nil
    } catch { report(error) }
  }

  private func updateAuthorization() async {
    authorization = await authorizationStatus()
  }

  private func reschedule() async {
    await updateAuthorization()
    scheduledCount = 0
    renewBefore = nil
    guard authorization == .authorized || authorization == .provisional else { return }
    do {
      var safePreferences = preferences
      safePreferences.mutedIDs.formUnion(pendingOptInIDs)
      let plan = try ReminderPlan.make(
        people: snapshot?.people ?? [], preferences: safePreferences, now: Date())
      scheduledCount = try await NotificationScheduler().apply(
        plan, timeZoneID: preferences.timeZoneID, store: notificationStore)
      renewBefore = plan.renewBefore
    } catch { report(error) }
  }

  private func rebuildUpcoming() {
    var displayPreferences = preferences
    displayPreferences.mutedIDs = []
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: preferences.timeZoneID) ?? .current
    let today = calendar.startOfDay(for: Date()).addingTimeInterval(-1)
    upcoming = (snapshot?.people ?? []).compactMap { person in
      let visible = BirthdayPerson(
        id: person.id, name: person.name, birthday: person.birthday, enabled: true)
      guard
        let date = try? ReminderPlan.make(
          people: [visible], preferences: displayPreferences, now: today, limit: 1
        ).reminders.first?.date
      else { return nil }
      return UpcomingBirthday(person: person, date: date)
    }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
  }

  private func report(_ error: Error) {
    if let error = error as? BirthdayError {
      self.error = error.localizedDescription
    } else if let error = error as? KeychainError {
      self.error = error.localizedDescription
    } else {
      self.error = "The operation could not finish. Check your connection and try again."
    }
  }
}
